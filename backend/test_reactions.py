"""고정 반응 5개 / 접속자 수 엔드포인트 테스트 — `python3 test_reactions.py`.

실제 news_trend.db를 건드리지 않도록 임시 SQLite로 엔진을 갈아끼우고, lifespan(서버
시작 시 재수집/재클러스터링)을 안 돌리려고 TestClient를 with 없이 씀."""
import datetime as dt
import os
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient
from sqlmodel import SQLModel, create_engine, select

import api
import db

tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
tmp.close()
db.engine = create_engine(f"sqlite:///{tmp.name}")
SQLModel.metadata.create_all(db.engine)

api._cache.clear()
api._cache["a1"] = {"id": "a1", "keyword": "추미애", "keywords": ["추미애"], "article_count": 5, "outlet_count": 3}
api._cache["b1"] = {"id": "b1", "keyword": "카카오", "keywords": ["카카오"], "article_count": 4, "outlet_count": 2}

client = TestClient(api.app)
ME, OTHER, THIRD, FOURTH = "a" * 32, "b" * 32, "c" * 32, "d" * 32


def set_(cid, kw, reaction):
    return client.post("/reactions/set", json={"client_id": cid, "keyword": kw, "reaction": reaction})


# 1) 고르면 집계/내 반응/대표 반응이 반영됨
r = set_(ME, "추미애", "angry")
assert r.status_code == 200, r.text
assert r.json() == {"counts": {"angry": 1}, "people": 1, "top": "angry", "mine": "angry"}, r.json()

# 2) 여러 사람 — 가장 많은 게 top, 사람 수는 합계(한 사람 하나)
set_(OTHER, "추미애", "angry")
set_(THIRD, "추미애", "worried")
body = client.get("/reactions", params={"keywords": ["추미애", "카카오"], "client_id": ME}).json()
assert body["추미애"] == {"counts": {"angry": 2, "worried": 1}, "people": 3, "top": "angry", "mine": "angry"}, body["추미애"]
assert body["카카오"] == {"counts": {}, "people": 0, "top": None, "mine": None}

# 3) 다른 걸 고르면 바뀜(한 카드에 하나만) — 합계는 그대로
r = set_(ME, "추미애", "sorry")
assert r.json()["mine"] == "sorry"
assert r.json()["counts"] == {"angry": 1, "worried": 1, "sorry": 1} and r.json()["people"] == 3, r.json()

# 4) None이면 지움(없는데 지워도 안전)
r = set_(ME, "추미애", None)
assert r.json()["mine"] is None and r.json()["people"] == 2
assert set_(ME, "추미애", None).status_code == 200

# 5) 동률이면 REACTION_KEYS 순서로 대표를 고름(like가 angry보다 앞)
set_(FOURTH, "카카오", "curious")
set_(THIRD, "카카오", "like")
assert client.get("/reactions", params={"keywords": ["카카오"]}).json()["카카오"]["top"] == "like"

# 6) 허용 키만: 이모지/글자/빈 문자열/대소문자 다른 키는 거부
for bad in ("😡", "화나요", "", "ANGRY", "angry ", "love"):
    assert set_(ME, "추미애", bad).status_code == 422, repr(bad)

# 7) 알 수 없는 키워드 / 잘못된 client_id
assert set_(ME, "없는키워드", "like").status_code == 404
assert set_("not-hex", "추미애", "like").status_code == 422
assert client.get("/reactions", params={"keywords": ["추미애"], "client_id": "zz"}).status_code == 422

# 8) 접속자 수: 3명 미만이면 show=false(숫자를 지어내지 않음), 3명 이상이면 true
api._presence.clear()
r = client.post("/presence/ping", json={"client_id": ME})
assert r.json()["online"] == 1 and r.json()["show"] is False
client.post("/presence/ping", json={"client_id": OTHER})
r = client.post("/presence/ping", json={"client_id": THIRD})
assert r.json()["online"] == 3 and r.json()["show"] is True
assert client.post("/presence/ping", json={"client_id": ME}).json()["online"] == 3  # 같은 설치는 중복 집계 안 됨
api._presence[OTHER] = time.time() - api.PRESENCE_WINDOW_SECONDS - 5  # 10분 지난 건 빠짐
r = client.post("/presence/ping", json={"client_id": ME})
assert r.json()["online"] == 2 and r.json()["show"] is False
assert client.post("/presence/ping", json={"client_id": "zz"}).status_code == 422

# 9) 오래된 반응 정리
with db.get_session() as s:
    s.add(db.Reaction(keyword="추미애", client_id="e" * 32, reaction="like", created_at=db.now() - dt.timedelta(days=400)))
    s.commit()
    assert db.prune_old_reactions(s) == 1
    assert s.exec(select(db.Reaction).where(db.Reaction.client_id == "e" * 32)).first() is None

print("test_reactions: ALL OK")
