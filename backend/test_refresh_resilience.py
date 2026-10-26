# -*- coding: utf-8 -*-
"""갱신/백그라운드 루프가 예외 한 번에 멈추지 않는지, /health가 갱신 정체를 알리는지 — `python3 test_refresh_resilience.py`.

2026-10-26 출시 전 점검(IP-01): run() 뒤 단계에서 예외가 나면 갱신 루프 태스크가 죽고 /health는 계속 ok였음."""
import asyncio
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient

import api

# 1) run() 뒤 단계(카테고리 분류 등)가 예외를 던져도 refresh_cache는 예외를 밖으로 안 던지고 _last_error를 남김
api.run = lambda live=True: []


def boom(_cache):
    raise RuntimeError("database is locked")


api._classify_categories = boom
asyncio.run(api.refresh_cache())  # 예외가 새면 여기서 테스트가 실패함
assert api._last_error and "database is locked" in api._last_error, api._last_error

# 2) 백그라운드 루프: 본문이 예외를 던져도 다음 주기에 계속 돎(태스크가 죽지 않음)
for loop_name, hook_name, interval_name in [
    ("_digest_loop", "_digest_check", "DIGEST_CHECK_INTERVAL_SECONDS"),
    ("_cluster_audit_loop", "_cluster_audit_check", "CLUSTER_AUDIT_CHECK_INTERVAL_SECONDS"),
]:
    calls = []

    def failing_hook(*a, _calls=calls, **k):
        _calls.append(1)
        raise RuntimeError("일시적 오류")

    setattr(api, hook_name, failing_hook)
    setattr(api, interval_name, 0.01)
    api._word_of_day_alert_check = lambda force=False: []

    async def run_loop(name=loop_name):
        task = asyncio.create_task(getattr(api, name)())
        await asyncio.sleep(0.3)
        died = task.done()
        task.cancel()
        return died

    died = asyncio.run(run_loop())
    assert not died, f"{loop_name}가 예외 한 번에 죽음"
    assert len(calls) >= 2, (loop_name, len(calls))

# 3) 단어 루프와 종목 카탈로그 루프도 마찬가지
word_calls = []


def failing_word():
    word_calls.append(1)
    raise RuntimeError("사전 API 오류")


api._get_or_create_word_of_day = failing_word
api.WORD_OF_DAY_CHECK_INTERVAL_SECONDS = 0.01


async def run_word():
    task = asyncio.create_task(api._word_of_day_loop())
    await asyncio.sleep(0.3)
    died = task.done()
    task.cancel()
    return died


assert not asyncio.run(run_word()) and len(word_calls) >= 2

cat_calls = []


def failing_catalog():
    cat_calls.append(1)
    raise RuntimeError("SEC 오류")


api.stocks.refresh_sec_catalog = failing_catalog
api.STOCK_CATALOG_REFRESH_INTERVAL_SECONDS = 0.01


async def run_catalog():
    task = asyncio.create_task(api._stock_catalog_refresh_loop())
    await asyncio.sleep(0.3)
    died = task.done()
    task.cancel()
    return died


assert not asyncio.run(run_catalog()) and len(cat_calls) >= 2

# 4) /health: 비어 있으면 warming_up, 최근 갱신이면 ok, 90분 넘게 갱신이 없으면 stale
client = TestClient(api.app)
api._cache.clear()
assert client.get("/health").json()["status"] == "warming_up"
api._cache["x"] = {"keyword": "k"}
api._last_refresh = time.time() - 60
assert client.get("/health").json()["status"] == "ok"
api._last_refresh = time.time() - 91 * 60
assert client.get("/health").json()["status"] == "stale"
api._last_refresh = None
assert client.get("/health").json()["status"] == "ok"  # 아직 한 번도 갱신 기록이 없으면 stale로 단정하지 않음

print("test_refresh_resilience: ALL OK")
