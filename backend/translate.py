# -*- coding: utf-8 -*-
"""
Claude Haiku 번역 — 2026-10-04, 파파고(NCP)에서 교체.

관심 종목 뉴스가 전부 영어라("이거 어느정도 번역은 해줘야겠는데" 피드백)
헤드라인만 한국어로 옮겨줌.

파파고는 "월 사용 글자수를 100만 자 단위로 올림" 해서 과금하는 구조라,
실사용량(월 40만 자 안팎)에 비해 늘 고정 20,000원이 나갔음(무료 제공량
자체가 없음) — 실측으로 확인하고 Claude Haiku로 교체함(쓴 토큰만큼만
과금, 월 최소과금 없음. 같은 사용량 기준 추산 월 2~3달러 수준).

인증키는 llm.py가 쓰는 키와 일부러 분리함 — Anthropic Console 사용량 대시보드에서 번역 비용만 따로
확인할 수 있게. 2026-10-20: 이름을 기능별 규칙(ANTHROPIC_KEY_TRANSLATE, backend/API_KEYS.md)으로 바꿈 —
예전 이름 ANTHROPIC_TRANSLATE_API_KEY도 계속 읽어서(없을 때) 서버 환경변수를 옮기는 중에도 안 깨짐. 서버의 systemd 서비스 환경변수로만 존재함
(/etc/systemd/system/newstrend-api.service.d/env.conf, git에는 안 올라감)
— 로컬에서 돌리려면 같은 이름으로 환경변수를 직접 설정해야 함.
"""

from __future__ import annotations

import json
import os
import re

import requests

_API_URL = "https://api.anthropic.com/v1/messages"
_MODEL = "claude-haiku-4-5"


def _api_key() -> str | None:
    return os.environ.get("ANTHROPIC_KEY_TRANSLATE") or os.environ.get("ANTHROPIC_TRANSLATE_API_KEY")


_QUOTE_PAIRS = {'"': '"', "'": "'", "“": "”", "‘": "’"}


def _unwrap_quotes(s: str) -> str:
    """모델이 번역문 전체를 따옴표로 감싸 답했을 때만 겉 따옴표를 벗김.
    2026-11-10: 예전엔 strip("\\"'")로 양끝 따옴표를 무조건 떼서, 헤드라인 끝이
    인용으로 끝나는 경우(예: ...'대박 아니면 매도') 닫는 따옴표만 사라지고 짝이
    깨졌음(실측 30건 중 3건). 감싼 경우가 아니면 그대로 둠."""
    s = s.strip()
    if len(s) >= 2 and s[0] in _QUOTE_PAIRS and s[-1] == _QUOTE_PAIRS[s[0]]:
        inner = s[1:-1]
        if s[0] not in inner and s[-1] not in inner:
            return inner.strip()
    return s


def _post(payload: dict, api_key: str) -> str:
    res = requests.post(
        _API_URL,
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
        data=json.dumps(payload),
        timeout=30,
    )
    res.raise_for_status()
    return res.json()["content"][0]["text"].strip()


_BATCH_LINE = re.compile(r"^\s*(\d+)\s*[.)]\s*(.+?)\s*$")
BATCH_SIZE = 10


def translate_many(texts: list[str]) -> list[str | None]:
    """여러 헤드라인을 한 번의 호출로 번역(2026-11-10). 호출마다 붙는 시스템
    프롬프트 입력 토큰과 요청 오버헤드를 나눠 쓰려는 것. 번호를 붙여 보내고
    같은 번호로 받아서 순서를 맞춤 — 응답이 일부 빠지거나 형식이 깨지면 그
    줄만 None(호출부가 낱개 호출로 다시 시도). 키 없음/API 실패는 전부 None."""
    results: list[str | None] = [None] * len(texts)
    api_key = _api_key()
    if not api_key:
        return results
    for start in range(0, len(texts), BATCH_SIZE):
        chunk = texts[start : start + BATCH_SIZE]
        lines = [f"{i}. {' '.join(t.split())}" for i, t in enumerate(chunk, 1)]
        try:
            payload = {
                "model": _MODEL,
                "max_tokens": 150 * len(chunk),
                "temperature": 0,
                "system": (
                    "너는 뉴스 헤드라인 번역기야. 번호가 붙은 영어 뉴스 헤드라인이 여러 줄 "
                    "들어오면 각각을 자연스러운 한국어 뉴스 헤드라인 톤으로 번역해. "
                    "같은 번호를 붙여서 한 줄에 하나씩, '번호. 번역문' 형식으로만 답해. "
                    "설명이나 따옴표는 붙이지 마."
                ),
                "messages": [{"role": "user", "content": "\n".join(lines)}],
            }
            out = _post(payload, api_key)
        except Exception:  # noqa: BLE001 - 실패하면 이 묶음은 None으로 두고 낱개 폴백
            continue
        for line in out.splitlines():
            m = _BATCH_LINE.match(line)
            if not m:
                continue
            idx = int(m.group(1)) - 1
            if 0 <= idx < len(chunk) and results[start + idx] is None:
                results[start + idx] = _unwrap_quotes(m.group(2)) or None
    return results


def translate_to_ko(text: str) -> str | None:
    """영어 텍스트를 한국어로 번역. 키가 없거나(로컬 개발 등) API 호출이
    실패하면 조용히 None — 호출하는 쪽에서 원문을 그대로 보여주면 됨
    (다른 외부 API 연동들과 같은 방어 원칙, api.py의 _fetch_weather 참고).

    temperature=0 — 번역 결과를 해시로 캐싱해서 평생 재사용하는 구조라
    (stocks.py의 _translate_cached), 같은 헤드라인은 항상 같은 번역이
    나와야 함(llm.py의 카테고리 분류와 같은 이유)."""
    api_key = _api_key()
    if not api_key or not text.strip():
        return None
    try:
        payload = {
            "model": _MODEL,
            "max_tokens": 200,
            "temperature": 0,
            "system": (
                "너는 뉴스 헤드라인 번역기야. 입력된 영어 뉴스 헤드라인을 "
                "자연스러운 한국어 뉴스 헤드라인 톤으로 번역해. 설명이나 "
                "따옴표 없이 번역문 한 줄만 답해."
            ),
            "messages": [{"role": "user", "content": text}],
        }
        return _unwrap_quotes(_post(payload, api_key)) or None
    except Exception:  # noqa: BLE001 - 번역 실패해도 원문을 보여주면 되니 전체 갱신을 막으면 안 됨
        return None
