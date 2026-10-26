# -*- coding: utf-8 -*-
"""이미지 프록시 강화 — `python3 test_image_proxy.py` (출시 전 점검 IP-07). 실제 네트워크 없이 requests.get을 가짜로 바꿈."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient

import api

client = TestClient(api.app)


class FakeRes:
    def __init__(self, status=200, headers=None, body=b"", chunks=None):
        self.status_code = status
        self.headers = headers or {}
        self._body = body
        self._chunks = chunks
        self.closed = False

    def iter_content(self, chunk_size=0):
        if self._chunks is not None:
            yield from self._chunks
        else:
            yield self._body

    def close(self):
        self.closed = True


calls = []
plan = {}


def fake_get(url, **kw):
    calls.append((url, kw))
    assert kw.get("allow_redirects") is False and kw.get("stream") is True, kw
    res = plan[url]
    if isinstance(res, Exception):
        raise res
    return res


api.requests.get = fake_get
OK_URL = "https://img.yna.co.kr/a.jpg"

# 정상: 이미지가 그대로 나가고 캐시 헤더가 붙음
plan[OK_URL] = FakeRes(200, {"Content-Type": "image/jpeg"}, b"\xff\xd8jpegdata")
r = client.get("/image-proxy", params={"url": OK_URL})
assert r.status_code == 200 and r.content == b"\xff\xd8jpegdata" and r.headers["content-type"] == "image/jpeg"
assert "max-age=86400" in r.headers["cache-control"] and plan[OK_URL].closed

# 허용 도메인이 아니거나 http/https가 아니면 요청 자체를 안 함
before = len(calls)
assert client.get("/image-proxy", params={"url": "https://evil.example.com/a.jpg"}).status_code == 403
assert client.get("/image-proxy", params={"url": "file:///etc/passwd"}).status_code == 403
assert client.get("/image-proxy", params={"url": "https://yna.co.kr.evil.com/a.jpg"}).status_code == 403
assert len(calls) == before

# 리다이렉트: 허용 도메인 안에서는 따라가고(최대 2번), 밖으로 나가면 막음
HTTP_URL = "http://img.yna.co.kr/b.jpg"
HTTPS_URL = "https://img.yna.co.kr/b.jpg"
plan[HTTP_URL] = FakeRes(301, {"Location": HTTPS_URL})
plan[HTTPS_URL] = FakeRes(200, {"Content-Type": "image/png"}, b"png")
assert client.get("/image-proxy", params={"url": HTTP_URL}).content == b"png"

OUT_URL = "https://img.yna.co.kr/c.jpg"
plan[OUT_URL] = FakeRes(302, {"Location": "http://169.254.169.254/latest/meta-data"})
before = len(calls)
assert client.get("/image-proxy", params={"url": OUT_URL}).status_code == 403
assert len(calls) == before + 1  # 내부 주소로는 두 번째 요청을 안 보냄

LOOP_A, LOOP_B = "https://img.yna.co.kr/l1.jpg", "https://img.yna.co.kr/l2.jpg"
plan[LOOP_A] = FakeRes(302, {"Location": LOOP_B})
plan[LOOP_B] = FakeRes(302, {"Location": LOOP_A})
assert client.get("/image-proxy", params={"url": LOOP_A}).status_code == 502

# 이미지가 아니면 거절, 큰 이미지(선언된 크기/실제 크기)는 거절
plan[OK_URL] = FakeRes(200, {"Content-Type": "text/html"}, b"<html>")
assert client.get("/image-proxy", params={"url": OK_URL}).status_code == 415
plan[OK_URL] = FakeRes(200, {"Content-Type": "image/jpeg", "Content-Length": str(6 * 1024 * 1024)}, b"x")
assert client.get("/image-proxy", params={"url": OK_URL}).status_code == 413
plan[OK_URL] = FakeRes(200, {"Content-Type": "image/jpeg"}, chunks=[b"x" * (1024 * 1024)] * 6)  # 길이를 속여도 실제로 5MB를 넘으면 중단
assert client.get("/image-proxy", params={"url": OK_URL}).status_code == 413

# 실패 응답에 내부 예외 문구가 없음
plan[OK_URL] = RuntimeError("HTTPSConnectionPool(host='10.0.0.5', port=443): secret internal detail")
r = client.get("/image-proxy", params={"url": OK_URL})
assert r.status_code == 502 and "10.0.0.5" not in r.text and "secret" not in r.text, r.text
plan[OK_URL] = FakeRes(500, {})
assert client.get("/image-proxy", params={"url": OK_URL}).status_code == 502

# /health 공개 응답에 예외 문구가 없음
api._last_error = "OperationalError: database is locked (/home/ubuntu/backend/news_trend.db)"
h = client.get("/health").json()
assert h["last_error"] == "refresh_failed" and "locked" not in str(h) and "ubuntu" not in str(h), h
api._last_error = None
assert client.get("/health").json()["last_error"] is None

print("test_image_proxy: ALL OK")
