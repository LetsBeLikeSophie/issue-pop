# -*- coding: utf-8 -*-
"""
kiwipiepy 기반 텍스트 정리/명사 추출 공용 유틸.

clustering.py(유사도 계산)와 keyword_extraction.py(대표 키워드 추출)가
같은 전처리를 쓰도록 공용 모듈로 뺐어요. 원래는 이 로직이 clustering.py
안에 있었는데, keyword_extraction.py가 clustering.py를 import하고
clustering.py도 keyword_extraction.py를 import하는 순환 참조가 생겨서
분리했어요.

이 전처리를 keyword_extraction.py도 쓰게 된 계기: 예전엔 원본 텍스트를
그대로 토큰화해서 "[포토]" 같은 섹션 태그의 "포토"가 실제 키워드로
뽑히는 문제가 있었음. clustering.py가 유사도 계산용으로 이미 만들어둔
바이라인/태그 제거 전처리를 재사용하면 이 문제가 해결됨.
"""

from __future__ import annotations

import html
import re

from kiwipiepy import Kiwi

kiwi = Kiwi()
NOUN_TAGS = {"NNG", "NNP", "SL"}  # 일반명사, 고유명사, 외국어(영문 표기 등)

# kiwipiepy 사전에 없는 외래어 고유명사는 끝 음절이 흔한 조사(로/은/는 등)와
# 겹치면 잘못 잘림. 예: "마운자로"(비만치료제 상표명)가 사전에 없어서
# "마운자"(명사)+"로"(조사)로 잘못 분석됨 → 키워드가 "마운자"로 뽑힘.
# 실측하면서 발견하는 대로 여기 추가해서 add_user_word로 통째로 한
# 단어로 인식시킴. (근본적으로는 신조어/외래어 사전을 계속 못 따라잡는
# 문제라 완전히 막을 순 없고, 발견되는 대로 추가하는 식으로 대응함.)
_USER_WORDS = [
    "마운자로",
]
for _word in _USER_WORDS:
    kiwi.add_user_word(_word, "NNP", 0)

# 통신사/매체 바이라인 패턴, 예: "(서울=연합뉴스) 김준태 기자 = " 또는
# "(부산=연합뉴스) ". 실측 결과, 이 정형 문구가 문자 n-gram 유사도를
# 오염시켜서 완전히 무관한 기사들(폭염특보, K팝, 정치 등)이 하나의
# 거대 클러스터로 잘못 묶이는 문제가 있었음(459건 중 368건이 한 클러스터로
# 뭉치고 키워드가 "있다"로 뽑힘). 벡터화 전에 이 부분을 제거해서 실제
# 본문 유사도만 비교하도록 함.
_BYLINE_RE = re.compile(r"^\([^()]*=[^()]*\)\s*(?:\S+\s*기자\s*=\s*)?")

# 제목 앞에 붙는 섹션/포맷 태그, 예: "[포토]", "[속보]", "[단독]". 이것도
# 실측에서 문제였음 — 머니투데이의 "[포토]" 사진 기사 38건이 전부 다른
# 인물/사건인데 이 태그 하나 때문에 한 클러스터로 뭉쳤음. 제목 끝의
# "(종합)" 같은 갱신 표시도 같은 이유로 제거.
_BRACKET_TAG_RE = re.compile(r"^(?:\[[^\[\]]+\]\s*)+")
_UPDATE_SUFFIX_RE = re.compile(r"\((?:종합|속보|단독)\)\s*$")

# 2026-08-24: 한겨레 RSS의 summary 필드에 실제 요약 대신 썸네일 이미지용
# HTML <table> 태그가 그대로 들어있는 걸 발견함(예: '<table border="0px"
# cellpadding="0px" ...><img src=...>'). 이게 거의 모든 한겨레 기사에서
# 똑같이 반복되다 보니, 임베딩 유사도 계산에서 완전히 무관한 한겨레
# 기사들이 "문체가 비슷해서"가 아니라 이 HTML 조각이 겹쳐서 하나로
# 묶이는 착시가 있었음(키워드가 "cellpadding"으로 뽑히기도 함). 태그를
# 다 제거하고, 흔한 HTML 엔티티(&#039; 등)도 원래 문자로 풀어줌.
_HTML_TAG_RE = re.compile(r"<[^>]+>")


def clean_title(title: str) -> str:
    title = html.unescape(title)
    title = _BRACKET_TAG_RE.sub("", title)
    title = _UPDATE_SUFFIX_RE.sub("", title)
    return title.strip()


def clean_summary(summary: str) -> str:
    summary = _HTML_TAG_RE.sub(" ", summary)
    summary = html.unescape(summary)
    summary = _BYLINE_RE.sub("", summary)
    return re.sub(r"\s+", " ", summary).strip()


def extract_nouns(text: str) -> list[str]:
    """형태소 분석해서 명사(+외국어 표기) 토큰 리스트를 반환."""
    return [t.form for t in kiwi.tokenize(text) if t.tag in NOUN_TAGS]


def extract_proper_nouns(text: str) -> set[str]:
    """고유명사(인물/기관/지명 등, NNP)만 뽑음.

    keyword_extraction.py가 보조 키워드를 고를 때 "직선"+"당원"처럼
    추상명사 둘만 있으면 무슨 얘긴지 안 잡히는데, 그중 하나가 "장동혁"
    같은 고유명사면 훨씬 구체적으로 읽힌다는 걸 실측(피드백)으로 확인해서
    추가함.
    """
    return {t.form for t in kiwi.tokenize(text) if t.tag == "NNP" and len(t.form) >= 2}


_NUMBER_TAG = "SN"  # 숫자
_UNIT_TAGS = {"NNB", "SW"}  # 의존명사(예: "도", "명", "건") / 기호(예: "%")


def extract_noun_ngrams(text: str) -> list[str]:
    """명사 유니그램 + 바로 붙어있는 명사쌍(바이그램) + 숫자·단위 조합.

    kiwipiepy는 사전 기반이라 같은 복합명사도 문장에 따라 한 토큰으로
    붙거나("국민연금") 쪼개져("국민"+"연금") 나올 수 있음. keyword_extraction이
    유니그램만 후보로 쓰면 쪼개진 경우엔 "연금"처럼 원래보다 더 뭉뚱그려진
    단어가 대표 키워드로 뽑힐 수 있어서, 바로 붙어있는 명사쌍을 이어붙인
    것도 후보로 같이 넣어서 "국민연금" 같은 복합어가 뽑힐 기회를 줌.

    2026-08-24: "38도", "3%"처럼 숫자+단위 조합도 후보에 추가함. 원래는
    명사만 뽑아서 "낮최고"처럼 단위/숫자가 빠진 애매한 키워드만 나왔는데,
    "그 클러스터가 몇 도/몇 %/몇 명짜리 얘기인지"가 부가 키워드로 유용한
    경우가 많아서 추가함(예: "낮최고"+"38도").
    """
    tokens = kiwi.tokenize(text)
    noun_idx = [i for i, t in enumerate(tokens) if t.tag in NOUN_TAGS]
    result = [tokens[i].form for i in noun_idx]
    for a, b in zip(noun_idx, noun_idx[1:]):
        if b == a + 1:
            result.append(tokens[a].form + tokens[b].form)

    for i, t in enumerate(tokens[:-1]):
        if t.tag == _NUMBER_TAG and tokens[i + 1].tag in _UNIT_TAGS:
            result.append(t.form + tokens[i + 1].form)

    return result
