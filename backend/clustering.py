# -*- coding: utf-8 -*-
"""
이슈 클러스터링 모듈 (v0 — 프로토타입).

목표: "여러 매체가 같은 이슈를 다르게 제목 붙여 보도한 기사들"을
      하나의 이슈로 묶는 것.

접근 방식 (2026-08-24: 문자 n-gram TF-IDF → 한국어 문장 임베딩으로 교체):
  1. `jhgan/ko-sroberta-multitask`(한국어 STS 전용 SBERT)로 기사 제목+
     요약을 의미 벡터로 변환해요. 이전엔 kiwipiepy 명사 추출 + 문자
     n-gram TF-IDF를 썼는데, 이 방식은 "표면적으로 겹치는 글자"가 있어야
     비슷하다고 판단해서 매체마다 표현이 완전히 다른 같은 이슈를 놓치는
     경우가 있었어요(예: "이소희·백하나, 배드민턴 세계선수권 여자복식
     31년 만에 우승" vs "백하나-이소희, 배드민턴 女복식 세계선수권 31년
     만의 金" — 겹치는 글자가 거의 없음). 문장 임베딩은 뜻이 같으면
     표현이 달라도 벡터가 가깝게 나와서 이런 케이스를 잘 잡아요.
     (범용 다국어 모델도 실측해봤는데, 매체별 "문체"를 지나치게 비슷하다고
     판단해서 완전히 다른 주제를 섞는 문제가 있었음 — 한국어 STS 전용
     모델로 바꾸니 훨씬 나아짐. 자세한 비교는 README 참고.)
  2. 코사인 유사도 기반 complete-linkage 계층적 클러스터링(사이킷런
     AgglomerativeClustering)으로 묶어요. 클러스터 내 "모든" 기사쌍의
     유사도가 threshold 이상이어야 합쳐짐 — 기사쌍 하나만 넘어도 합치는
     single-linkage(Union-Find)보다 훨씬 엄격함(예전에 겪은 percolation
     문제 때문에 처음부터 이 방식으로 감).
  3. 각 클러스터를 대표 제목(가장 이른 시각의 기사, 또는 클러스터 내
     다른 기사들과 평균 유사도가 가장 높은 기사)과 함께 반환.

이 방식의 한계 (알고 가야 할 것):
  - 인코딩이 문자 n-gram보다 훨씬 느림(로컬 CPU 기준 461건에 20~50초).
    기사 수가 많아지면 배치 크기 조절이나 GPU, 또는 임베딩을 미리
    계산해서 캐싱하는 게 필요할 수 있음.
  - 여전히 임계값 하나로 전역 판단하기 때문에, 이슈마다 표현의
    다양성이 다르면 과소/과대 클러스터링이 생길 수 있음.
  - O(n^2) 유사도 행렬이라 기사 수가 수만 건으로 늘면 느려짐
    (그때는 LSH나 벡터 DB로 근사 검색을 붙이면 됨).
  - 랭킹은 article_count가 아니라 outlet_count를 1순위로 정렬해요 —
    한 매체가 같은 이벤트를 실시간으로 여러 건 도배하면(예: 야구 경기
    사진 캡션 38건) article_count만으로는 "많이 보도된 이슈"처럼 보이지만
    실제로는 한 매체 단독 스트림일 뿐이라 앱의 취지("여러 매체가 보도")와
    안 맞아서 이렇게 바꿨어요. 임베딩으로 바꾼 뒤에도 한 매체가 비슷한
    문체로 쓴 여러 기사(예: 스포츠 사진 캡션)가 하나로 묶이는 경향은
    남아있는데, outlet_count 우선 정렬 덕분에 이런 것들은 랭킹 하위로
    자연스럽게 밀려남.
"""

from __future__ import annotations

from collections import defaultdict

import numpy as np
from sklearn.cluster import AgglomerativeClustering
from sklearn.metrics.pairwise import cosine_similarity

from category import classify_category
from embedding_utils import embed
from keyword_extraction import build_global_df, extract_keywords
from text_utils import clean_summary, clean_title


def _vectorize(texts: list[str]):
    """제목+요약 텍스트를 한국어 문장 임베딩으로 변환."""
    return embed(texts)


def cluster_articles(articles: list[dict], threshold: float = 0.45) -> list[dict]:
    """기사 리스트를 이슈 클러스터로 묶어요.

    Args:
        articles: fetcher.fetch_all()이 반환하는 표준 스키마의 기사 리스트.
        threshold: 코사인 유사도 임계값 (0~1). 높일수록 더 엄격하게(적게) 묶임.

    Returns:
        클러스터 리스트. 각 클러스터는:
        {
            "keyword": str,               # 랭킹 화면에 쓸 짧은 대표 키워드 (예: "국민연금")
            "keywords": [str, ...],       # 대표 키워드 + 보조 키워드(최대 2개, 예: ["카카오", "증권가"])
            "category": str,              # 고정 섹션 분류 (정치/경제/사회/국제/스포츠/연예/IT/과학/기타)
            "representative_title": str,  # 참고용 예시 헤드라인(기사 한 건의 제목 전체)
            "article_count": int,
            "outlet_count": int,
            "outlets": {outlet: count, ...},   # 매체별 보도 건수 (매체별 분포 화면용)
            "articles": [article, ...],
        }
        outlet_count 내림차순, 그 다음 article_count 내림차순으로 정렬
        (오늘 많이 언급된 키워드 랭킹용 — "여러 매체가 보도"를 우선시함).

        keyword와 representative_title은 서로 다른 로직으로 뽑혀요.
        representative_title은 "실제로 존재하는 기사 제목 중 하나"라서
        항상 자연스러운 문장이지만 길고, keyword는 keyword_extraction.py의
        규칙 기반 추출로 뽑은 짧은 단어라서 화면 랭킹 리스트에 쓰기 좋아요.
    """
    if not articles:
        return []

    texts = [
        f"{clean_title(a['title'])} {clean_summary(a.get('summary', ''))}" for a in articles
    ]
    vectors = _vectorize(texts)
    sim_matrix = cosine_similarity(vectors)
    global_df = build_global_df(articles)

    n = len(articles)
    if n == 1:
        labels = np.array([0])
    else:
        # complete-linkage: 두 클러스터는 "모든" 기사쌍의 거리가 threshold
        # 이내여야 합칠 수 있음. (참고: 예전엔 Union-Find로 기사쌍 하나만
        # threshold를 넘어도 합치는 single-linkage 방식을 썼는데, 이게
        # 459건 실데이터에서 심각한 문제였음 — 평균 연결 차수가 19 정도라
        # 그래프 percolation 이론상 threshold를 어떻게 잡아도 기사 대부분이
        # 사슬처럼 하나로 뭉치는 게 수학적으로 거의 필연이었음. complete
        # linkage는 약한 연결 하나로 전체가 오염되는 걸 막아줌.)
        distance = np.clip(1 - sim_matrix, 0, None)
        np.fill_diagonal(distance, 0)
        clustering = AgglomerativeClustering(
            n_clusters=None,
            metric="precomputed",
            linkage="complete",
            distance_threshold=1 - threshold,
        ).fit(distance)
        labels = clustering.labels_

    groups: dict[int, list[int]] = defaultdict(list)
    for i, label in enumerate(labels):
        groups[int(label)].append(i)

    clusters = []
    for indices in groups.values():
        cluster_articles_list = [articles[i] for i in indices]

        # 대표 제목: 클러스터 내 다른 기사들과 평균 유사도가 가장 높은 기사
        # (가장 "전형적인" 표현을 대표로 뽑기 위함)
        if len(indices) == 1:
            rep_idx = indices[0]
        else:
            sub = sim_matrix[np.ix_(indices, indices)]
            avg_sim = sub.mean(axis=1)
            rep_idx = indices[int(np.argmax(avg_sim))]
        representative_title = articles[rep_idx]["title"]

        outlets: dict[str, int] = defaultdict(int)
        for a in cluster_articles_list:
            outlets[a["outlet"]] += 1

        keywords = extract_keywords(cluster_articles_list, global_df, len(articles))
        category = classify_category(cluster_articles_list)

        clusters.append(
            {
                "keyword": keywords[0] if keywords else cluster_articles_list[0]["title"],
                "keywords": keywords,
                "category": category,
                "representative_title": representative_title,
                "article_count": len(cluster_articles_list),
                "outlet_count": len(outlets),
                "outlets": dict(sorted(outlets.items(), key=lambda kv: -kv[1])),
                "articles": cluster_articles_list,
            }
        )

    clusters.sort(key=lambda c: (-c["outlet_count"], -c["article_count"]))
    return clusters
