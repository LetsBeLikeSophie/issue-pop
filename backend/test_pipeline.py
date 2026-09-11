# -*- coding: utf-8 -*-
"""
아주 가벼운 회귀 테스트. pytest 없이 그냥 `python3 test_pipeline.py`로 돌려요.

sample_data/sample_articles.json은 사람이 직접 "이 18건은 사실 7개 이슈다"라고
정답을 알고 만든 픽스처예요. 클러스터링 알고리즘/threshold가 바뀔 때마다
이 정답에 딱 맞진 않을 수 있는데(작은 픽스처의 최적 threshold가 실제
대량 데이터의 최적값과 항상 일치하진 않음 — 여러 번 겪은 패턴), 그래도
"기사 수가 보존되는지", "무관한 주제끼리 안 섞이는지" 같은 핵심 불변량은
항상 확인해서 회귀를 잡아내요.
"""

from pipeline import load_sample_articles
from clustering import cluster_articles
from meta_cluster import group_into_super_clusters


def _find_cluster_containing(clusters, substring):
    """제목에 substring이 들어간 기사를 포함하는 클러스터를 찾음(테스트용 헬퍼).

    2026-08-24: 임베딩으로 바꾸면서 "국민연금" 클러스터가 항상 clusters[0]
    이라는 가정이 깨짐(같은 article_count/outlet_count로 동점인 클러스터가
    여럿 생길 수 있어서 정렬 순서가 안정적이지 않음). 위치 대신 내용으로
    찾도록 헬퍼를 만듦.
    """
    for c in clusters:
        if any(substring in a["title"] for a in c["articles"]):
            return c
    raise AssertionError(f"'{substring}'이 들어간 클러스터를 못 찾음")


def test_sample_data_clusters_into_expected_issues():
    """정답을 아는 18건 픽스처 기준 클러스터링 결과 확인.

    2026-08-24: 문자 n-gram → 한국어 문장 임베딩(ko-sroberta-multitask)으로
    바꾸면서 threshold를 0.40(픽스처와 정확히 일치)이 아니라 0.45로
    잡았음. 이유: 라이브 460건 실측에서 0.40은 "박은빈 드라마 종영 +
    살인사건 + 병원 응급실 + 정치"가 뒤섞인 클러스터가 나왔는데, 0.45로
    올리니 없어짐(자세한 진단은 backend/README.md 참고). 그 결과 픽스처의
    "국민연금" 이슈(원래 6건 통짜)가 "보험료율 인상"(4건)과 "청년층
    불신·공청회"(2건)로 다시 갈라짐 — 정확히 예전 문자 n-gram 버전에서도
    한 번 겪었던 것과 같은 종류의 트레이드오프. 둘 다 여전히 말이 되는
    분리라(국민연금 정책 자체 vs 청년 세대 반응/공청회), 정답을 이걸로
    갱신함.

    2026-09-11: "김승원 신약 로비" 단독 기사(#18)를 추가함 — 키워드 추출의
    고유명사 스코어링 버그(아래 test_keywords_are_short_and_on_topic 참고)를
    회귀로 고정하려는 목적. 다른 이슈와 안 묶이는 단독 기사라 클러스터
    크기 목록에 1이 하나 더 늘어남.
    """
    articles = load_sample_articles()
    clusters = cluster_articles(articles)

    sizes = sorted((c["article_count"] for c in clusters), reverse=True)
    assert sizes == [4, 4, 3, 2, 2, 1, 1, 1], f"예상과 다른 클러스터 크기: {sizes}"
    assert sum(sizes) == len(articles)  # 기사 수 보존(누락/중복 없음)

    # "보험료율 인상"(4건)과 "청년층 불신/공청회"(2건)를 합치면 원래
    # 픽스처가 의도한 "국민연금" 이슈 6건, 6개 매체를 커버해야 함.
    core = _find_cluster_containing(clusters, "보험료율")
    fringe = _find_cluster_containing(clusters, "연금 불신")
    combined_outlets = set(core["outlets"]) | set(fringe["outlets"])
    assert core["article_count"] + fringe["article_count"] == 6
    assert len(combined_outlets) == 6, f"매체 커버리지 부족: {combined_outlets}"

    print(f"OK: {len(clusters)}개 클러스터, 사이즈", sizes)


def test_keywords_are_short_and_on_topic():
    """키워드가 헤드라인 문장 전체가 아니라 짧은 대표 단어로 뽑히는지 확인."""
    articles = load_sample_articles()
    clusters = cluster_articles(articles)

    expected = {
        # 2026-08-25: "보험료"→"보험료율"로 바뀜 — text_utils.py의
        # extract_noun_ngrams가 명사+접미사(XSN, "율")를 이제 하나로
        # 합쳐서(예전엔 "율"이 빠져서 "보험료"만 남았음) 더 정확한 키워드가
        # 나옴. 실측으로 확인한 개선이라 기대값을 새 결과로 맞춤.
        "보험료율": "보험료율",
        "전기요금": "요금인상",
        "폭염특보": "폭염특보",
    }
    for substring, expected_kw in expected.items():
        c = _find_cluster_containing(clusters, substring)
        assert c["keyword"] == expected_kw, f"기대: {expected_kw}, 실제: {c['keyword']}"

    for c in clusters:
        assert len(c["keyword"]) <= 10, f"키워드가 너무 김(헤드라인이 그대로 나온 듯): {c['keyword']}"

    # 2026-09-11: "김승원" 고유명사 스코어링 버그 회귀 테스트.
    # extract_noun_ngrams가 인접 명사를 이어붙여 "김승원신약" 같은 글자
    # 조합을 만드는데, 이 조합이 코퍼스 전체에서 유일해서(global_df=0)
    # idf가 비정상적으로 커져 흔한 고유명사 "김승원"(global_df 높음)보다
    # 점수가 더 높게 나와 키워드 자리를 차지해버리는 버그가 있었음
    # (실제 라이브 데이터로 확인, keyword_extraction.py 참고). "김승원"이
    # 안 잘리고 그대로 키워드 후보에 있어야 함 — "김승원신약" 같은 글자가
    # 붙은 형태로 나오면 회귀.
    kim = _find_cluster_containing(clusters, "김승원")
    assert "김승원" in ([kim["keyword"]] + kim.get("keywords", [])), (
        f"김승원 고유명사가 키워드에서 잘림: keyword={kim['keyword']!r} keywords={kim.get('keywords')!r}"
    )
    for kw in [kim["keyword"]] + kim.get("keywords", []):
        assert "김승원신약" not in kw, f"고유명사 스코어링 버그 재발: {kw!r}"

    print("OK: 키워드 추출 정상 (보험료/요금인상/폭염특보/김승원 등)")


def test_no_cross_topic_contamination():
    """국민연금(보험료율) 이슈 클러스터에 전기요금/폭염 관련 기사가 섞여 들어가면 안 됨."""
    articles = load_sample_articles()
    clusters = cluster_articles(articles)

    core = _find_cluster_containing(clusters, "보험료율")
    for a in core["articles"]:
        assert "전기" not in a["title"], f"오염된 기사 발견: {a['title']}"
        assert "폭염" not in a["title"], f"오염된 기사 발견: {a['title']}"

    print("OK: 클러스터 간 오염 없음")


def test_super_clusters_preserve_all_issues():
    """메타클러스터링(group_into_super_clusters)이 이슈를 잃어버리거나 중복시키지 않는지 확인."""
    articles = load_sample_articles()
    clusters = cluster_articles(articles)
    super_clusters = group_into_super_clusters(clusters)

    total_issues = sum(len(g["clusters"]) for g in super_clusters)
    assert total_issues == len(clusters), f"이슈 개수 불일치: {total_issues} != {len(clusters)}"

    total_articles = sum(g["article_count"] for g in super_clusters)
    assert total_articles == len(articles), f"기사 수 불일치: {total_articles} != {len(articles)}"

    print(f"OK: 슈퍼그룹 {len(super_clusters)}개, 이슈/기사 수 보존 확인")


if __name__ == "__main__":
    test_sample_data_clusters_into_expected_issues()
    test_no_cross_topic_contamination()
    test_keywords_are_short_and_on_topic()
    test_super_clusters_preserve_all_issues()
    print("\n모든 테스트 통과")
