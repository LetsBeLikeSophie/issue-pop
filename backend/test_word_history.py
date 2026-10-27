# -*- coding: utf-8 -*-
"""지난 오늘의 단어(/word-of-day/history) — `python3 test_word_history.py`."""
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

with db.get_session() as s:
    for i in range(1, 41):  # 40일치
        s.add(db.WordOfDay(date=f"2026-09-{i:02d}" if i <= 30 else f"2026-10-{i - 30:02d}", word=f"단어{i}", example="예문", definition=f"뜻{i}"))
    s.add(db.WordOfDay(date="2026-10-11", word="", example="", definition=None))  # 단어가 비어 있는 날은 건너뜀
    s.commit()

client = TestClient(api.app)
r = client.get("/word-of-day/history")
assert r.status_code == 200 and "max-age=300" in r.headers["cache-control"]
rows = r.json()
# 기본 30일, 최신순, 날짜·단어·뜻만(예문 등은 안 내려줌)
assert len(rows) <= 30
dates = [x["date"] for x in rows]
assert dates == sorted(dates, reverse=True)
assert set(rows[0]) == {"date", "word", "definition"} and rows[0]["date"] == "2026-10-11" or rows[0]["word"] != ""
assert all(x["word"] for x in rows)

assert len(client.get("/word-of-day/history", params={"days": 5}).json()) <= 5
assert client.get("/word-of-day/history", params={"days": 0}).status_code == 422
assert client.get("/word-of-day/history", params={"days": 91}).status_code == 422
assert client.get("/word-of-day/history", params={"days": 90}).status_code == 200

# 비어 있어도 오류 없이 빈 목록
with db.get_session() as s:
    s.exec(db.delete(db.WordOfDay))
    s.commit()
assert client.get("/word-of-day/history").json() == []

print("test_word_history: ALL OK")
