# -*- coding: utf-8 -*-
"""언론사별 기사 수(/outlet-stats) — `python3 test_outlet_stats.py`."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient

import api
import sources

client = TestClient(api.app)
names = [s["outlet"] for s in sources.RSS_SOURCES]
first, second, third = names[0], names[1], names[2]

api._cache.clear()
api._cache["a"] = {"articles": [{"outlet": first}, {"outlet": first}, {"outlet": second}]}
api._cache["b"] = {"articles": [{"outlet": first}, {"outlet": "목록에 없는 매체"}]}

r = client.get("/outlet-stats")
assert r.status_code == 200 and "max-age=300" in r.headers["cache-control"]
rows = r.json()
by = {x["outlet"]: x for x in rows}

# 수집 중인 언론사는 전부 나옴(0건 포함), 목록에 없는 매체는 안 나옴
assert set(by) == set(names), set(by) ^ set(names)
assert by[first]["count"] == 3 and by[second]["count"] == 1 and by[third]["count"] == 0
assert "목록에 없는 매체" not in by
# 많은 순, 같으면 이름순
counts = [x["count"] for x in rows]
assert counts == sorted(counts, reverse=True)
assert rows[0]["outlet"] == first
# 홈페이지 링크(https)가 같이 내려옴
assert all((x["homepage"] is None) or x["homepage"].startswith("http") for x in rows)
assert by[first]["homepage"] == sources.OUTLET_HOMEPAGE.get(first)

# 캐시가 비어도 오류 없이 전부 0건
api._cache.clear()
assert all(x["count"] == 0 for x in client.get("/outlet-stats").json())

print("test_outlet_stats: ALL OK")
