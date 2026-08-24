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

from embedding_utils import embed
from text_utils import clean_summary, clean_title

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
