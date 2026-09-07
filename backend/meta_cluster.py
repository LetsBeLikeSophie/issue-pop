# -*- coding: utf-8 -*-
"""
이슈 클러스터를 한 번 더 묶는 2단계(메타) 클러스터링 (v0).

clustering.py의 cluster_articles()가 원본 기사 461건을 87개 안팎의
"이슈"로 묶어주는데, 이슈가 90개 가까이 되니 flat한 목록으로는 한눈에
안 들어온다는 피드백을 받았어요. 원본 기사(461건, 노이즈 많음)를 더
낮은 threshold로 다시 묶는 건 이미 시도해봤다가 버림 — 문자 유사도가
스케일에 취약해서(threshold를 낮추면 percolation 재발, 예: 92건짜리
아티팩트가 114건으로 더 커짐) 실측으로 확인함.

대신 "이미 만들어진 87개 이슈 자체"를 문서 하나씩으로 보고 한 번 더
complete-linkage 클러스터링을 돌리는 게 훨씬 안전했어요 — 입력이 461개
노이즈 낀 문장이 아니라 87개의 이미 정제된(같은 이슈 기사들이 뭉친)
텍스트 덩어리라서 스케일 문제가 훨씬 덜함.

**2026-08-24: 임베딩으로 교체하면서 문서 표현 방식도 바꿈.** clustering.py가
문자 n-gram TF-IDF에서 문장 임베딩으로 바뀌었는데, 예전처럼 클러스터 안
"모든 기사 텍스트를 이어붙여서" 하나의 긴 문서로 만들면 문제가 생김 —
임베딩 모델은 입력 길이 제한이 있어서 기사가 많은 클러스터는 뒷부분이
잘려나감. 대신 클러스터 안 각 기사를 따로 임베딩한 뒤 평균 벡터(mean
pooling)로 그 클러스터를 대표하게 함 — 길이 제한과 무관하고, "그
클러스터에 속한 기사들이 전반적으로 어떤 의미 공간에 있는지"를 더
안정적으로 표현함.

**스팸비율 필터**: 원래 "곽빈"이라는 92건/2매체짜리 잔여 아티팩트
클러스터 때문에 만든 방어 로직이었음. 나중에 알고 보니 그 원인의 상당
부분은 클러스터링 버그가 아니라 데이터 버그였음 — 한겨레 RSS의
summary 필드에 실제 요약 대신 썸네일 이미지용 HTML `<table>` 태그가
그대로 들어있어서, 무관한 한겨레 기사들이 "문체가 비슷해서"가 아니라
이 HTML 조각이 겹쳐서 하나로 묶이고 있었음(text_utils.py에서 고침).
이 버그를 고친 뒤로는 스팸비율에 걸리는 클러스터가 거의 안 나오지만
(2026-08-24 라이브 실측: 245개 중 0개), 혹시 모를 다른 종류의 아티팩트에
대한 안전망으로 필터는 그대로 남겨둠.
"""

from __future__ import annotations

from collections import defaultdict

import numpy as np
from sklearn.cluster import AgglomerativeClustering
from sklearn.metrics.pairwise import cosine_similarity

from category import classify_category
from embedding_utils import embed
from keyword_extraction import build_global_df, extract_keywords, split_articles_by_keywords
from text_utils import clean_summary, clean_title, extract_proper_nouns

SPAM_RATIO_LIMIT = 10.0  # article_count/outlet_count가 이보다 크면 메타클러스터링에서 제외


def _cluster_embedding(cluster: dict) -> np.ndarray:
    """클러스터 안 기사들을 각각 임베딩한 뒤 평균 벡터로 그 클러스터를 대표시킴."""
    texts = [
        f"{clean_title(a['title'])} {clean_summary(a.get('summary', ''))}"
        for a in cluster["articles"]
    ]
    article_embeddings = embed(texts)
    return article_embeddings.mean(axis=0)


def group_into_super_clusters(
    clusters: list[dict], threshold: float = 0.30
) -> list[dict]:
    """이슈 클러스터 리스트를 받아 슈퍼그룹으로 한 번 더 묶어요.

    Args:
        clusters: cluster_articles()가 반환한 이슈 클러스터 리스트.
        threshold: 메타 레벨 코사인 유사도 임계값. 실측(2026-08-24, 라이브
            460건 기준) 0.30 근처에서 245개 이슈 → 100개 슈퍼그룹으로
            줄고 카테고리도 대체로 일관됨. 평균 벡터끼리의 유사도라
            개별 기사 유사도(이슈 레벨 threshold=0.45)보다 절대적인
            값 자체는 낮게 나오는 경향이 있어서 직접 비교하면 안 됨.

    Returns:
        슈퍼그룹 리스트. 각 슈퍼그룹은:
        {
            "label": str,          # 대표 이슈의 키워드 (그룹 내 outlet_count 1등)
            "category": str,       # 대표 이슈의 카테고리
            "article_count": int,  # 그룹 내 전체 기사 수 합
            "outlet_count": int,   # 그룹 내 전체 매체 수(중복 제거)
            "clusters": [cluster, ...],  # 원본 이슈 클러스터들 (article_count 내림차순)
        }
        outlet_count 내림차순 정렬.
    """
    if not clusters:
        return []

    normal = [
        c for c in clusters if c["article_count"] / c["outlet_count"] <= SPAM_RATIO_LIMIT
    ]
    excluded = [
        c for c in clusters if c["article_count"] / c["outlet_count"] > SPAM_RATIO_LIMIT
    ]

    groups: list[list[dict]] = [[c] for c in excluded]  # 제외된 건 단독 그룹으로

    if len(normal) == 1:
        groups.append(normal)
    elif len(normal) > 1:
        vectors = np.vstack([_cluster_embedding(c) for c in normal])
        sim_matrix = cosine_similarity(vectors)
        distance = np.clip(1 - sim_matrix, 0, None)
        np.fill_diagonal(distance, 0)
        model = AgglomerativeClustering(
            n_clusters=None,
            metric="precomputed",
            linkage="complete",
            distance_threshold=1 - threshold,
        ).fit(distance)

        by_label: dict[int, list[dict]] = defaultdict(list)
        for i, label in enumerate(model.labels_):
            by_label[int(label)].append(normal[i])
        groups.extend(by_label.values())

    super_clusters = []
    for member_clusters in groups:
        member_clusters = sorted(member_clusters, key=lambda c: -c["article_count"])
        primary = max(member_clusters, key=lambda c: c["outlet_count"])
        outlets: set[str] = set()
        for c in member_clusters:
            outlets.update(c["outlets"].keys())

        super_clusters.append(
            {
                "label": primary["keyword"],
                "category": primary["category"],
                "article_count": sum(c["article_count"] for c in member_clusters),
                "outlet_count": len(outlets),
                "clusters": member_clusters,
            }
        )

    super_clusters.sort(key=lambda g: (-g["outlet_count"], -g["article_count"]))
    return super_clusters


# 아래는 "슈퍼그룹"(위 group_into_super_clusters, 계층 구조 — 지금 UI에서 안 씀)과는
# 다른 목적: 진짜로 같은 사건인데 1차 클러스터링(threshold=0.45, complete-linkage)이
# 놓쳐서 별개 이슈로 갈라진 걸 찾아 "완전히 합침"(article_count/outlet_count까지
# 하나로 재계산). 2026-08-26 실사용 피드백: "8명"(네팔 홍수 한국인 실종, 정부
# 대응 위주 보도)과 "남동발전"(같은 사고, 소속 회사 위주 보도)이 랭킹 1·2위를
# 나눠 차지함 — 같은 사건인데 프레이밍이 달라서 개별 기사쌍 유사도가 들쭉날쭉
# 하고, complete-linkage는 "가장 안 닮은 기사쌍"까지 threshold를 넘어야 하니
# 못 합쳐졌음.
_GENERIC_ANCHOR_STOPWORDS = {"유니콘", "팩토리"}  # 실측에서 우연히 겹쳐 오탐 냈던 범용 단어


def merge_duplicate_clusters(
    clusters: list[dict], all_articles: list[dict], threshold: float = 0.60
) -> list[dict]:
    """1차 클러스터링이 놓친 "같은 사건, 다른 프레이밍" 이슈들을 사후에 합침.

    처음엔 클러스터 평균 임베딩 유사도만으로 합쳐봤는데, "스타트업"(투자
    소식 모음)처럼 원래도 여러 스타트업 기사가 느슨하게 묶인 클러스터가
    유사도만으로는 무관한 다른 클러스터까지 끌어당겼음(범용 업계 용어가
    많아서). 그래서 유사도(threshold, 기본 0.60)와 함께 "두 클러스터가
    고유명사를 실제로 공유하는지"도 같이 요구함 — 진짜 같은 사건이면
    인물/기관/지명 같은 구체적인 이름을 공유하는 경우가 많아서.

    합칠 그룹을 고를 때 Union-Find(체이닝)로 하면 "장미란"(실종 사건)이
    "이준석"(정당 대표 사퇴)까지 딸려오는 percolation이 재발함(전체
    파이프라인이 애초에 complete-linkage를 쓰기로 한 이유와 같은 문제,
    clustering.py 상단 주석 참고) — 그래서 여기도 같은 원칙을 씀. 다만
    complete-linkage(가장 먼 쌍 기준)는 너무 엄격해서 "8명"↔"남동발전"
    같은 원래 타겟 케이스조차 다 못 합쳤음 — average-linkage(평균 기준)로
    바꾸니 그 케이스는 합치면서도 percolation은 안 생겼음(실측 확인).

    한계: "유니콘"/"팩토리"처럼 우연히 여러 클러스터에 겹쳐 나오는 범용
    단어는 발견하는 대로 _GENERIC_ANCHOR_STOPWORDS에 추가해서 대응함
    (text_utils.py의 _USER_WORDS와 같은 방식 — 완벽히 막을 수는 없고
    발견되는 대로 보완). "광주"처럼 지명이 야구장 소재지와 축구팀 연고지
    양쪽에 다 나오는 것 같은 드문 우연의 일치는 아직 남아있을 수 있음.
    """
    if len(clusters) <= 1:
        return clusters

    n = len(clusters)
    vectors = np.vstack([_cluster_embedding(c) for c in clusters])
    sim = cosine_similarity(vectors)

    proper_nouns = []
    for c in clusters:
        text = " ".join(
            f"{clean_title(a['title'])} {clean_summary(a.get('summary', ''))}" for a in c["articles"]
        )
        proper_nouns.append(extract_proper_nouns(text) - _GENERIC_ANCHOR_STOPWORDS)

    # complete-linkage와 같은 원리지만, "합칠 수 있는 쌍"인지부터 유사도+고유명사
    # 공유 두 조건으로 미리 걸러서 distance를 만듦(둘 다 만족 못 하면 1.0=합칠
    # 수 없음으로 고정). average-linkage라 이 안에서도 평균 기준으로 묶임.
    distance = np.ones((n, n))
    for i in range(n):
        for j in range(n):
            if i == j:
                distance[i, j] = 0
            elif sim[i, j] >= threshold and (proper_nouns[i] & proper_nouns[j]):
                distance[i, j] = 1 - sim[i, j]

    model = AgglomerativeClustering(
        n_clusters=None,
        metric="precomputed",
        linkage="average",
        distance_threshold=1 - threshold,
    ).fit(distance)

    groups: dict[int, list[int]] = defaultdict(list)
    for i, label in enumerate(model.labels_):
        groups[int(label)].append(i)

    global_df = build_global_df(all_articles)
    total = len(all_articles)

    def _build_cluster(articles_list: list[dict], fallback_title: str) -> dict:
        outlets: dict[str, int] = defaultdict(int)
        for a in articles_list:
            outlets[a["outlet"]] += 1
        keywords = extract_keywords(articles_list, global_df, total)
        return {
            "keyword": keywords[0] if keywords else fallback_title,
            "keywords": keywords,
            "category": classify_category(articles_list),
            "representative_title": fallback_title,
            "article_count": len(articles_list),
            "outlet_count": len(outlets),
            "outlets": dict(sorted(outlets.items(), key=lambda kv: -kv[1])),
            "articles": articles_list,
        }

    merged = []
    for idxs in groups.values():
        if len(idxs) == 1:
            merged.append(clusters[idxs[0]])
            continue
        member_clusters = [clusters[i] for i in idxs]
        combined_articles = [a for c in member_clusters for a in c["articles"]]
        keywords = extract_keywords(combined_articles, global_df, total)

        # 병합 직후 다시 한번 키워드로 검증함 — 합치는 과정에서 새로 뽑힌
        # 대표 키워드와 실제로는 무관한 기사가 섞여 보일 수 있어서
        # (2026-08-27 피드백: "홍수고립"+"조현" 병합 후 조현과 무관한
        # 기사가 섞임, "70대"+"연인" 병합 후 둘 다와 무관한 기사가 섞임).
        # split_articles_by_keywords가 clustering.py의 1차 검증과 같은
        # 로직으로 다시 한번 걸러줌(패턴 A: 소수 낙오, 패턴 B: 반반 쪼갬).
        subgroups, leftover = split_articles_by_keywords(combined_articles, keywords)
        for g in subgroups:
            g_ids = {id(a) for a in g}
            candidates = [c for c in member_clusters if any(id(a) in g_ids for a in c["articles"])]
            fallback_title = (
                max(candidates, key=lambda c: c["outlet_count"])["representative_title"]
                if candidates
                else g[0]["title"]
            )
            merged.append(_build_cluster(g, fallback_title))
        if leftover:
            merged.append(_build_cluster(leftover, leftover[0]["title"]))

    merged.sort(key=lambda c: (-c["outlet_count"], -c["article_count"]))
    return merged
