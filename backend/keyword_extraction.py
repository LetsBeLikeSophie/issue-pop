# -*- coding: utf-8 -*-
"""
클러스터 대표 키워드 추출 (v1 — 형태소 분석 기반으로 교체, 2026-08-23).

clustering.py가 기사를 이슈 단위로 묶어주긴 하지만, 그 결과의
`representative_title`은 "그 클러스터 안에서 가장 전형적인 기사 한 건의
제목 전체"였어요 (예: "보험료율 단계적 인상안, 세대 간 형평성 논쟁").
근데 와이어프레임(Main.dc.html의 "오늘 많이 언급된 키워드")이 원한 건
그게 아니라 "국민연금"처럼 짧은 키워드 한 단어였고, 실제로 써보니
그 차이 때문에 헷갈렸어요. 그래서 이 모듈을 따로 뺐어요.

접근 방식:
  1. clustering.py와 같은 kiwipiepy로 명사(+외국어 표기)만 추출. 예전엔
     형태소 분석기 없이 정규식으로 "한글 2음절 이상 + 조사 후보 목록으로
     뒤에서 자르기"를 했었는데, "발효"/"가결"처럼 동사에서 온 명사형이
     섞이거나 "국가"처럼 조사가 아닌데 조사처럼 끝나는 단어가 잘못
     잘리는 문제가 있었음. kiwipiepy가 이제 clustering.py에 들어와 있으니
     같은 걸 재사용.
  2. clustering.py의 _clean_title/_clean_summary로 바이라인/섹션태그를
     먼저 제거한 뒤에 토큰화함. 이게 없어서 "[포토]" 같은 태그의 "포토"가
     실제 키워드로 뽑히는 문제가 있었음 — clustering.py가 유사도 계산용
     으로 이미 만들어둔 전처리를 재사용하면 됨.
  3. 클러스터 안에서 이 단어가 몇 개의 "다른" 기사에 등장하는지 세고
     (article_count 기준, 한 기사 안에서 반복돼도 1로만 셈), 전체 코퍼스
     전역에서 이 단어가 얼마나 흔한지(idf)를 곱해서 "이 클러스터에서만
     유독 자주 나오는 단어"를 우선시함(class-based TF-IDF, BERTopic 등과
     같은 아이디어). 제목에 나온 단어는 요약문에만 나온 단어보다 가중치를
     2배 줌.

     예전 버전은 이 tf*idf 점수를 "동점일 때만 보는 2순위"로 잘못
     써놔서, "총리"처럼 그 클러스터에서 제일 자주 나오지만 코퍼스
     전체에서도 흔한 단어가 idf 페널티를 못 받고 그대로 키워드가 되는
     버그가 있었음. tf*idf를 1순위 정렬 기준으로 바꿈.

한계:
  - "포토"처럼 대괄호 태그 밖에서 평문으로 등장하는 섹션 라벨(예:
    "화보", "카드뉴스")은 여전히 STOPWORDS로 수동 방어해야 함 — tf*idf만
    으로는 못 잡음. 그 클러스터 안에서 유일하게 반복되는 단어라면
    코퍼스 전체 기준 idf가 오히려 높게(=키워드 우선순위가 높게) 나올
    수 있기 때문(그 태그를 쓰는 곳이 코퍼스에 적을수록 "희소해서 특징적인
    단어"로 오인됨).
  - 기사가 1건뿐인 이슈(단독 보도)는 반복 신호가 없어서 tie-break가
    알파벳(가나다) 순서로 떨어짐 → 정확히 하려면 개체명 인식(NER) 등이
    필요하고, 지금은 "기사 여러 건이 모인 진짜 트렌드 이슈"에서 잘 되면
    충분하다고 보고 넘어감.
"""

from __future__ import annotations

import math
from collections import Counter

from text_utils import clean_summary, clean_title, extract_noun_ngrams, extract_proper_nouns

STOPWORDS = {
    "오늘", "이번", "지난", "한편", "관련", "위해", "것", "기자",
    "최종안", "발표", "계획", "전망", "진행", "확인", "가운데", "다음", "이유",
    "가능성", "전체", "포토", "화보", "카드뉴스", "속보", "단독", "종합",
    "개막", "개최", "실시", "마련", "도입",
    # 단위 약자(SL 태그라 명사 후보에 들어오지만, 앞에 숫자 없이 혼자
    # 나오면 "오세훈 · cm"처럼 의미 없는 파편이 됨 — 2026-08-24 발견.
    "cm", "kg", "mm", "km", "ml", "mg", "kwh",
}


def _normalize_tokens(text: str) -> set[str]:
    tokens = extract_noun_ngrams(text)
    return {t for t in tokens if len(t) >= 2 and t not in STOPWORDS}


def _article_tokens(article: dict) -> tuple[set[str], set[str]]:
    """(제목 토큰, 제목+요약 토큰) 튜플을 반환."""
    title = clean_title(article["title"])
    summary = clean_summary(article.get("summary", ""))
    title_toks = _normalize_tokens(title)
    all_toks = _normalize_tokens(f"{title} {summary}")
    return title_toks, all_toks


def build_global_df(all_articles: list[dict]) -> Counter:
    """전체 기사 코퍼스에서 각 단어가 몇 건의 기사에 등장하는지(document frequency).

    클러스터별 키워드를 뽑을 때 "이 코퍼스 전체에서 흔한 단어"를 걸러내는
    기준으로 쓰여요 (idf 계산용). 파이프라인 전체를 한 번 돌 때 한 번만
    계산해서 각 클러스터 키워드 추출에 재사용하면 돼요.
    """
    df: Counter = Counter()
    for a in all_articles:
        _, toks = _article_tokens(a)
        for t in toks:
            df[t] += 1
    return df


def _score_candidates(
    cluster_articles: list[dict], global_df: Counter, total_articles: int
) -> list[tuple[str, int, float]]:
    """후보 단어들을 (단어, tf, tf*idf점수)로 점수 매겨서 내림차순 정렬해 반환."""
    weighted: Counter = Counter()
    for a in cluster_articles:
        title_toks, all_toks = _article_tokens(a)
        for t in all_toks:
            weighted[t] += 2 if t in title_toks else 1

    if not weighted:
        return []

    scored = []
    for t, w in weighted.items():
        idf = math.log(total_articles / (1 + global_df.get(t, 0)))
        # log(1+tf)로 완만하게 눌러서 raw 빈도가 idf를 압도하지 못하게 함.
        # 예: "연금"(모든 기사에 등장, 흔함)이 raw 빈도로는 "국민연금"(그
        # 클러스터 절반에만 등장, 훨씬 특징적)을 항상 이겨버리는 문제가
        # 있었음 — tf를 그대로 곱하면 등장 횟수 차이가 idf 차이를 압도함.
        score = math.log1p(w) * idf
        scored.append((t, w, score))

    # 1순위: log(1+tf)*idf(클러스터 내 등장 빈도 x 전역 희소성), 2순위: 완전
    # 동점일 때만 더 긴(더 구체적인) 후보, 3순위: 가나다순(결정론적 tie-break).
    #
    # 예전엔 1순위가 raw 등장 빈도(w)였는데, 그러면 idf는 완전한 동점일 때만
    # 보는 tie-break라 사실상 무력했음 — "총리"처럼 그 클러스터에서 제일 자주
    # 나오지만 코퍼스 전체에서도 흔한 단어가 idf 페널티를 못 받고 그대로
    # 뽑히는 버그가 있었음.
    #
    # "점수가 거의 비슷하면 긴 쪽을 우선"하는 것도 시도해봤는데, 그러면
    # "국민연금"이 "연금"을 이기는 대신 "국내스타트업"처럼 단어 여러 개를
    # 억지로 이어붙인 후보가 다른 클러스터에서 이겨버리는 역효과가 더
    # 컸음(단순 글자수 비교는 "몇 형태소가 진짜로 붙어있는 자연스러운
    # 복합어인지"를 구분 못함). 그래서 "완전 동점일 때만" 긴 쪽을 우선하는
    # 걸로 좁혔음 — 예: "폭염특보"와 "특보"가 그 클러스터에서 항상 같이
    # 붙어다녀서 점수가 정확히 같은 경우.
    #
    # 기사 1건짜리 클러스터는 반복 신호가 아예 없어서 거의 모든 후보가
    # 우연히 동점이 되는데(등장 횟수가 다 1이라서), 그 상태에서 "긴 쪽 우선"을
    # 적용하면 "주말한반도"처럼 문장에서 아무 단어나 이어붙인 게 이겨버려서
    # 오히려 나빠짐. 그래서 기사 2건 이상(=진짜 여러 매체가 동의한 신호가
    # 있는 경우)에서만 이 tie-break를 씀.
    if len(cluster_articles) > 1:
        scored.sort(key=lambda x: (-x[2], -len(x[0]), x[0]))
    else:
        scored.sort(key=lambda x: (-x[2], x[0]))
    return scored


def extract_keyword(cluster_articles: list[dict], global_df: Counter, total_articles: int) -> str:
    """클러스터 하나에 대한 대표 키워드(짧은 단어) 하나를 뽑아요.

    Returns:
        키워드 문자열. 토큰을 하나도 못 뽑으면(제목이 특수문자뿐 등)
        안전하게 첫 기사 제목 전체를 그대로 반환.
    """
    scored = _score_candidates(cluster_articles, global_df, total_articles)
    if not scored:
        return cluster_articles[0]["title"]
    return scored[0][0]


_PROPER_NOUN_SEARCH_WINDOW = 8  # 상위 몇 개 후보 안에서 고유명사를 찾아볼지


def extract_keywords(
    cluster_articles: list[dict], global_df: Counter, total_articles: int, k: int = 2
) -> list[str]:
    """클러스터 하나에 대한 키워드를 최대 k개 뽑아요(1등 + 보조 키워드들).

    "카카오"만 있으면 무슨 얘긴지 모르지만 "카카오 · 증권가"처럼 2번째
    키워드가 붙으면 훨씬 맥락이 잡힌다는 피드백으로 추가함. 1등 키워드와
    겹치는(서로 부분 문자열 관계인) 후보는 정보량이 없어서 건너뜀 — 예:
    "폭염특보"가 1등이면 "특보"는 새 정보가 없으니 스킵하고 그 다음
    후보(예: "38도")로 넘어감.

    2026-08-24: 실제로 써보니 "직선 · 당원"처럼 추상명사 둘만 나오면
    오히려 더 헷갈리고("당원직선제" 얘기인 줄 바로 안 잡힘), "구속영장 ·
    경찰관구속"처럼 뜻이 겹치는 경우도 있다는 피드백을 받음. 공통점:
    좋았던 조합("법관제청 · 조희대", "김정은 · 트럼프")은 인물/기관 같은
    고유명사가 하나 섞여 있었음 — 고유명사는 그 자체로 "누구/어디" 얘긴지
    바로 알려줘서 정보량이 확실함. 그래서 뽑힌 키워드 중 고유명사가
    하나도 없으면, 상위 후보 안에서 고유명사를 찾아 가장 약한(마지막)
    키워드를 그걸로 바꿔치기함.

    Returns:
        1~k개의 키워드 리스트. 후보가 아예 없으면 빈 리스트.
    """
    scored = _score_candidates(cluster_articles, global_df, total_articles)
    if not scored:
        return []

    keywords: list[str] = []
    for t, _w, _score in scored:
        if any(t in kw or kw in t for kw in keywords):
            continue
        keywords.append(t)
        if len(keywords) >= k:
            break

    if k >= 2 and len(keywords) >= 2:
        proper_nouns: set[str] = set()
        for a in cluster_articles:
            proper_nouns |= extract_proper_nouns(clean_title(a["title"]))
            proper_nouns |= extract_proper_nouns(clean_summary(a.get("summary", "")))

        if not any(kw in proper_nouns for kw in keywords):
            for t, _w, _score in scored[:_PROPER_NOUN_SEARCH_WINDOW]:
                if t in proper_nouns and not any(t in kw or kw in t for kw in keywords[:-1]):
                    keywords[-1] = t
                    break

    return keywords
