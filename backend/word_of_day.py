# -*- coding: utf-8 -*-
"""
2026-09-11: "오늘의 단어" — 오늘 수집된 기사 제목들에서 어려운(추정) 명사
하나를 뽑아 예문과 함께 보여주는 기능. 뜻풀이는 국립국어원 표준국어대사전
Open API 연동 전까지는 비워둠(api.py의 word-of-day 엔드포인트가 null로 내려줌).

**알려진 한계**: 실제 난이도/사용빈도 사전이 없어서, "일반명사(NNG) +
3음절 이상 + 스톱워드 아님" 중 가장 긴 것을 고르는 근사치임 — 한자어
복합명사일수록 길고 formal한 경향이 있다는 전제인데, 완벽하지 않음
(고유명사 축약형이나 신조어가 우연히 걸릴 수 있음). 사전 API를 붙이면
"사전에 표제어로 있는지" 자체를 필터로 쓸 수 있어서 그때 교체할 것.
"""

from __future__ import annotations

import os

import dictionary
import llm
import text_utils

# 뉴스에 매일 나오지만 "어렵다"고 하기엔 너무 일상적인 명사 — 실측하며
# 계속 추가할 스톱리스트(완벽한 빈도 사전이 없어서 v0 수준의 필터링임).
_COMMON_STOPWORDS = {
    "오늘", "발표", "관련", "정부", "국민", "사회", "경제", "정치", "사건",
    "기자", "보도", "뉴스", "사진", "영상", "취재", "확인", "논란", "문제",
    "상황", "이후", "이번", "지난", "올해", "내년", "지금", "당시", "현재",
    "대통령", "위원회", "기업", "시장", "국내", "해외", "전국", "지역",
    "우리나라", "관계자", "담당자", "책임자", "이야기", "생각", "사람들",
    # 2026-09-11: "한국어 학습용 어휘 목록"(2003, 외국인 학습자 대상)이
    # 원어민이면 당연히 아는 현대 기술/산업 용어나 영어 외래어까지는 못
    # 커버해서(반도체/데이터/프로젝트 등이 그 목록에 없어서 "어려운 말"로
    # 잘못 뽑힘) 발견하는 대로 여기 추가함 — _USER_WORDS(text_utils.py)와
    # 같은 식의 대응.
    "반도체", "글로벌", "프로젝트", "데이터", "인프라", "코스닥",
}

# "실종자"/"사망자"/"후보자"처럼 "OO+자"(그 일을 하는/당하는 사람) 형태는
# 뒷글자만 봐도 뜻이 바로 파악되는 구성적 단어라, 원본 어근이 낯설어도
# 전체 단어는 안 어렵게 읽힘 — 실측(후보 상위권이 죄다 이 패턴)으로
# 발견해서 통째로 걸러냄. "인자"/"숫자"처럼 사람을 뜻하지 않는 예외도
# 같이 걸러지긴 하지만, 그런 것들도 흔한 말이라 실용상 손해는 적음.
_AGENT_SUFFIX = "자"

# 2026-09-11: "오늘 여러 기사에 반복되는 말"만 보면 실측 결과 "반도체"/
# "위원장"/"아파트"처럼 그냥 흔한 시사 명사만 뽑힘(회자=화제성이지 난이도가
# 아님) — 국립국어원 "한국어 학습용 어휘 목록"(2003, 5,965단어, 등급
# A/B/C 전부 포함)에 있는 말은 "원어민이면 당연히 아는 말"로 보고
# 제외함으로써 난이도 신호를 따로 둠. 동음이의어 구분용 뒤 숫자(가격03의
# "03")는 제거하고 로드함(known_words.txt 생성 스크립트와 동일 규칙).
_KNOWN_WORDS_PATH = os.path.join(os.path.dirname(__file__), "known_words.txt")
with open(_KNOWN_WORDS_PATH, encoding="utf-8") as _f:
    _KNOWN_WORDS = {line.strip() for line in _f if line.strip()}

# 최소 이만큼 서로 다른 이슈에 등장해야 "오늘 회자되는 말"로 침(1건짜리
# 우연한 표현은 제외).
_MIN_ISSUE_COUNT = 2

# 사전 조회 + LLM 판단에 넘길 후보 수 상한 — 반복 횟수 내림차순으로 이만큼만
# 시도함(전부 다 조회하면 사전 API 호출이 너무 많아짐). 반복 횟수 자체는
# 난이도가 아니라 "회자 여부"만 걸러주는 신호라 이 안에서 순서는 의미 없음.
_MAX_CANDIDATES = 15


def pick_word(cache: dict) -> tuple[str, str, str | None] | None:
    """오늘 캐시(_cache.values(), 각 c["articles"]에 기사 목록)에서 골라
    (단어, 예문, 뜻풀이)로 반환. 후보가 하나도 없으면 None.

    2026-09-11: 규칙 기반 필터(회자 여부 + 학습용 어휘 목록 제외 + 사전
    등재 여부)로 후보군을 추리고, "그중 어느 게 가장 오늘의 단어답게
    적당히 어려운지"는 LLM(Haiku, llm.pick_best_word)에게 맡김 — 반복
    횟수만으로는 "발전소"처럼 그냥 흔한 말이 1등으로 뽑히는 문제가
    있었음(회자=화제성이지 난이도가 아니라서). LLM이 실패하거나 키가
    없으면 후보 중 첫 번째(반복 최다)로 폴백함."""
    issue_counts: dict[str, set[str]] = {}
    examples: dict[str, str] = {}
    for issue_id, c in cache.items():
        for a in c.get("articles", []):
            title = a.get("title", "")
            if not title:
                continue
            for tok in text_utils.kiwi.tokenize(title):
                if tok.tag != "NNG":
                    continue
                word = tok.form
                if len(word) < 3:
                    continue
                if word in _COMMON_STOPWORDS:
                    continue
                if word in _KNOWN_WORDS:
                    continue
                if word.endswith(_AGENT_SUFFIX):
                    continue
                issue_counts.setdefault(word, set()).add(issue_id)
                examples.setdefault(word, title)

    recurring = [w for w, ids in issue_counts.items() if len(ids) >= _MIN_ISSUE_COUNT]
    if not recurring:
        return None

    ordered = sorted(recurring, key=lambda w: len(issue_counts[w]), reverse=True)
    validated = []
    for word in ordered[:_MAX_CANDIDATES]:
        definition = dictionary.lookup(word)
        if definition:
            validated.append({"word": word, "example": examples[word], "definition": definition})

    if not validated:
        return None

    picked = llm.pick_best_word(validated)
    chosen = next((c for c in validated if c["word"] == picked), validated[0])
    return chosen["word"], chosen["example"], chosen["definition"]
