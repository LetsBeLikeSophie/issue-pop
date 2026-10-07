# -*- coding: utf-8 -*-
"""
Claude Haiku 번역 — 2026-10-04, 파파고(NCP)에서 교체.

관심 종목 뉴스가 전부 영어라("이거 어느정도 번역은 해줘야겠는데" 피드백)
헤드라인만 한국어로 옮겨줌.

파파고는 "월 사용 글자수를 100만 자 단위로 올림" 해서 과금하는 구조라,
실사용량(월 40만 자 안팎)에 비해 늘 고정 20,000원이 나갔음(무료 제공량
자체가 없음) — 실측으로 확인하고 Claude Haiku로 교체함(쓴 토큰만큼만
과금, 월 최소과금 없음. 같은 사용량 기준 추산 월 2~3달러 수준).

인증키(ANTHROPIC_TRANSLATE_API_KEY)는 llm.py가 쓰는 ANTHROPIC_API_KEY와
일부러 분리함 — Anthropic Console 사용량 대시보드에서 번역 비용만 따로
확인할 수 있게. 서버의 systemd 서비스 환경변수로만 존재함
(/etc/systemd/system/newstrend-api.service.d/env.conf, git에는 안 올라감)
— 로컬에서 돌리려면 같은 이름으로 환경변수를 직접 설정해야 함.
"""

from __future__ import annotations

import json
import os

import requests

_API_KEY = os.environ.get("ANTHROPIC_TRANSLATE_API_KEY")
_API_URL = "https://api.anthropic.com/v1/messages"
_MODEL = "claude-haiku-4-5"


def translate_to_ko(text: str) -> str | None:
    """영어 텍스트를 한국어로 번역. 키가 없거나(로컬 개발 등) API 호출이
    실패하면 조용히 None — 호출하는 쪽에서 원문을 그대로 보여주면 됨
    (다른 외부 API 연동들과 같은 방어 원칙, api.py의 _fetch_weather 참고).

    temperature=0 — 번역 결과를 해시로 캐싱해서 평생 재사용하는 구조라
    (stocks.py의 _translate_cached), 같은 헤드라인은 항상 같은 번역이
    나와야 함(llm.py의 카테고리 분류와 같은 이유)."""
    if not _API_KEY or not text.strip():
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
        res = requests.post(
            _API_URL,
            headers={
                "x-api-key": _API_KEY,
                "anthropic-version": "2023-06-01",
                "content-type": "application/json",
            },
            data=json.dumps(payload),
            timeout=20,
        )
        res.raise_for_status()
        return res.json()["content"][0]["text"].strip().strip("\"'")
    except Exception:  # noqa: BLE001 - 번역 실패해도 원문을 보여주면 되니 전체 갱신을 막으면 안 됨
        return None
