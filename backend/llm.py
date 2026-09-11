# -*- coding: utf-8 -*-
"""Claude API 호출 공용 유틸.

- word_of_day.py: 후보 단어 중 하나를 고르는 데 씀(하루 1번).
- cluster_audit.py: 오늘 클러스터들의 키워드/카테고리/기사 매칭이 이상한지
  배치로 감사하는 데 씀(하루 1번, 여러 클러스터를 묶어서 몇 번만 호출).

둘 다 저렴하고 간단한 판단 작업이라 제일 가벼운 모델(Haiku)을 씀.

인증키는 서버 systemd 환경변수(ANTHROPIC_API_KEY)로만 존재함 — 로컬
개발 시엔 같은 이름으로 환경변수를 직접 설정해야 동작함(translate.py 등과
같은 패턴).
"""

from __future__ import annotations

import json
import os

import requests

_API_KEY = os.environ.get("ANTHROPIC_API_KEY")
_API_URL = "https://api.anthropic.com/v1/messages"
_MODEL = "claude-haiku-4-5-20251001"


def complete(prompt: str, max_tokens: int = 1024) -> str | None:
    """Claude Haiku에 프롬프트 하나를 보내고 텍스트 응답을 받음. 키가
    없거나 API 실패 시 None(호출부가 각자 폴백 처리)."""
    if not _API_KEY:
        return None
    try:
        res = requests.post(
            _API_URL,
            headers={
                "x-api-key": _API_KEY,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            data=json.dumps(
                {
                    "model": _MODEL,
                    "max_tokens": max_tokens,
                    "messages": [{"role": "user", "content": prompt}],
                }
            ),
            timeout=60,
        )
        res.raise_for_status()
        return res.json()["content"][0]["text"].strip()
    except Exception:
        return None


def pick_best_word(candidates: list[dict]) -> str | None:
    """candidates: [{"word": ..., "example": ..., "definition": ...}, ...]
    이 중 "오늘의 단어"로 가장 적합한 것의 word를 반환. API 실패, 혹은
    응답이 후보 목록에 없는 말이면(안전장치 — LLM이 목록 밖의 말을
    지어내면 안 되니까) None을 반환하고, 호출부가 기존 규칙 기반
    폴백으로 넘어감."""
    if not candidates:
        return None

    lines = [f'- "{c["word"]}": {c["definition"]} (예문: {c["example"]})' for c in candidates]
    prompt = (
        "다음은 오늘 뉴스에 여러 번 나온 단어 후보들이야. 이 중에서 "
        "'오늘의 단어'로 가장 적합한 것 하나를 골라줘 — 뉴스를 보며 "
        "어휘 공부를 하듯, 뜻을 알아두면 유용하고 적당히 생소한 단어가 "
        "좋아. 너무 전문적이거나(예: 화학식, 법률 조항 번호) 반대로 "
        "누구나 아는 쉬운 말은 피해줘.\n\n"
        + "\n".join(lines)
        + "\n\n반드시 위 목록에 있는 단어 하나만, 다른 설명 없이 그 단어만 답해."
    )
    text = complete(prompt, max_tokens=30)
    if text is None:
        return None

    valid_words = {c["word"] for c in candidates}
    # 가끔 따옴표/마침표를 붙여서 답할 수 있어서 정확히 일치하는 후보를
    # 찾을 때까지 살짝 정리해서 비교함.
    cleaned = text.strip("\"'. \n")
    if cleaned in valid_words:
        return cleaned
    for word in valid_words:
        if word in text:
            return word
    return None
