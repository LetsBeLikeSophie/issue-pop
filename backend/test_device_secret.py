# -*- coding: utf-8 -*-
"""기기 비밀값(번호만으로 남의 설정을 못 보게) + 문의 메일 테스트 — `python3 test_device_secret.py`."""
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
db.init_db()


async def _no_warm(ticker):
    return None


api._warm_ticker = _no_warm
client = TestClient(api.app)


def H(secret):
    return {"X-Device-Secret": secret} if secret else {}


# 1) 옛 앱: claim 없이 등록 → 비밀값 없음, 번호만으로 열림(예전과 같음)
legacy = client.post("/devices", json={"push_token": "legacy-token"}).json()
assert "device_secret" not in legacy
lid = legacy["device_id"]
assert client.get(f"/devices/{lid}/digest").status_code == 200
assert client.put(f"/devices/{lid}/digest", json={"hour": 8, "minute": 0}).status_code == 200

# 2) 새 앱: claim=true로 새 기기 등록 → 비밀값 받음, 번호만으로는 403
new = client.post("/devices", json={"push_token": "new-token", "claim": True}).json()
nid, nsec = new["device_id"], new["device_secret"]
assert len(nsec) >= 32
assert client.get(f"/devices/{nid}/digest").status_code == 403
assert client.get(f"/devices/{nid}/digest", headers=H("wrong")).status_code == 403
assert client.get(f"/devices/{nid}/digest", headers=H(nsec)).status_code == 200
with db.get_session() as s:
    assert nsec not in (s.get(db.Device, nid).secret_hash or "")  # 해시만 저장

# 3) 보호되는 엔드포인트 전부(번호만으론 403, 맞는 비밀값이면 통과)
guarded = [
    ("get", f"/devices/{nid}/digest", None),
    ("put", f"/devices/{nid}/digest", {"hour": 9, "minute": 5}),
    ("get", f"/devices/{nid}/keyword-alert", None),
    ("put", f"/devices/{nid}/keyword-alert", {"enabled": True, "quiet_start": 23, "quiet_end": 7}),
    ("get", f"/devices/{nid}/word-of-day-alert", None),
    ("put", f"/devices/{nid}/word-of-day-alert", {"enabled": True, "hour": 9, "minute": 0}),
    ("get", f"/devices/{nid}/stocks", None),
    ("get", f"/watches/{nid}", None),
    ("post", "/watches", {"device_id": nid, "keyword": "추미애"}),
    ("post", "/stocks", {"device_id": nid, "ticker": "AAPL"}),
    ("put", f"/devices/{nid}/push-token", {"push_token": "new-token-2"}),
]
for method, path, body in guarded:
    kw = {"json": body} if body is not None else {}
    assert getattr(client, method)(path, **kw).status_code == 403, ("번호만으로 열림", method, path)
    assert getattr(client, method)(path, headers=H("wrong"), **kw).status_code == 403, ("틀린 비밀값으로 열림", method, path)
    r = getattr(client, method)(path, headers=H(nsec), **kw)
    assert r.status_code == 200, (method, path, r.status_code, r.text)

# 4) 다른 기기의 비밀값으로는 안 열림
other = client.post("/devices", json={"push_token": "other-token", "claim": True}).json()
assert client.get(f"/devices/{nid}/digest", headers=H(other["device_secret"])).status_code == 403

# 5) 관심 키워드/종목 삭제도 비밀값이 맞아야 함
wid = client.post("/watches", json={"device_id": nid, "keyword": "삭제테스트"}, headers=H(nsec)).json()["id"]
assert client.delete(f"/watches/{wid}").status_code == 403
assert client.delete(f"/watches/{wid}", headers=H(other["device_secret"])).status_code == 403
assert any(w["id"] == wid for w in client.get(f"/watches/{nid}", headers=H(nsec)).json())  # 안 지워짐
assert client.delete(f"/watches/{wid}", headers=H(nsec)).status_code == 200
assert not any(w["id"] == wid for w in client.get(f"/watches/{nid}", headers=H(nsec)).json())
stocks = client.get(f"/devices/{nid}/stocks", headers=H(nsec)).json()
sid = stocks[0]["id"]
assert client.delete(f"/stocks/{sid}").status_code == 403
assert client.delete(f"/stocks/{sid}", headers=H(nsec)).status_code == 200

# 6) 옛 기기를 새 앱이 넘겨받기(같은 push_token을 아는 쪽만) → 그때부터 잠김, 번호는 그대로
claimed = client.post("/devices", json={"push_token": "legacy-token", "claim": True}).json()
assert claimed["device_id"] == lid and "device_secret" in claimed
assert client.get(f"/devices/{lid}/digest").status_code == 403
assert client.get(f"/devices/{lid}/digest", headers=H(claimed["device_secret"])).status_code == 200
assert client.get("/devices/9999/digest").status_code == 404  # 없는 번호는 그대로 404

# 7) 옛 앱이 같은 토큰으로 다시 등록해도(claim 없음) 비밀값이 바뀌거나 잠기지 않음
again = client.post("/devices", json={"push_token": "legacy-token"}).json()
assert again == {"device_id": lid}
assert client.get(f"/devices/{lid}/digest", headers=H(claimed["device_secret"])).status_code == 200

# 8) 다시 claim하면 새 비밀값이 나오고 이전 것은 무효(비밀값을 잃어버린 앱의 복구 경로)
rot = client.post("/devices", json={"push_token": "legacy-token", "claim": True}).json()
assert rot["device_secret"] != claimed["device_secret"]
assert client.get(f"/devices/{lid}/digest", headers=H(claimed["device_secret"])).status_code == 403
assert client.get(f"/devices/{lid}/digest", headers=H(rot["device_secret"])).status_code == 200

# 9) 문의 메일: 설정이 없으면 건너뜀, 있으면 제목 줄바꿈 제거 + Reply-To + 받는 곳 기본값
import smtplib

sent = []


class FakeSMTP:
    def __init__(self, host, port, timeout=0):
        sent.append(("connect", host, port))

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def starttls(self):
        sent.append(("tls",))

    def login(self, user, password):
        sent.append(("login", user))

    def send_message(self, msg):
        sent.append(("msg", msg))


smtplib.SMTP = FakeSMTP
for k in ("FEEDBACK_SMTP_USER", "FEEDBACK_SMTP_PASSWORD", "FEEDBACK_MAIL_TO", "FEEDBACK_SMTP_HOST"):
    os.environ.pop(k, None)
api._send_feedback_email(1, "메일 설정 없음", None, None)
assert sent == []

os.environ["FEEDBACK_SMTP_USER"] = "sender@example.com"
os.environ["FEEDBACK_SMTP_PASSWORD"] = "app-password"
r = client.post("/feedback", json={"message": "첫 줄\nBcc: evil@x.com\n둘째 줄", "contact_email": "user@example.com", "device_id": nid})
assert r.status_code == 200
kinds = [x[0] for x in sent]
assert kinds == ["connect", "tls", "login", "msg"], kinds
msg = sent[-1][1]
assert msg["To"] == "contact@issue-pop.com" and msg["Reply-To"] == "user@example.com" and msg["From"] == "sender@example.com"
assert "\n" not in msg["Subject"] and msg["Bcc"] is None
assert "Bcc: evil@x.com" in msg.get_content()  # 본문에는 그대로, 헤더로는 안 새어나감

# 메일 서버가 죽어도 문의 접수는 성공(DB에 저장)
class BrokenSMTP(FakeSMTP):
    def starttls(self):
        raise OSError("down")


smtplib.SMTP = BrokenSMTP
assert client.post("/feedback", json={"message": "서버 죽음"}).status_code == 200

print("test_device_secret: ALL OK")
