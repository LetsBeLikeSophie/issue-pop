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

import dictionary
import text_utils

# 뉴스에 매일 나오지만 "어렵다"고 하기엔 너무 일상적인 명사 — 실측하며
# 계속 추가할 스톱리스트(완벽한 빈도 사전이 없어서 v0 수준의 필터링임).
_COMMON_STOPWORDS = {
    "오늘", "발표", "관련", "정부", "국민", "사회", "경제", "정치", "사건",
    "기자", "보도", "뉴스", "사진", "영상", "취재", "확인", "논란", "문제",
    "상황", "이후", "이번", "지난", "올해", "내년", "지금", "당시", "현재",
    "대통령", "위원회", "기업", "시장", "국내", "해외", "전국", "지역",
    "우리나라", "관계자", "담당자", "책임자", "이야기", "생각", "사람들",
}


def pick_word(cache: dict) -> tuple[str, str, str | None] | None:
    """오늘 캐시(_cache.values(), 각 c["articles"]에 기사 목록)에서 후보
    단어와 그 단어가 실제로 나온 기사 제목(예문)을 골라 (단어, 예문, 뜻풀이)
    로 반환. 후보가 하나도 없으면 None.

    2026-09-11: 사전 API 연동 후 — 후보를 길이 내림차순으로 보면서 실제
    표준국어대사전 표제어인 것을 찾으면 그걸 채택함. 사전에 없으면
    "울산시립미술관" 같은 기관명/고유명사일 가능성이 높다는 걸 실측으로
    발견해서(길이만으로 고르던 v0의 한계), 사전 조회 자체를 필터로 씀 —
    이러면 진짜 사전에 있는 말만 고르게 됨. 키가 없거나 후보 전부 사전에
    안 걸리면(무료 API라 연결 실패 등도 있을 수 있음) 정의 없이 가장 긴
    후보를 그대로 반환함(단어/예문만이라도 보여줄 가치는 있음)."""
    candidates: dict[str, str] = {}
    for c in cache.values():
        for a in c.get("articles", []):
            title = a.get("title", "")
            if not title:
                continue
            for tok in text_utils.kiwi.tokenize(title):
                if tok.tag != "NNG":
                    continue
                if len(tok.form) < 3:
                    continue
                if tok.form in _COMMON_STOPWORDS:
                    continue
                candidates.setdefault(tok.form, title)
    if not candidates:
        return None

    ordered = sorted(candidates, key=len, reverse=True)
    for word in ordered:
        definition = dictionary.lookup(word)
        if definition:
            return word, candidates[word], definition

    word = ordered[0]
    return word, candidates[word], None
