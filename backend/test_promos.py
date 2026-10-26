# -*- coding: utf-8 -*-
"""웹 양옆 홍보 카드(/promos) — `python3 test_promos.py`. 파일을 읽어 내려주되 잘못된 내용에도 안 깨지는지."""
import json
import os
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient

import api

client = TestClient(api.app)


def write(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content if isinstance(content, str) else json.dumps(content, ensure_ascii=False))
    # 같은 초 안에 바꿔도 변경으로 인식되게 수정 시각을 확실히 앞으로 보냄
    t = time.time() + write.counter
    write.counter += 2
    os.utime(path, (t, t))


write.counter = 1

# 1) 저장소에 들어 있는 기본 파일: 앱 안내(준비 중) 카드 + Buy Me a Coffee(임베드)
api.PROMOS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "promos.json")
api._promo_cache.update(mtime=None, items=None)
r = client.get("/promos")
assert r.status_code == 200 and "max-age=300" in r.headers["cache-control"]
cards = r.json()
by_id = {c["id"]: c for c in cards}
assert set(by_id) == {"app", "coffee"}
coffee = by_id["coffee"]
assert coffee["title"] == "Buy Me a Coffee" and coffee["url"] == "https://buymeacoffee.com/itssophie"
assert coffee["side"] == "right" and coffee["highlight"] is True
assert coffee["embed"].startswith("https://buymeacoffee.com/widget/page/") and coffee["embed_height"] == 300
# 앱 받기는 스토어 출시 전이라 링크·버튼 없는 "준비 중" 안내 카드
assert by_id["app"]["side"] == "left" and by_id["app"]["url"] == "" and by_id["app"]["button"] == ""

tmp = tempfile.mkdtemp()
path = os.path.join(tmp, "promos.json")
api.PROMOS_FILE = path

# 2) 파일이 없으면 기본값
assert client.get("/promos").json()[0]["title"] == "Buy Me a Coffee"

# 3) 내 앱 카드를 추가하면 그대로 나오고, 바꾸면 다음 요청에 반영됨(서버 재시작 불필요)
write(path, [
    {"id": "coffee", "side": "right", "title": "Buy Me a Coffee", "button": "후원", "url": "https://buymeacoffee.com/itssophie"},
    {"id": "dailycut", "side": "left", "title": "데일리컷", "body": "공공데이터를 매일 한 장으로", "button": "받기", "url": "https://play.google.com/store/apps/details?id=x"},
])
cards = client.get("/promos").json()
assert [c["id"] for c in cards] == ["coffee", "dailycut"] and cards[1]["side"] == "left" and cards[0]["body"] == ""
write(path, [{"title": "새 앱", "button": "열기", "url": "https://example.com/app"}])
cards = client.get("/promos").json()
assert len(cards) == 1 and cards[0]["title"] == "새 앱" and cards[0]["side"] == "right" and cards[0]["id"] == "새 앱"

# 4) 못 쓰는 항목은 건너뜀: http 링크, 필수 값 없음, 이상한 타입, 너무 긴 글은 잘라냄, 최대 8장
write(path, [
    {"title": "http 링크", "button": "x", "url": "http://insecure.example.com"},
    {"title": "javascript", "button": "x", "url": "javascript:alert(1)"},
    {"title": "", "button": "x", "url": "https://ok.example.com"},
    {"button": "x", "url": "https://ok.example.com"},
    "문자열", 42, None,
    {"title": "가" * 100, "body": "나" * 500, "button": "다" * 50, "url": "https://ok.example.com/" + "a" * 100},
] + [{"title": f"앱{i}", "button": "b", "url": "https://ok.example.com"} for i in range(20)])
cards = client.get("/promos").json()
assert len(cards) == 8
assert len(cards[0]["title"]) == 40 and len(cards[0]["body"]) == 140 and len(cards[0]["button"]) == 20
assert all(c["url"].startswith("https://") for c in cards)

# 4-1) 버튼·링크는 짝(하나만 있으면 안내 카드), image/embed는 https만, 높이는 100~700으로 제한
write(path, [
    {"title": "안내만", "body": "준비 중", "button": "버튼만 있음"},
    {"title": "링크만", "url": "https://ok.example.com"},
    {"title": "QR", "image": "https://api.issue-pop.com/downloads/qr-store.png", "button": "받기", "url": "https://play.google.com/x"},
    {"title": "http 이미지", "image": "http://insecure.example.com/a.png"},
    {"title": "http 임베드", "embed": "http://insecure.example.com/w"},
    {"title": "너무 큰 임베드", "embed": "https://ok.example.com/w", "embed_height": 99999},
    {"title": "작은 임베드", "embed": "https://ok.example.com/w", "embed_height": 5},
    {"title": "이상한 높이", "embed": "https://ok.example.com/w", "embed_height": "큼"},
])
cards = {c["title"]: c for c in client.get("/promos").json()}
assert set(cards) == {"안내만", "링크만", "QR", "너무 큰 임베드", "작은 임베드", "이상한 높이"}, set(cards)
assert cards["안내만"]["button"] == "" and cards["안내만"]["url"] == ""
assert cards["링크만"]["button"] == "" and cards["링크만"]["url"] == ""
assert cards["QR"]["image"].endswith("qr-store.png") and cards["QR"]["url"].startswith("https://play.google.com")
assert cards["너무 큰 임베드"]["embed_height"] == 700 and cards["작은 임베드"]["embed_height"] == 100 and cards["이상한 높이"]["embed_height"] == 300

# 5) 파일이 깨졌거나 목록이 아니면 기본값으로 되돌아감(앱이 깨지지 않음)
write(path, "{ 이건 JSON이 아님")
assert client.get("/promos").json()[0]["title"] == "Buy Me a Coffee"
write(path, {"title": "객체지 목록이 아님"})
assert client.get("/promos").json()[0]["title"] == "Buy Me a Coffee"

# 6) 인증 없이 열려 있는 공개 엔드포인트(앱이 로그인 없이 부름)
assert client.get("/promos").status_code == 200

print("test_promos: ALL OK")
