# -*- coding: utf-8 -*-
"""
관심 종목 가격/등락률 — 2026-09-07 추가.

Finnhub 무료 티어(분당 60회, 카드 등록 없이 키 발급)로 현재가/변동을
가져옴. 환율(USD→KRW)은 Frankfurter.app(유럽중앙은행 기준, 키 불필요,
무료)에서 따로 받아와서 프론트가 "$ 탭하면 원화로 토글" 기능에 씀 —
환율은 하루 단위로만 갱신해도 충분해서 날씨(_fetch_weather)와 같은
캐싱 패턴을 씀.
"""

from __future__ import annotations

import os

import requests

_FINNHUB_QUOTE_URL = "https://finnhub.io/api/v1/quote"
_FRANKFURTER_URL = "https://api.frankfurter.app/latest"


def fetch_quote(ticker: str) -> dict | None:
    """이 티커의 현재가/변동을 가져옴. 키가 없거나(로컬 개발 등) API
    호출이 실패하면(없는 티커 포함 — Finnhub은 없는 심볼에 c=0을
    돌려줌) 조용히 None — 호출하는 쪽에서 가격 없이 뉴스만 보여주면 됨."""
    key = os.environ.get("FINNHUB_API_KEY")
    if not key:
        return None
    try:
        res = requests.get(_FINNHUB_QUOTE_URL, params={"symbol": ticker, "token": key}, timeout=8)
        res.raise_for_status()
        data = res.json()
        if not data.get("c"):
            return None
        return {"price": data["c"], "change": data["d"], "percent": data["dp"]}
    except Exception:  # noqa: BLE001 - 한 티커 실패가 전체 갱신을 막으면 안 됨
        return None


def fetch_quotes(tickers: list[str]) -> dict[str, dict]:
    """여러 티커의 가격을 한 번에 가져옴 — api.py의 갱신 루프에서 씀."""
    result = {}
    for t in tickers:
        q = fetch_quote(t)
        if q is not None:
            result[t] = q
    return result


def fetch_usd_krw_rate() -> float | None:
    try:
        res = requests.get(_FRANKFURTER_URL, params={"from": "USD", "to": "KRW"}, timeout=8)
        res.raise_for_status()
        return res.json()["rates"]["KRW"]
    except Exception:  # noqa: BLE001 - 실패해도 프론트가 달러만 보여주면 됨
        return None
