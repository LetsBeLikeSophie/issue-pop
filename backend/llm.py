# -*- coding: utf-8 -*-
"""Claude API 호출 공용 유틸.

- category.py: 이슈 카테고리 분류(purpose="category", 새 이슈 키워드마다 1회, 30일 캐시).
- word_of_day.py: 후보 단어 중 하나를 고르는 데 씀(purpose="wordofday", 하루 1번).
- cluster_audit.py: 오늘 클러스터들의 키워드/카테고리/기사 매칭이 이상한지
  배치로 감사하는 데 씀(purpose="audit", 하루 1번, 여러 클러스터를 묶어서 몇 번만 호출).

둘 다 저렴하고 간단한 판단 작업이라 제일 가벼운 모델(Haiku)을 씀.

인증키는 서버 systemd 환경변수로만 존재함 — 로컬 개발 시엔 같은 이름으로 환경변수를
직접 설정해야 동작함(translate.py 등과 같은 패턴).

2026-10-20: 기능별로 Anthropic Console 키를 나눠서 "어느 기능에 비용이 많이 드는지"를 콘솔 사용량에서 바로
보려고, 호출마다 purpose를 받아 ANTHROPIC_KEY_<PURPOSE> 환경변수(예: ANTHROPIC_KEY_CATEGORY)를 먼저 찾고,
없으면 예전 공용 키 ANTHROPIC_API_KEY로 폴백함(키를 하나씩 옮겨가도 서비스가 안 깨지게). 이름 규칙은
backend/API_KEYS.md 참고.
"""

from __future__ import annotations

import json
import os

import requests

_API_URL = "https://api.anthropic.com/v1/messages"
_MODEL = "claude-haiku-4-5-20251001"


def api_key_for(purpose: str | None) -> str | None:
    """이 용도의 키: ANTHROPIC_KEY_<PURPOSE>가 있으면 그걸, 없으면 공용 ANTHROPIC_API_KEY(옛 방식)를 돌려줌.
    호출할 때마다 환경변수를 읽음(서버가 키를 바꾸고 재시작하면 바로 반영되고, 테스트에서 바꿔 끼우기도 쉬움)."""
    if purpose:
        specific = os.environ.get(f"ANTHROPIC_KEY_{purpose.upper()}")
        if specific:
            return specific
    return os.environ.get("ANTHROPIC_API_KEY")


def complete(
    prompt: str,
    max_tokens: int = 1024,
    temperature: float | None = None,
    purpose: str | None = None,
) -> str | None:
    """Claude Haiku에 프롬프트 하나를 보내고 텍스트 응답을 받음. 키가
    없거나 API 실패 시 None(호출부가 각자 폴백 처리).

    temperature: 기본(None)이면 API 기본값(1.0에 가까움) 그대로 씀 — 지금까지의
    호출부(단어 고르기 등)는 이걸로 충분했음. 2026-09-29: 카테고리 분류처럼
    답을 오래 캐싱해두는 용도로 쓰려니, 애매한 케이스에서 같은 입력에도
    호출마다 답이 달라지는 걸 실측으로 확인함("암살자" 케이스가 문화/연예를
    오갔음) — 한 번 뽑은 답을 계속 재사용하는 구조에서는 그 "한 번"이 최대한
    일관된 답이어야 해서, 이런 용도는 낮은 temperature를 명시적으로 넘기게 함."""
    api_key = api_key_for(purpose)
    if not api_key:
        return None
    try:
        payload = {
            "model": _MODEL,
            "max_tokens": max_tokens,
            "messages": [{"role": "user", "content": prompt}],
        }
        if temperature is not None:
            payload["temperature"] = temperature
        res = requests.post(
            _API_URL,
            headers={
                "x-api-key": api_key,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            data=json.dumps(payload),
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
    text = complete(prompt, max_tokens=30, purpose="wordofday")
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
