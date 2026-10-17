# -*- coding: utf-8 -*-
"""종목 추가가 바로 응답하고(시세/뉴스는 뒤에서) 목록의 loading 표시가 맞는지 — `python3 test_stock_async.py`.

실제 DB/외부 API를 안 쓰려고 임시 SQLite + 가짜 시세/뉴스 함수로 갈아끼움. 백그라운드 작업이 요청 사이에 살아있어야 해서
TestClient를 with로 쓰되(이벤트 루프 유지), 서버 시작 때 도는 재수집(lifespan)은 빈 것으로 바꿈."""
import os
import sys
import tempfile
import time
from contextlib import asynccontextmanager

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient
from sqlmodel import SQLModel, create_engine

import api
import db

tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
tmp.close()
db.engine = create_engine(f"sqlite:///{tmp.name}")
SQLModel.metadata.create_all(db.engine)


@asynccontextmanager
async def _no_lifespan(app):
    yield


api.app.router.lifespan_context = _no_lifespan

SLOW = 1.2  # 가짜 뉴스 가져오기에 걸리는 시간(초)
api._stock_news_cache.clear()
api._stock_quote_cache.clear()
api.quotes.fetch_quote = lambda t: None if t == "NOPE" else {"price": 100.0, "change": 1.0, "percent": 1.0, "time": 1}
api.stocks._fetch_sec_catalog = lambda: [{"ticker": "KNWN", "name": "Known Corp"}]  # 외부(SEC) 호출 없이


def _slow_news(ticker, limit=5):
    time.sleep(SLOW)
    return [{"title": f"{ticker} 뉴스", "link": "https://e.com", "source": "x", "published": None, "title_ko": None}]


api.stocks.fetch_one_with_translation = _slow_news

with TestClient(api.app) as client:
    device_id = client.post("/devices", json={"push_token": "t" * 24}).json()["device_id"]

    # 처음 목록 조회로 기본 10개 시드 — 그 종목들은 캐시가 비어 있어도 "추가 중"이 아니므로 loading=false
    first = client.get(f"/devices/{device_id}/stocks").json()
    assert first and all(w["loading"] is False for w in first)

    # 1) 추가는 뉴스 가져오기를 기다리지 않고 바로 응답(loading=true)
    t0 = time.time()
    r = client.post("/stocks", json={"device_id": device_id, "ticker": "ZZZZ"})
    took = time.time() - t0
    assert r.status_code == 200, r.text
    assert took < SLOW, f"응답이 뉴스 가져오기를 기다림: {took:.2f}s"
    assert r.json()["loading"] is True, r.json()

    # 2) 가져오는 동안 목록에서 그 종목은 loading=true
    mid = {w["ticker"]: w for w in client.get(f"/devices/{device_id}/stocks").json()}
    assert mid["ZZZZ"]["loading"] is True and mid["ZZZZ"]["news"] == []

    # 3) 다 가져오면 loading=false + 시세/뉴스가 채워짐(시세는 뉴스보다 먼저 들어옴)
    deadline = time.time() + 10
    while time.time() < deadline:
        cur = {w["ticker"]: w for w in client.get(f"/devices/{device_id}/stocks").json()}
        if not cur["ZZZZ"]["loading"]:
            break
        time.sleep(0.2)
    assert cur["ZZZZ"]["loading"] is False
    assert cur["ZZZZ"]["quote"]["price"] == 100.0
    assert cur["ZZZZ"]["news"] and cur["ZZZZ"]["news"][0]["title"] == "ZZZZ 뉴스"

    # 3-1) 없는 티커(카탈로그에도 없고 시세도 없음)는 등록 자체를 거절 — 목록에도 안 생김
    bad = client.post("/stocks", json={"device_id": device_id, "ticker": "nope"})
    assert bad.status_code == 422, bad.text
    assert "NOPE" not in {w["ticker"] for w in client.get(f"/devices/{device_id}/stocks").json()}

    # 3-2) 카탈로그에 있는 티커는 시세 조회 없이 바로 등록
    ok = client.post("/stocks", json={"device_id": device_id, "ticker": "KNWN"})
    assert ok.status_code == 200, ok.text

    # 4) 이미 캐시에 있는 티커를 다시 추가하면(다른 기기가 이미 등록) 기다릴 것도 없음 → loading=false
    r2 = client.post("/stocks", json={"device_id": device_id, "ticker": "ZZZZ"})
    assert r2.json()["loading"] is False

print("test_stock_async: ALL OK")
