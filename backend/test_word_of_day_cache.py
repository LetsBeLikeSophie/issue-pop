# -*- coding: utf-8 -*-
"""오늘의 단어: 실패해도 요청마다 다시 계산하지 않음 — `python3 test_word_of_day_cache.py` (출시 전 점검 IP-06)."""
import os
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient
from sqlmodel import SQLModel, create_engine

import api
import db

tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
tmp.close()
db.engine = create_engine(f"sqlite:///{tmp.name}")
SQLModel.metadata.create_all(db.engine)

calls = []
outcome = {"value": None}


def fake_pick(cache):
    calls.append(1)
    if isinstance(outcome["value"], Exception):
        raise outcome["value"]
    return outcome["value"]


api.word_of_day.pick_word = fake_pick
client = TestClient(api.app)

# 1) 요청(GET /word-of-day)은 저장된 값만 읽음 — 단어가 아직 없으면 계산하지 않고 빈 값
r = client.get("/word-of-day").json()
assert r["word"] is None and calls == []

# 2) 백그라운드 계산이 실패(None)하면 30분 동안은 다시 계산하지 않음
assert api._get_or_create_word_of_day() is None and len(calls) == 1
for _ in range(5):
    assert api._get_or_create_word_of_day() is None
assert len(calls) == 1, "실패한 계산을 다시 시도함"

# 3) 예외로 실패해도 마찬가지(예외가 밖으로 안 새고, 쉬는 시간이 걸림)
api._word_of_day_retry_at = 0
calls.clear()
outcome["value"] = RuntimeError("사전 API 오류")
assert api._get_or_create_word_of_day() is None and len(calls) == 1
assert api._get_or_create_word_of_day() is None and len(calls) == 1

# 4) 쉬는 시간이 지난 뒤 성공하면 저장되고, 요청이 그 값을 읽음. 이후엔 다시 계산하지 않음
api._word_of_day_retry_at = 0
calls.clear()
outcome["value"] = ("비상계엄", "예문", "뜻풀이")
row = api._get_or_create_word_of_day()
assert row is not None and row.word == "비상계엄" and len(calls) == 1
assert client.get("/word-of-day").json()["word"] == "비상계엄"
api._get_or_create_word_of_day()
assert len(calls) == 1

# 5) 계산 중이면(락) 다른 호출은 기다리지 않고 None
with db.get_session() as s:
    s.delete(s.get(db.WordOfDay, row.date))
    s.commit()
api._word_of_day_lock.acquire()
try:
    assert api._get_or_create_word_of_day() is None and len(calls) == 1
finally:
    api._word_of_day_lock.release()

print("test_word_of_day_cache: ALL OK")
