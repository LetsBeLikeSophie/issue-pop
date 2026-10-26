# -*- coding: utf-8 -*-
"""방문자 집계(오늘/최근 10분/일별) — `python3 test_visitors.py`."""
import base64
import os
import sys
import tempfile

os.environ["ADMIN_USERNAME"] = "boss"
os.environ["ADMIN_PASSWORD"] = "s3cret-pw"
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient
from sqlmodel import SQLModel, create_engine

import api
import db

tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
tmp.close()
db.engine = create_engine(f"sqlite:///{tmp.name}")
SQLModel.metadata.create_all(db.engine)

client = TestClient(api.app)
AUTH = {"Authorization": "Basic " + base64.b64encode(b"boss:s3cret-pw").decode()}
day = {"value": "2026-10-26"}
api._kst_today = lambda: day["value"]


def cid(n):
    return f"{n:032x}"


def ping(n):
    r = client.post("/presence/ping", json={"client_id": cid(n)})
    assert r.status_code == 200, r.text


# 1) 인증 없이는 못 봄
assert client.get("/admin/visitors").status_code == 401
assert client.get("/admin/visitors", headers={"Authorization": "Basic " + base64.b64encode(b"boss:x").decode()}).status_code == 401

# 2) 서로 다른 설치 3곳 → 오늘 3, 최근 10분 3. 같은 설치가 다시 보내도 늘지 않음
for n in (1, 2, 3, 1, 2, 1):
    ping(n)
stats = client.get("/admin/visitors", headers=AUTH).json()
assert stats["today"] == 3 and stats["online_10min"] == 3 and stats["date"] == "2026-10-26", stats
assert stats["recent_days"][0] == {"date": "2026-10-26", "count": 3}

# 3) 저장(주기 저장)하면 DB에는 숫자만 남음(식별자 없음)
api._flush_visitors()
with db.get_session() as s:
    rows = s.exec(db.select(db.VisitorDay)).all()
    assert [(r.date, r.count) for r in rows] == [("2026-10-26", 3)]
    assert not any(hasattr(r, "client_id") for r in rows)

# 4) 날짜가 바뀌면 어제 값이 확정 저장되고 오늘은 새로 시작
day["value"] = "2026-10-27"
ping(4)
ping(5)
stats = client.get("/admin/visitors", headers=AUTH).json()
assert stats["today"] == 2 and stats["date"] == "2026-10-27"
assert stats["recent_days"][:2] == [{"date": "2026-10-27", "count": 2}, {"date": "2026-10-26", "count": 3}], stats

# 5) 서버를 재시작해 메모리가 비어도 오늘 값은 DB에 남긴 값 아래로 줄지 않음
api._flush_visitors()
api._visitors_today.clear()
api._presence.clear()
stats = client.get("/admin/visitors", headers=AUTH).json()
assert stats["today"] == 2 and stats["online_10min"] == 0, stats
ping(6)
assert client.get("/admin/visitors", headers=AUTH).json()["today"] == 2  # max(DB 2, 메모리 1)
ping(7)
ping(8)
assert client.get("/admin/visitors", headers=AUTH).json()["today"] == 3  # 메모리가 DB를 넘으면 그 값

# 6) 최근 7일만 내려줌
for i in range(2, 12):
    with db.get_session() as s:
        s.add(db.VisitorDay(date=f"2026-10-{i:02d}", count=i))
        s.commit()
days = client.get("/admin/visitors", headers=AUTH).json()["recent_days"]
assert len(days) == 7 and days[0]["date"] == "2026-10-27"

print("test_visitors: ALL OK")
