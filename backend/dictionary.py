# -*- coding: utf-8 -*-
"""국립국어원 표준국어대사전 Open API — 단어 하나의 첫 번째 뜻풀이만 가져옴.

인증키는 서버 systemd 환경변수(STDICT_API_KEY)로만 존재함 — 로컬 개발 시엔
같은 이름으로 환경변수를 직접 설정해야 동작함(translate.py/quotes.py와 같은
패턴). 키가 없거나 API가 실패하면 None을 반환하고, 호출부(word_of_day.py)가
그 경우 정의 없이 단어/예문만 보여줌.

**저작권 참고**: 표준국어대사전 자료는 CC BY-SA 2.0 KR 라이선스라 뜻풀이를
그대로(원문 그대로) 보여줄 때 "국립국어원 표준국어대사전" 출처 표시가
필요함(가공 없이 인용만 하는 거라 동일조건변경허락까지는 안 걸림) — 이
정의를 보여주는 화면(app/lib/screens/settings_screen.dart)에 출처 표시를
같이 넣어둠.
"""

from __future__ import annotations

import os

import requests

_API_KEY = os.environ.get("STDICT_API_KEY")
_BASE_URL = "https://stdict.korean.go.kr/api/search.do"


def lookup(word: str) -> str | None:
    """표제어 word의 뜻풀이(첫 번째 의미) — 사전에 없거나 API 실패 시 None."""
    if not _API_KEY:
        return None
    try:
        res = requests.get(
            _BASE_URL,
            params={"key": _API_KEY, "q": word, "req_type": "json"},
            timeout=5,
        )
        res.raise_for_status()
        data = res.json()
    except Exception:
        return None

    items = data.get("channel", {}).get("item")
    if not items:
        return None
    item = items[0]
    sense = item.get("sense")
    if isinstance(sense, list):
        sense = sense[0] if sense else None
    if not isinstance(sense, dict):
        return None
    return sense.get("definition")
