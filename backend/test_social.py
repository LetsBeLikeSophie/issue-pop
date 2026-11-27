# -*- coding: utf-8 -*-
"""SNS 자동 게시: 생성·승인·게시 순서, 재시도, 토큰 갱신, 공개 URL — `python3 test_social.py`.

실제 렌더링(폰트·ffmpeg 필요)은 SOCIAL_RENDER_TEST=1일 때만 함(서버에서 확인용).
게시 API는 requests를 가짜로 바꿔서 확인함 — 실제로는 아무것도 안 올라감."""
import os
import sys
import tempfile
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

tmpdir = tempfile.mkdtemp()
os.environ.update(
    SOCIAL_MEDIA_DIR=tmpdir,
    SOCIAL_SIGNING_SECRET="test-secret",
    SOCIAL_DRY_RUN="1",
    SOCIAL_REQUIRE_APPROVAL="1",
    SOCIAL_PUBLIC_BASE="https://api.example.test",
)
for k in ("SOCIAL_PREVIEW_MAIL_TO", "SOCIAL_TIMES", "SOCIAL_CHANNELS", "IG_ACCESS_TOKEN", "THREADS_ACCESS_TOKEN"):
    os.environ.pop(k, None)

import social  # noqa: E402
import social_card  # noqa: E402
import social_video  # noqa: E402

ISSUES = [
    {"keyword": f"키워드{i}", "keywords": [f"키워드{i}"], "category": "사회", "representative_title": f"제목 {i}",
     "outlet_count": 10 - i, "article_count": 30 - i, "articles": [{"title": "x"}]}
    for i in range(7)
]

if os.environ.get("SOCIAL_RENDER_TEST") == "1":
    # 서버(폰트·ffmpeg 있는 곳)에서 실제 렌더링 스모크 테스트
    png = social_card.render_card(ISSUES)
    assert png[:8] == b"\x89PNG\r\n\x1a\n" and len(png) > 10_000
    out = os.path.join(tmpdir, "smoke.mp4")
    social_video.render_video(ISSUES, out)
    assert os.path.getsize(out) > 50_000
    print("render smoke ok")

# 렌더러는 가짜로(로컬엔 서버 폰트가 없음)
render_calls = []
social_card.render_card = lambda issues, now=None, top_n=5: render_calls.append("card") or b"PNGDATA"


def fake_video(issues, out_path, now=None, top_n=5):
    render_calls.append("video")
    open(out_path, "wb").write(b"MP4DATA")
    return out_path


social_video.render_video = fake_video


def at(h, m, day=26):
    return datetime(2026, 11, day, h, m, tzinfo=social.KST)


get_issues = lambda: ISSUES  # noqa: E731

# 0) 기본 일정: 이슈팝은 Threads·피드 둘 다 08:00, Threads 글엔 플레이스토어 링크(눌림), 인스타 캡션은 프로필 링크 안내
d = social.times()
assert d["threads"] == d["ig_feed"] == (8, 0) and d["ig_reel"] == (12, 10)
assert social.PLAY_URL in social.threads_text(ISSUES) and len(social.threads_text(ISSUES)) <= 500
assert "프로필 링크" in social_card.caption(ISSUES)
# 아래 순서 확인은 채널마다 시각이 달라야 쉬워서 예전 일정으로 고정해서 봄
os.environ["SOCIAL_TIMES"] = "preview=07:00,threads=07:40,ig_feed=08:00,ig_reel=12:10"

# 1) 07:00 전에는 아무것도 안 함
assert social.tick(get_issues, at(6, 59)) == []
assert social.load_state("2026-11-26") is None

# 2) 07:00에 생성(TOP5만 저장), 메일 설정이 없으면 메일은 건너뜀
assert social.tick(get_issues, at(7, 0)) == ["generate"]
st = social.load_state("2026-11-26")
assert len(st["issues"]) == 5 and st["issues"][0]["keyword"] == "키워드0" and "articles" not in st["issues"][0]
assert st["preview_sent"] is True and st["approved"] is None
assert render_calls == ["card", "video"]
assert social.DIR_RE.match(st["dir"]) and st["dir"].startswith("2026-11-26-")
assert "TOP 5" in st["caption"] and len(st["threads_text"]) <= 500
# 다시 돌려도 다시 만들지 않음
assert social.tick(get_issues, at(7, 1)) == [] and render_calls == ["card", "video"]

# 3) 승인 전에는 게시 시각이 지나도 안 올라감
assert social.tick(get_issues, at(7, 41)) == []
assert social.load_state("2026-11-26")["posts"]["threads"]["status"] == "pending"

# 4) 서명: 맞는 sig만 통과
sig = social.sign("2026-11-26")
assert social.verify("2026-11-26", sig) and not social.verify("2026-11-26", "x" * 32)
assert not social.verify("2026-11-27", sig)

# 5) 승인 → 시각이 된 채널만 게시(dry-run)
social.decide("2026-11-26", True)
assert social.tick(get_issues, at(7, 41)) == ["threads"]
st = social.load_state("2026-11-26")
assert st["posts"]["threads"]["status"] == "posted" and st["posts"]["threads"]["id"] == "dry-run"
assert st["posts"]["ig_feed"]["status"] == "pending"
assert social.tick(get_issues, at(8, 0)) == ["ig_feed"]
assert social.tick(get_issues, at(8, 1)) == []

# 6) 너무 늦으면 건너뜀(기본 180분)
assert social.tick(get_issues, at(15, 11)) == []
assert social.load_state("2026-11-26")["posts"]["ig_reel"]["status"] == "skipped"

# 7) 반려한 날은 안 올라감 + 자동 게시 모드에서도 반려는 존중
os.environ["SOCIAL_REQUIRE_APPROVAL"] = "0"
social.tick(get_issues, at(7, 0, day=27))
social.decide("2026-11-27", False)
assert social.tick(get_issues, at(7, 41, day=27)) == []
# 자동 게시 모드에서 승인 안 해도 올라감
social.tick(get_issues, at(7, 0, day=28))
assert social.tick(get_issues, at(7, 41, day=28)) == ["threads"]
os.environ["SOCIAL_REQUIRE_APPROVAL"] = "1"

# 8) 서버가 하루 종일 꺼져 있다 저녁에 켜지면 그날은 만들지도 않음
assert social.tick(get_issues, at(20, 0, day=29)) == []
assert social.load_state("2026-11-29") is None

# 9) 미디어 파일: 허용된 것만, 경로 조작 불가
assert social.media_file(st["dir"], "card.png") is not None
assert social.media_file(st["dir"], "state.json") is None
assert social.media_file("../etc", "card.png") is None
assert social.media_url(st, "reel.mp4") == f"https://api.example.test/social/media/{st['dir']}/reel.mp4"


# 10) 실제 게시 흐름(가짜 requests): 컨테이너 → 상태 확인 → 게시
class Resp:
    def __init__(self, data, code=200):
        self._d, self.status_code, self.text = data, code, str(data)

    def json(self):
        return self._d

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(self.status_code)


calls = []


def fake_post(url, data=None, timeout=None):
    calls.append(("POST", url, dict(data)))
    if url.endswith("/media") or url.endswith("/threads"):
        return Resp({"id": "C1"})
    return Resp({"id": "P1"})


statuses = iter(["IN_PROGRESS", "FINISHED"])


def fake_get(url, params=None, timeout=None):
    calls.append(("GET", url, dict(params)))
    if "refresh_access_token" in url:
        return Resp({"access_token": "NEW-" + params["access_token"]})
    return Resp({"status_code": next(statuses, "FINISHED"), "status": "FINISHED"})


social.requests.post, social.requests.get = fake_post, fake_get
os.environ.update(IG_USER_ID="111", IG_ACCESS_TOKEN="IGTOKEN", THREADS_USER_ID="222", THREADS_ACCESS_TOKEN="THTOKEN")

pid = social.publish_instagram("reel", "https://x/reel.mp4", "캡션", sleep=lambda s: None)
assert pid == "P1"
assert calls[0][1].endswith("/111/media") and calls[0][2]["media_type"] == "REELS"
assert calls[0][2]["video_url"] == "https://x/reel.mp4" and calls[0][2]["access_token"] == "IGTOKEN"
assert [c[0] for c in calls] == ["POST", "GET", "GET", "POST"]
assert calls[-1][1].endswith("/111/media_publish") and calls[-1][2]["creation_id"] == "C1"
assert calls[0][1].startswith("https://graph.instagram.com/")

# 통합 로그인 시스템 사용자 토큰(EAA…)은 graph.facebook.com으로
calls.clear()
statuses = iter(["FINISHED"])
os.environ["IG_ACCESS_TOKEN"] = "EAATOKEN"
assert social.publish_instagram("image", "https://x/card.png", "캡션", sleep=lambda s: None) == "P1"
assert all(c[1].startswith("https://graph.facebook.com/v23.0/") for c in calls)
assert calls[0][2]["image_url"] == "https://x/card.png"
os.environ["IG_ACCESS_TOKEN"] = "IGTOKEN"

calls.clear()
assert social.publish_threads("https://x/card.png", "글", sleep=lambda s: None) == "P1"
assert calls[0][1] == "https://graph.threads.net/v1.0/222/threads" and calls[0][2]["media_type"] == "IMAGE"
assert calls[-1][1].endswith("/222/threads_publish")

# 11) 실패하면 3번까지 다시 시도 후 failed
os.environ["SOCIAL_DRY_RUN"] = "0"
social.requests.post = lambda url, data=None, timeout=None: Resp({"error": "bad"}, 400)
social.tick(get_issues, at(7, 0, day=30))
social.decide("2026-11-30", True)
for m in (41, 42, 43, 44):
    social.tick(get_issues, at(7, m, day=30))
p = social.load_state("2026-11-30")["posts"]["threads"]
assert p["status"] == "failed" and p["attempts"] == 3 and "HTTP 400" in p["error"]

# 12) 토큰: 처음엔 기록만, 45일 지나면 갱신하고 이후 그 토큰을 씀. 환경변수를 새 토큰으로 바꾸면 그게 우선
t0 = 1_800_000_000
calls.clear()
assert social.refresh_tokens_if_due(now=t0) == [] and calls == []
assert social.get_token("ig") == "IGTOKEN"
assert sorted(social.refresh_tokens_if_due(now=t0 + 46 * 86400)) == ["ig", "threads"]
assert social.get_token("ig") == "NEW-IGTOKEN" and social.get_token("threads") == "NEW-THTOKEN"
os.environ["IG_ACCESS_TOKEN"] = "IGTOKEN2"
assert social.get_token("ig") == "IGTOKEN2"
# EAA 토큰은 만료가 없으니 아무리 지나도 갱신 요청을 보내지 않음
os.environ["IG_ACCESS_TOKEN"] = "EAATOKEN"
calls.clear()
assert "ig" not in social.refresh_tokens_if_due(now=t0 + 400 * 86400)
assert not any("graph.instagram.com/refresh" in c[1] for c in calls)
assert social.get_token("ig") == "EAATOKEN"
os.environ["SOCIAL_DRY_RUN"] = "1"

# 13) API: 미디어 공개, 확인 페이지는 sig 필요, 승인은 POST로만
from fastapi.testclient import TestClient  # noqa: E402

import api  # noqa: E402

client = TestClient(api.app)
d = social.load_state("2026-11-26")["dir"]
r = client.get(f"/social/media/{d}/card.png")
assert r.status_code == 200 and r.content == b"PNGDATA" and r.headers["content-type"] == "image/png"
assert client.get(f"/social/media/{d}/state.json").status_code == 404
assert client.get("/social/review/2026-11-27?sig=bad").status_code == 404
sig27 = social.sign("2026-11-27")
r = client.get(f"/social/review/2026-11-27?sig={sig27}")
assert r.status_code == 200 and "반려됨" in r.text and social.load_state("2026-11-27")["approved"] is False
social.tick(get_issues, at(7, 0, day=25))
sig25 = social.sign("2026-11-25")
r = client.get(f"/social/review/2026-11-25?sig={sig25}")
assert "승인" in r.text and social.load_state("2026-11-25")["approved"] is None  # GET으로는 안 바뀜
assert client.post(f"/social/review/2026-11-25?sig=bad&action=approve").status_code == 404
r = client.post(f"/social/review/2026-11-25?sig={sig25}&action=approve", follow_redirects=False)
assert r.status_code == 303 and social.load_state("2026-11-25")["approved"] is True

print("ok")
