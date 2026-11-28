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
    SOCIAL_DEVLOG="0",  # 개발 일지는 맨 아래 14)에서 따로 켜서 확인
    SOCIAL_PROMO="0",  # Ripe Weekly 홍보는 맨 아래 15)에서 따로 켜서 확인
)
for k in ("SOCIAL_PREVIEW_MAIL_TO", "SOCIAL_TIMES", "SOCIAL_CHANNELS", "IG_ACCESS_TOKEN", "THREADS_ACCESS_TOKEN",
          "SOCIAL_EPISODE_WEEKDAY", "ANTHROPIC_KEY_SOCIAL", "ANTHROPIC_API_KEY"):
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

# 스토리(9:16)는 카드를 가운데에 — 실제로 그려 봄(폰트는 아래 글씨에만 필요해서 가짜 폰트 로더로)
import io  # noqa: E402

from PIL import Image as _Img  # noqa: E402

_buf = io.BytesIO()
_Img.new("RGB", (1080, 1350), (250, 250, 247)).save(_buf, "PNG")
_real_font = social_card._font
social_card._font = lambda weight, size: social_card.ImageFont.load_default()
story = _Img.open(io.BytesIO(social_card.render_story(_buf.getvalue())))
assert story.size == (1080, 1920) and story.getpixel((540, 960)) == (250, 250, 247)
assert story.getpixel((540, 20)) == social_card.NAVY
social_card._font = _real_font

# 렌더러는 가짜로(로컬엔 서버 폰트가 없음)
render_calls = []
social_card.render_card = lambda issues, now=None, top_n=5: render_calls.append("card") or b"PNGDATA"
social_card.render_story = lambda card: render_calls.append("story") or b"STORY"


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
assert d["threads"] == d["ig_feed"] == d["ig_story"] == (8, 0) and d["ig_reel"] == (12, 10)
assert social.PLAY_URL in social.threads_text(ISSUES) and len(social.threads_text(ISSUES)) <= 500
assert "프로필 링크" in social_card.caption(ISSUES)
# 기본 채널: 이슈팝은 인스타 피드 + 스토리만(Threads·릴스 꺼짐, 영상도 안 만듦). Threads는 게임 일지·앱 에피소드
assert "ig_story" in social.channels() and "ig_reel" not in social.channels() and "threads" not in social.channels()
assert "devlog_threads" in social.channels() and "episode_threads" in social.channels()
social.tick(get_issues, at(7, 0, day=20))
s20 = social.load_state("2026-11-20")
assert set(s20["posts"]) == {"ig_feed", "ig_story"} and render_calls == ["card", "story"]
assert social.media_file(s20["dir"], "story.png") is not None
social.decide("2026-11-20", True)
assert sorted(social.tick(get_issues, at(8, 0, day=20))) == ["ig_feed", "ig_story"]
render_calls.clear()
# 아래 순서 확인은 채널마다 시각이 달라야 쉬워서 예전 일정(+릴스 켬)으로 고정해서 봄
os.environ["SOCIAL_TIMES"] = "preview=07:00,threads=07:40,ig_feed=08:00,ig_reel=12:10"
os.environ["SOCIAL_CHANNELS"] = "threads,ig_feed,ig_reel"

# 1) 07:00 전에는 아무것도 안 함
assert social.tick(get_issues, at(6, 59)) == []
assert social.load_state("2026-11-26") is None

# 2) 07:00에 생성(TOP5만 저장), 메일 설정이 없으면 메일은 건너뜀
assert social.tick(get_issues, at(7, 0)) == ["generate"]
st = social.load_state("2026-11-26")
assert len(st["issues"]) == 5 and st["issues"][0]["keyword"] == "키워드0" and "articles" not in st["issues"][0]
assert st["preview_sent"] is True and st["approved"] is None
assert render_calls == ["card", "story", "video"]
assert social.DIR_RE.match(st["dir"]) and st["dir"].startswith("2026-11-26-")
assert "TOP 5" in st["caption"] and len(st["threads_text"]) <= 500
# 다시 돌려도 다시 만들지 않음
assert social.tick(get_issues, at(7, 1)) == [] and render_calls == ["card", "story", "video"]

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
assert "topic_tag" not in calls[0][2]
calls.clear()
assert social.publish_threads(None, "글", sleep=lambda s: None, topic="창업") == "P1"
assert calls[0][2]["topic_tag"] == "창업"
assert social.THREADS_TOPICS["promo_en_threads"] == "automation" and social.THREADS_TOPICS["devlog_threads"] == "게임개발"

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
# 메일의 [승인]으로 열면: 큰 버튼 하나("이대로 올리기")만 보이고, 여는 것만으로는 안 바뀜
r = client.get(f"/social/review/2026-11-25?sig={sig25}&do=approve")
assert "이대로 올리기" in r.text and "action=approve" in r.text and social.load_state("2026-11-25")["approved"] is None
r = client.get(f"/social/review/2026-11-25?sig={sig25}&do=reject")
assert "이번엔 안 올리기" in r.text and social.load_state("2026-11-25")["approved"] is None
assert client.post(f"/social/review/2026-11-25?sig=bad&action=approve").status_code == 404
r = client.post(f"/social/review/2026-11-25?sig={sig25}&action=approve", follow_redirects=False)
assert r.status_code == 303 and social.load_state("2026-11-25")["approved"] is True

# 14) 만드는 과정 공개: GitHub 커밋 → Threads 게임 개발 일지 / 주간 앱 에피소드
import devlog  # noqa: E402
import devlog_card  # noqa: E402

# 가리기: 키·메일·주소·링크는 글에 안 나감
red = devlog.redact("키 sk-ant-abc123def456ghi 메일 me@x.com 서버 203.0.113.7 https://x.y/z?t=1 "
                    "토큰 EAAQlKabcdefgh 해시 " + "a" * 40)
assert "sk-ant" not in red and "me@x.com" not in red and "203.0.113" not in red and "https://" not in red
assert "EAAQ" not in red and "a" * 40 not in red
assert devlog._clean_message("고침\n\nCo-Authored-By: Claude <noreply@anthropic.com>") == "고침"

def c(repo, msg, created="2026-10-01T00:00:00Z", date="2026-11-26T10:00:00Z"):
    return {"repo": repo, "sha": "x", "date": date, "created": created, "message": msg}


COMMITS = [c("Appjupjup", "홈: 티켓 칩 하나로"), c("Appjupjup", "캡처는 하루 1장씩"),
           c("issue-pop", "SNS 자동 게시"), c("SubwayRush", "환승역 맵 추가")]
groups = devlog.group_by_project(COMMITS)
assert [(g["name"], g["count"]) for g in groups] == [("앱줍줍", 2), ("이슈팝", 1), ("지옥철", 1)]
assert [g["game"] for g in groups] == [False, False, True]
assert groups[0]["color"] == (242, 106, 27)  # 앱줍줍 주황(앱 코드의 --primary)
os.environ["SOCIAL_GAME_REPOS"] = "Durango-Like"  # 새 게임 저장소는 환경변수로 바로 추가
assert devlog.app_info("durango-like")["game"] is True
os.environ.pop("SOCIAL_GAME_REPOS")

# 캡처 목록: social/YYYY-MM-DD-*.png|jpg만, 날짜순
CAPS = [{"name": "2026-11-27-home.jpg", "type": "file", "path": "social/2026-11-27-home.jpg"},
        {"name": "2026-11-20-old.png", "type": "file", "path": "social/2026-11-20-old.png"},
        {"name": "2026-11-25-ticket.png", "type": "file", "path": "social/2026-11-25-ticket.png"},
        {"name": "notes.md", "type": "file", "path": "social/notes.md"}]
devlog._get = lambda url, params=None: CAPS
assert [d for d, _ in devlog.list_captures("x")] == ["2026-11-20", "2026-11-25", "2026-11-27"]
assert devlog.week_capture("Appjupjup", at(20, 0, day=22), at(20, 0, day=29)) == "social/2026-11-27-home.jpg"
assert devlog.week_capture("Appjupjup", at(20, 0, day=28), at(20, 0, day=29)) is None
assert devlog.fetch_image("x", None) is None

# 게임 개발 일지: 그 기간 새 캡처가 있는 게임만(화면 위주), 전 = 바로 앞 캡처
v = devlog.game_visual(groups, at(20, 0, day=26), at(20, 0, day=27), at(20, 0, day=27))
assert v["name"] == "지옥철" and v["after"] == "social/2026-11-27-home.jpg"
assert v["before"] == "social/2026-11-25-ticket.png" and "#" not in v["text"]  # 해시태그 대신 주제 태그
assert devlog.game_visual(groups, at(20, 0, day=28), at(20, 0, day=29), at(20, 0, day=29)) is None  # 새 화면 없음
assert devlog.game_visual(groups[:2], at(20, 0, day=26), at(20, 0, day=27), at(20, 0, day=27)) is None  # 게임 없음

# 에피소드 소재 고르기
start = at(20, 0, day=22)
assert devlog.choose_angle(groups, start, [])[0] == "story"
assert devlog.choose_angle(groups, start, [])[1]["name"] == "앱줍줍"  # 만든 이유가 적힌 앱 우선
new_app = devlog.group_by_project(COMMITS + [c("cortex", "첫 화면", created="2026-11-24T00:00:00Z")])
assert devlog.choose_angle(new_app, start, []) == ("new", next(g for g in new_app if g["repo"] == "cortex"))
many = devlog.group_by_project(COMMITS * 6)  # 커밋 24개
assert devlog.choose_angle(many, start, [{"angle": "story", "repo": "Appjupjup"}])[0] == "vibe"
assert devlog.choose_angle(many, start, [{"angle": "vibe", "repo": ""}])[0] == "story"
only_ip = devlog.group_by_project([c("issue-pop", "고침")])
ang, g = devlog.choose_angle(only_ip, start, [])
assert ang == "story" and g["name"] == "앱줍줍" and g["count"] == 0  # 이번 주 커밋 없어도 이야기 가능
ang, g = devlog.choose_angle(only_ip, start, [{"angle": "story", "repo": "appjupjup"}])
assert ang == "story" and g["name"] == "이슈팝"

# 에피소드 글(한 장용, 짧게): Claude 없이 기본 글
end = at(20, 0, day=29)
ep = devlog.weekly_episode(groups, start, end)
assert ep["angle"] == "story" and ep["name"] == "앱줍줍" and ep["line1"] and ep["line2"]
assert ep["color"] == (242, 106, 27) and "프로필 링크" in ep["caption"] and len(ep["threads"]) <= 400
assert "👾" in ep["threads"] and "💜" in ep["threads"] and "만들구 이쏘" in ep["threads"]  # 기본 글도 소피 말투
# 쪼개 쓰기(ㄴ ㅏ)는 섞어서: 같은 seed면 늘 같고, 여러 글 중 일부만
mixed = [devlog.mix_jamo("그래서 ㄴ ㅏ 만들구 이쏘 했ㅈ ㅣ렁", str(i)) for i in range(20)]
assert any("ㄴ ㅏ" in m for m in mixed) and "그래서 만들구 이쏘 했지렁" in mixed
assert devlog.mix_jamo("ㄴ ㅏ", "x") == devlog.mix_jamo("ㄴ ㅏ", "x")
vibe = devlog.weekly_episode(many, start, end, [{"angle": "story", "repo": "appjupjup"}])
assert vibe["angle"] == "vibe" and vibe["number"] == 24 and vibe["repo"] == "" and vibe["line1"]
newep = devlog.weekly_episode(new_app, start, end)
assert newep["angle"] == "new" and newep["name"] == "Cortex" and newep["lines"] and "11월 29일" in newep["date_label"]

# Claude 답(JSON)이 오면 그걸 쓰되, 길이 자르고 민감한 건 가림
devlog._ask = lambda prompt: {"line1": "앱 홍보 사이트, 많죠.", "line2": "근데 이건 홍보가 아니에요.",
                              "caption": "캡션 me@x.com", "threads": "스레드 글"}
ep = devlog.weekly_episode(groups, start, end)
assert ep["line1"] == "앱 홍보 사이트, 많죠." and ep["line2"] == "근데 이건 홍보가 아니에요."
assert "me@x.com" not in ep["caption"] and ep["threads"] == "스레드 글"
devlog._ask = lambda prompt: {"lines": ["앱이 계속 생기는데", "써 줄 사람이 없었다.", "그래서", "만들었다.", "다섯째"]}
assert devlog.weekly_episode(new_app, start, end)["lines"] == ["앱이 계속 생기는데", "써 줄 사람이 없었다.", "그래서", "만들었다."]
devlog._ask = lambda prompt: None

# 실제 렌더: 소재마다 한 장, 앱 색 배경(A), 아이콘 색 뽑기, 게임 전→후
from PIL import Image  # noqa: E402

pic = Image.new("RGB", (1600, 900), (10, 20, 30))
for e_ in (ep, vibe, newep):
    for imgs in ({}, {"icon": pic}):
        pngs = devlog_card.render_episode(e_, imgs)
        assert len(pngs) == 1 and pngs[0][:8] == b"\x89PNG\r\n\x1a\n"
a = Image.open(io.BytesIO(devlog_card.render_episode(ep)[0]))
assert a.size == (1080, 1350) and a.getpixel((20, 20)) == (242, 106, 27)
icon = Image.new("RGB", (512, 512), (255, 255, 255))
icon.paste((40, 160, 70), (100, 100, 400, 400))
col = devlog_card.theme_color(None, icon)
assert col[1] > col[0] and col[1] > col[2]  # 아이콘의 초록을 뽑음(흰색은 무시)
assert devlog_card.theme_color(None, None) == devlog_card.LAVENDER_INK
for before in (None, pic):
    g_png = devlog_card.render_game({"name": "지옥철"}, before, pic)
    assert Image.open(io.BytesIO(g_png)).size == (1080, 1350)

# 루프: 20:00 생성(목요일=게임 개발 일지, 새 화면 있음) → 승인 → 21:00 Threads(이미지 + 짧은 글)
os.environ["SOCIAL_DEVLOG"] = "1"
os.environ.pop("SOCIAL_CHANNELS", None)  # 기본 채널(개발 일지 포함)
os.environ["SOCIAL_TIMES"] = ""  # 기본 일정
CAPS[0] = {"name": "2026-11-26-home.jpg", "type": "file", "path": "social/2026-11-26-home.jpg"}
fetched = []
devlog.fetch_commits = lambda since, until: fetched.append((since, until)) or COMMITS
rendered = []
devlog_card.render_episode = lambda ep, images=None: rendered.append((ep, images)) or [b"PNG1"]
devlog_card.render_game = lambda info, before, after: rendered.append(("game", before, after)) or b"GAME"
devlog.fetch_image = lambda repo, path: f"IMG:{repo}:{path}" if path else None
assert at(20, 0).weekday() == 3
assert "devlog_generate" not in social.tick(get_issues, at(19, 59))
assert "devlog_generate" in social.tick(get_issues, at(20, 0))
dl = social.load_state("devlog-2026-11-26")
assert dl["slides"] == 1 and list(dl["posts"]) == ["devlog_threads"] and dl["weekly"] is False
assert rendered[-1] == ("game", "IMG:SubwayRush:social/2026-11-25-ticket.png", "IMG:SubwayRush:social/2026-11-26-home.jpg")
assert social.media_file(dl["dir"], "slide1.png").read_bytes() == b"GAME"
assert fetched[-1][1] - fetched[-1][0] == social.timedelta(days=1)
assert social.load_state("2026-11-26")["kind"] == "issuepop"  # 같은 날 이슈팝 상태와 섞이지 않음
assert social.tick(get_issues, at(21, 0)) == []  # 승인 전
social.decide("devlog-2026-11-26", True)
assert social.tick(get_issues, at(21, 0)) == ["devlog_threads"]

# 게임 화면이 안 바뀐 날(새 캡처 없음): 커밋이 있어도 안 올림, 메일도 안 보냄
social.tick(get_issues, at(20, 0, day=27))
e = social.load_state("devlog-2026-11-27")
assert e["empty"] is True and e["posts"] == {} and e["preview_sent"] is True
social.decide("devlog-2026-11-27", True)
assert social.tick(get_issues, at(21, 0, day=27)) == []

# 일요일: 지난 7일 → 앱 에피소드 한 장 → 인스타 피드(이미지) + Threads
social.tick(get_issues, at(20, 0, day=29))
w = social.load_state("devlog-2026-11-29")
assert w["weekly"] and w["slides"] == 1 and set(w["posts"]) == {"episode_ig", "episode_threads"}
ep_r, imgs = rendered[-1]
assert ep_r["angle"] == "story" and ep_r["name"] == "앱줍줍" and imgs["icon"] is None
assert fetched[-1][1] - fetched[-1][0] == social.timedelta(days=7)
social.decide("devlog-2026-11-29", True)
assert sorted(social.tick(get_issues, at(21, 0, day=29))) == ["episode_ig", "episode_threads"]
# 다음 에피소드는 기록을 보고 같은 앱·같은 소재를 피함
assert social.episode_history(at(20, 0, day=30)) == [{"date": "2026-11-29", "angle": "story", "repo": "Appjupjup"}]

# 확인 페이지(개발 일지 key도 서명 필요)
sigw = social.sign("devlog-2026-11-29")
r = client.get(f"/social/review/devlog-2026-11-29?sig={sigw}")
assert r.status_code == 200 and "앱 에피소드" in r.text and "slide1.png" in r.text
assert client.get("/social/review/devlog-2026-11-29?sig=bad").status_code == 404
assert client.get(f"/social/media/{w['dir']}/slide1.png").content == b"PNG1"

# 15) Ripe Weekly 홍보: 수요일 10:00 생성(한국어·영어 한 장씩) → 12:10 한국어, 23:00 영어(인스타 + Threads)
import ripe_promo  # noqa: E402

wed = lambda h, m: datetime(2026, 12, 2, h, m, tzinfo=social.KST)  # noqa: E731 - 수요일
assert wed(10, 0).weekday() == 2
k = ripe_promo.pick("ko", wed(10, 0))
assert k in ripe_promo.SETS["ko"] and ripe_promo.pick("en", wed(10, 0)) in ripe_promo.SETS["en"]
assert ripe_promo.pick("ko", wed(10, 0)) != ripe_promo.pick("ko", datetime(2026, 12, 9, tzinfo=social.KST))  # 주마다 바뀜
for lang in ("ko", "en"):
    s_ = ripe_promo.SETS[lang][0]
    # 링크는 넣지 않음(웹 버전이 무료·유료 확인 없이 AI 토큰을 써서)
    for text in (ripe_promo.threads_text(lang, s_), ripe_promo.caption(lang, s_)):
        assert "itssophie.dev" not in text and "http" not in text and len(text) <= 1000
    th = ripe_promo.threads_text(lang, s_)
    assert "👾" in th and "💜" in th and len(th) <= 500  # Threads는 소피 말투
assert "만들구 이쏘" in ripe_promo.threads_text("ko", ripe_promo.SETS["ko"][0])
assert "예시" in ripe_promo.caption("ko", k) and "example" in ripe_promo.caption("en", ripe_promo.SETS["en"][0])
os.environ["SOCIAL_PROMO"] = "1"
os.environ["SOCIAL_DEVLOG"] = "0"
_real_render = ripe_promo.render
ripe_promo.render = lambda lang, s: f"PNG-{lang}".encode()
assert not any(x.startswith("promo_") for x in social.tick(get_issues, datetime(2026, 12, 1, 10, 0, tzinfo=social.KST)))
assert "promo_generate" not in social.tick(get_issues, wed(9, 59))
assert "promo_generate" in social.tick(get_issues, wed(10, 0))
pr = social.load_state("promo-2026-12-02")
assert pr["kind"] == "promo" and set(pr["posts"]) == set(social.PROMO_CHANNELS)
assert social.media_file(pr["dir"], "ko.png").read_bytes() == b"PNG-ko"
assert social.tick(get_issues, wed(12, 10)) == []  # 승인 전
social.decide("promo-2026-12-02", True)
assert sorted(social.tick(get_issues, wed(12, 10))) == ["promo_ko_ig", "promo_ko_threads"]
assert social.tick(get_issues, wed(22, 59)) == []
assert sorted(social.tick(get_issues, wed(23, 0))) == ["promo_en_ig", "promo_en_threads"]
sigp = social.sign("promo-2026-12-02")
r = client.get(f"/social/review/promo-2026-12-02?sig={sigp}")
assert r.status_code == 200 and "Ripe Weekly" in r.text and "en.png" in r.text and "ripe.itssophie.dev" not in r.text
assert "12:10  인스타 피드 · 스레드 (한국어)" in r.text and "23:00  인스타 피드 · 스레드 (영어)" in r.text
ripe_promo.render = _real_render
os.environ["SOCIAL_PROMO"] = "0"
os.environ["SOCIAL_DEVLOG"] = "1"

# 미리보기 메일: SNS 전용 보내는 계정(SOCIAL_SMTP_*)으로, 받는 주소는 SOCIAL_PREVIEW_MAIL_TO, 확인 링크 포함
import smtplib  # noqa: E402

sent_mail = []


class FakeSMTP:
    def __init__(self, host, port, timeout=None):
        self.host = host

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def starttls(self):
        pass

    def login(self, user, pw):
        sent_mail.append(("login", user, pw))

    def send_message(self, msg):
        sent_mail.append(("msg", msg["From"], msg["To"], msg["Subject"], msg.get_body(("plain",)).get_content(),
                          msg.get_body(("html",)).get_content()))


smtplib.SMTP, _real_smtp = FakeSMTP, smtplib.SMTP
os.environ.update(SOCIAL_PREVIEW_MAIL_TO="threads@example.test", SOCIAL_SMTP_USER="sns@example.test",
                  SOCIAL_SMTP_PASSWORD="app-pw", FEEDBACK_SMTP_USER="feedback@example.test")
assert social.send_preview_email(social.load_state("devlog-2026-11-29")) is True
assert sent_mail[0] == ("login", "sns@example.test", "app-pw")
_, frm, to, subj, body, html = sent_mail[1]
assert frm == "sns@example.test" and to == "threads@example.test" and "앱 에피소드" in subj and "21:00" in subj
assert "/social/review/devlog-2026-11-29?sig=" in body and "/social/review/devlog-2026-11-29?sig=" in html
# 메일 한눈에: 목적, 몇 번 올라가는지, 채널(플랫폼·형식)별 그림과 글
assert "21:00  인스타 피드 · 스레드" in html and "21:00  인스타 피드 · 스레드" in subj
# 메일엔 '확인하기' 링크 하나만(do= 없음). 그림·글·주제 태그는 열리는 페이지에
assert "확인하기" in html and "확인하기:" in body and "do=" not in html and "do=" not in body
assert "slide1.png" not in html and "만든 이유" in subj
page = social._plan_html(social.load_state("devlog-2026-11-29"))
assert "주제 1인개발" in page and "slide1.png" in page and "그림은 위와 같음" in page
# 이슈팝: 08:00 한 번에 피드 + 스토리(스토리는 글 없음)
sent_mail.clear()
st25 = social.load_state("2026-11-25")
st25["posts"] = {c: social._new_post() for c in ("ig_feed", "ig_story")}  # 기본 채널(피드 + 스토리)
assert social.send_preview_email(st25) is True
_, _, _, subj, body, html = sent_mail[1]
assert "08:00  인스타 피드 · 인스타 스토리" in subj and "08:00  인스타 피드 · 인스타 스토리" in body
page = social._plan_html(st25)
assert "story.png" in page and "(글 없음)" in page
smtplib.SMTP = _real_smtp
for k in ("SOCIAL_PREVIEW_MAIL_TO", "SOCIAL_SMTP_USER", "SOCIAL_SMTP_PASSWORD", "FEEDBACK_SMTP_USER"):
    os.environ.pop(k)

# 생성 실패(GitHub 오류 등): 바로 다시 부르지 않고 15분 쉬고, 3번 실패하면 그날은 포기
def boom(since, until):
    raise RuntimeError("github down")


devlog.fetch_commits = boom
for m, should_try in ((0, True), (1, False), (15, True), (30, True), (45, False)):
    try:
        social.tick(get_issues, at(20, m, day=24))
        tried = False
    except RuntimeError:
        tried = True
    assert tried == should_try, (m, tried)

# 실제 게시 흐름(가짜 requests): 캐러셀 = 장마다 컨테이너 → 상태 확인 → 묶음 컨테이너 → 게시, Threads 글만 = TEXT
social.requests.post, social.requests.get = fake_post, fake_get
statuses = iter([])
os.environ["IG_ACCESS_TOKEN"] = "EAATOKEN"
calls.clear()
assert social.publish_instagram("carousel", ["https://x/1.png", "https://x/2.png"], "캡션", sleep=lambda s: None) == "P1"
posts = [c for c in calls if c[0] == "POST"]
assert [p[2].get("is_carousel_item") for p in posts[:2]] == ["true", "true"]
assert posts[2][2]["media_type"] == "CAROUSEL" and posts[2][2]["children"] == "C1,C1"
assert posts[3][1].endswith("/media_publish")
calls.clear()
assert social.publish_instagram("story", "https://x/story.png", "", sleep=lambda s: None) == "P1"
assert calls[0][2]["media_type"] == "STORIES" and "caption" not in calls[0][2]
calls.clear()
assert social.publish_threads(None, "글만", sleep=lambda s: None) == "P1"
assert calls[0][2]["media_type"] == "TEXT" and "image_url" not in calls[0][2]

print("ok")
