# -*- coding: utf-8 -*-
"""개발/관리용 엔드포인트가 관리자 인증 없이는 못 쓰이는지 — `python3 test_admin_auth.py`.

2026-10-23: 인증 없이 열려 있던 /refresh, /digest/run, /admin/* 등을 막은 뒤의 회귀 테스트. api는 import 때 환경변수를
읽으므로 먼저 계정을 넣어둠. 진짜 갱신/발송/LLM 호출이 일어나지 않게 해당 함수는 가짜로 바꿈."""
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

calls = []


async def fake_refresh():
    calls.append("refresh")


api.refresh_cache = fake_refresh
api._digest_check = lambda force=False: calls.append("digest") or []
api._word_of_day_alert_check = lambda force=False: calls.append("wod") or []
api._run_cluster_audit = lambda: calls.append("audit") or 0

client = TestClient(api.app)
GOOD = {"Authorization": "Basic " + base64.b64encode(b"boss:s3cret-pw").decode()}
BAD = {"Authorization": "Basic " + base64.b64encode(b"boss:wrong").decode()}

PROTECTED = [
    ("post", "/refresh"),
    ("post", "/digest/run?force=true"),
    ("post", "/word-of-day/alert-run?force=true"),
    ("post", "/devices/1/keyword-alert/run"),
    ("post", "/issues/abc/summary"),
    ("post", "/admin/cluster-audit/run"),
    ("get", "/admin/cluster-audit/status"),
    ("get", "/admin/cluster-audit/findings"),
    ("put", "/admin/cluster-audit/findings/1"),
    ("get", "/feedback"),
]
for method, path in PROTECTED:
    kwargs = {"json": {"summary_text": "x"}} if path.endswith("/summary") else {}
    assert getattr(client, method)(path, **kwargs).status_code == 401, ("인증 없이 열림", method, path)
    assert getattr(client, method)(path, headers=BAD, **kwargs).status_code == 401, ("틀린 비밀번호로 열림", method, path)
assert calls == [], calls  # 거절된 요청은 아무 일도 일으키지 않음

# 맞는 계정이면 동작(가짜 함수라 실제 갱신/발송은 없음)
assert client.post("/refresh", headers=GOOD).status_code == 200
assert client.post("/digest/run?force=true", headers=GOOD).status_code == 200
assert client.post("/word-of-day/alert-run", headers=GOOD).status_code == 200
assert client.get("/admin/cluster-audit/status", headers=GOOD).status_code == 200
assert client.get("/feedback", headers=GOOD).status_code == 200
assert "refresh" in calls and "digest" in calls and "wod" in calls

# 앱이 쓰는 공개 엔드포인트는 그대로 열려 있음
for path in ("/health", "/trending", "/categories", "/stats"):
    assert client.get(path).status_code == 200, path

# 문서 페이지(전체 엔드포인트 목록)는 꺼져 있고, 문의를 웹페이지로 보여주던 /feedback/view도 없어짐(메일로 받음)
for path in ("/docs", "/redoc", "/openapi.json", "/feedback/view"):
    assert client.get(path).status_code == 404, path

# 문의 길이 제한
assert client.post("/feedback", json={"message": "가" * 5001}).status_code == 422
assert client.post("/feedback", json={"message": "안녕", "contact_email": "a" * 250 + "@b.co"}).status_code == 422
assert client.post("/feedback", json={"message": "가" * 5000}).status_code == 200

print("test_admin_auth: ALL OK")
