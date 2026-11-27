"""이슈팝 SNS 자동 게시 (Instagram 피드·릴스 + Threads).

하루 흐름(KST, 시각은 환경변수로 바꿀 수 있음):
  07:00  오늘자 카드(PNG)·영상(MP4) 생성 → 미리보기 메일 발송(승인 링크)
  (08:00  Threads  — 이슈팝 카드 + TOP5 글 + 플레이스토어 링크: 기본으로 꺼짐)
  08:00  Instagram 피드 — 카드(캡션 링크는 눌리지 않아서 "프로필 링크"로 안내)
  12:10  Instagram 릴스 — 영상
  20:00  개발 일지 생성(devlog.py: 공개 저장소 커밋) → 미리보기 메일
  21:00  Threads 게임 개발 일지(화면 위주: 게임 저장소 social/에 새 캡처가 있는 날만, 전→후 이미지 + 짧은 글)
         일요일엔 대신 앱 에피소드 한 장(새 앱=메모 / 앱 이야기=한 줄 임팩트 / 바이브 코딩=숫자) → 인스타 피드 + Threads
승인이 필요한 동안(SOCIAL_REQUIRE_APPROVAL=1, 기본값)은 승인된 날만 게시한다(이슈팝·개발 일지 따로 승인). 게시 시각이 지난 뒤
승인하면 다음 확인 주기(1분)에 바로 올라가되, 너무 늦으면(SOCIAL_LATE_LIMIT_MINUTES) 그 채널은 건너뛴다.

Instagram/Threads API는 우리 서버의 **공개 URL에서 미디어를 가져가는 방식**이라 파일은
SOCIAL_MEDIA_DIR/<날짜>-<무작위>/ 에 저장하고 GET /social/media/<그 폴더>/<파일>로 내보낸다
(폴더 이름에 무작위 값을 붙여서 승인 전 미리보기를 남이 날짜만으로 찾아 볼 수 없게).

⚠️ 토큰·시크릿은 서버 환경변수로만 둔다(레포가 public). 갱신된 장기 토큰은 SOCIAL_MEDIA_DIR/tokens.json
(권한 600)에 저장하고, 환경변수 값은 처음 한 번 쓰는 초기값이다.

환경변수(전부 선택, 기본값은 '아무것도 안 올라감' 쪽):
  SOCIAL_ENABLED=1            루프를 켬(기본 꺼짐)
  SOCIAL_DRY_RUN=0            실제 API 호출(기본 1 = 호출하지 않고 로그만)
  SOCIAL_REQUIRE_APPROVAL=0   확인 없이 자동 게시(기본 1)
  SOCIAL_SIGNING_SECRET       승인 링크 서명 키(없으면 승인 불가 → 승인 필요 모드에선 아무것도 안 올라감)
  SOCIAL_PREVIEW_MAIL_TO      미리보기 받을 주소(메일 계정은 FEEDBACK_SMTP_* 재사용)
  SOCIAL_PUBLIC_BASE          기본 https://api.issue-pop.com
  SOCIAL_MEDIA_DIR            기본 backend/data/social
  SOCIAL_TIMES                기본 DEFAULT_TIMES(아래) — 일부만 적으면 나머지는 기본값
  SOCIAL_CHANNELS             기본 전부(CHANNELS) — 일부만 켤 때 쉼표로
  SOCIAL_LATE_LIMIT_MINUTES   기본 180
  SOCIAL_DEVLOG=0             개발 일지 끔(기본 켬). 저장소 빼기·모델 등은 devlog.py 참고
  SOCIAL_EPISODE_WEEKDAY      주간 에피소드 요일(월=0 … 일=6, 기본 6)
  ANTHROPIC_KEY_SOCIAL        개발 일지 글쓰기용 Claude 키(없으면 커밋 제목으로 만든 기본 글)
  IG_USER_ID, IG_ACCESS_TOKEN, THREADS_USER_ID, THREADS_ACCESS_TOKEN
  IG_GRAPH_VERSION            기본 v23.0
  (IG 토큰이 EAA…로 시작하는 시스템 사용자 토큰이면 graph.facebook.com을 쓰고 갱신하지 않음 — 만료 없음.
   IG…로 시작하는 Instagram 로그인 토큰이면 graph.instagram.com + 45일마다 갱신.)
"""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import threading
import time
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import requests

KST = ZoneInfo("Asia/Seoul")
ISSUEPOP_CHANNELS = ("threads", "ig_feed", "ig_story", "ig_reel")
DEVLOG_CHANNELS = ("devlog_threads",)                  # 매일(게임 커밋 있는 날만) Threads 게임 개발 일지
EPISODE_CHANNELS = ("episode_ig", "episode_threads")   # 주 1회 "이번 주 만든 것"
CHANNELS = ISSUEPOP_CHANNELS + DEVLOG_CHANNELS + EPISODE_CHANNELS
CHANNEL_LABELS = {"threads": "Threads", "ig_feed": "Instagram 피드", "ig_story": "Instagram 스토리",
                  "ig_reel": "Instagram 릴스",
                  "devlog_threads": "Threads 게임 개발 일지", "episode_ig": "Instagram 피드(앱 에피소드)",
                  "episode_threads": "Threads 앱 에피소드"}
PLAY_URL = "https://play.google.com/store/apps/details?id=com.issuepop.issue_pop"
# 이슈팝은 매일 08:00 인스타 피드 + 스토리만(2026-11-27 사용자 결정). Threads는 게임 개발 일지(화면 바뀐 날)와
# 주간 앱 에피소드용. 이슈팝 Threads·릴스는 기본으로 끔 — SOCIAL_CHANNELS에 넣으면 다시 켜짐
DEFAULT_OFF = ("ig_reel", "threads")
DEFAULT_TIMES = ("preview=07:00,threads=08:00,ig_feed=08:00,ig_story=08:00,ig_reel=12:10,"
                 "devlog_preview=20:00,devlog_threads=21:00,episode_ig=21:00,episode_threads=21:00")
MAX_ATTEMPTS = 3
GEN_RETRY_MINUTES = 15  # 생성(렌더·GitHub·Claude)이 실패하면 이만큼 쉬었다 다시, 3번까지
TOKEN_REFRESH_AFTER_DAYS = 45  # 장기 토큰은 60일 — 넉넉히 앞서 갱신
KEY_RE = re.compile(r"^(?:devlog-)?\d{4}-\d{2}-\d{2}$")  # 승인 단위: 이슈팝은 날짜, 개발 일지는 devlog-날짜
DIR_RE = re.compile(r"^(?:devlog-)?\d{4}-\d{2}-\d{2}-[0-9a-f]{16}$")
MEDIA_FILES = {"card.png": "image/png", "story.png": "image/png", "reel.mp4": "video/mp4",
               **{f"slide{i}.png": "image/png" for i in range(1, 11)}}

_lock = threading.Lock()  # 상태 파일 읽고 쓰기(루프 스레드 ↔ 승인 요청)


# ---------- 설정 ----------

def _flag(name: str, default: bool) -> bool:
    v = os.environ.get(name)
    if v is None or v.strip() == "":
        return default
    return v.strip().lower() in ("1", "true", "yes", "on")


def enabled() -> bool:
    return _flag("SOCIAL_ENABLED", False)


def dry_run() -> bool:
    return _flag("SOCIAL_DRY_RUN", True)


def require_approval() -> bool:
    return _flag("SOCIAL_REQUIRE_APPROVAL", True)


def public_base() -> str:
    return (os.environ.get("SOCIAL_PUBLIC_BASE") or "https://api.issue-pop.com").rstrip("/")


def media_root() -> Path:
    default = Path(__file__).resolve().parent / "data" / "social"
    return Path(os.environ.get("SOCIAL_MEDIA_DIR") or default)


def times() -> dict[str, tuple[int, int]]:
    out = {}
    for part in (os.environ.get("SOCIAL_TIMES") or DEFAULT_TIMES).split(","):
        if "=" not in part:
            continue
        k, v = part.split("=", 1)
        h, m = v.strip().split(":")
        out[k.strip()] = (int(h), int(m))
    for part in DEFAULT_TIMES.split(","):  # 빠진 항목은 기본값
        k, v = part.split("=")
        if k not in out:
            h, m = v.split(":")
            out[k] = (int(h), int(m))
    return out


def channels() -> list[str]:
    raw = os.environ.get("SOCIAL_CHANNELS")
    if not raw:
        return [c for c in CHANNELS if c not in DEFAULT_OFF]
    return [c.strip() for c in raw.split(",") if c.strip() in CHANNELS]


def devlog_enabled() -> bool:
    return _flag("SOCIAL_DEVLOG", True)


def episode_weekday() -> int:
    """주간 에피소드 요일(월=0 … 일=6). 그날은 한 줄 일지 대신 에피소드를 올림."""
    return int(os.environ.get("SOCIAL_EPISODE_WEEKDAY") or 6)


def late_limit_minutes() -> int:
    return int(os.environ.get("SOCIAL_LATE_LIMIT_MINUTES") or 180)


def _at(now: datetime, hm: tuple[int, int]) -> datetime:
    return now.replace(hour=hm[0], minute=hm[1], second=0, microsecond=0)


# ---------- 날짜별 상태 ----------

def _state_path(dirname: str) -> Path:
    return media_root() / dirname / "state.json"


def _find_dir(key: str) -> str | None:
    root = media_root()
    if not root.exists():
        return None
    for p in sorted(root.glob(f"{key}-*")):
        if p.is_dir() and DIR_RE.match(p.name) and p.name[:-17] == key and (p / "state.json").exists():
            return p.name
    return None


def load_state(key: str) -> dict | None:
    """key: "2026-11-27"(이슈팝) 또는 "devlog-2026-11-27"(개발 일지)."""
    d = _find_dir(key)
    if d is None:
        return None
    return json.loads(_state_path(d).read_text(encoding="utf-8"))


def _save_state(state: dict) -> None:
    p = _state_path(state["dir"])
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")
    os.replace(tmp, p)


def media_url(state: dict, name: str) -> str:
    return f"{public_base()}/social/media/{state['dir']}/{name}"


def media_file(dirname: str, name: str) -> Path | None:
    """GET /social/media/{dirname}/{name}용 — 허용된 파일만, 경로 조작 불가."""
    if not DIR_RE.match(dirname) or name not in MEDIA_FILES:
        return None
    p = media_root() / dirname / name
    return p if p.is_file() else None


# ---------- 승인 링크 서명 ----------

def _secret() -> bytes | None:
    s = os.environ.get("SOCIAL_SIGNING_SECRET")
    return s.encode() if s else None


def sign(date: str) -> str:
    key = _secret()
    if key is None:
        return ""
    return hmac.new(key, f"social-approve:{date}".encode(), hashlib.sha256).hexdigest()[:32]


def verify(date: str, sig: str) -> bool:
    expected = sign(date)
    return bool(expected) and hmac.compare_digest(expected, sig or "")


def review_url(date: str) -> str:
    return f"{public_base()}/social/review/{date}?sig={sign(date)}"


# ---------- 생성 ----------

def _snapshot(issues: list[dict]) -> list[dict]:
    keep = ("keyword", "keywords", "category", "representative_title", "outlet_count", "article_count")
    return [{k: it.get(k) for k in keep} for it in issues[:5]]


def generate(issues: list[dict], now: datetime | None = None) -> dict:
    """오늘자 카드·영상을 만들고 상태 파일을 남김. 이미 있으면 그대로 반환."""
    import social_card
    import social_video

    now = now or datetime.now(KST)
    date = now.strftime("%Y-%m-%d")
    existing = load_state(date)
    if existing is not None:
        return existing
    top = _snapshot(issues)
    if not top:
        raise RuntimeError("이슈가 없어 카드를 만들 수 없음")

    dirname = f"{date}-{secrets.token_hex(8)}"
    out = media_root() / dirname
    out.mkdir(parents=True, exist_ok=True)
    card = social_card.render_card(top, now=now)
    (out / "card.png").write_bytes(card)
    (out / "story.png").write_bytes(social_card.render_story(card))
    if "ig_reel" in channels():  # 영상은 1 OCPU에서 1분 넘게 걸려서 릴스를 켰을 때만
        social_video.render_video(top, str(out / "reel.mp4"), now=now)

    state = {
        "kind": "issuepop",
        "key": date,
        "date": date,
        "dir": dirname,
        "generated_at": now.isoformat(),
        "issues": top,
        "caption": social_card.caption(top, now=now),
        "threads_text": threads_text(top, now=now),
        "approved": None,  # None=대기, True=승인, False=반려
        "decided_at": None,
        "preview_sent": False,
        "posts": {c: _new_post() for c in ISSUEPOP_CHANNELS if c in channels()},
    }
    with _lock:
        _save_state(state)
    return state


def _new_post() -> dict:
    return {"status": "pending", "attempts": 0, "id": None, "error": None}


def episode_history(now: datetime, days: int = 60) -> list[dict]:
    """최근 에피소드들 [{date, angle, repo}] (최근 것이 앞) — 같은 소재·같은 앱이 연달아 나오지 않게."""
    root = media_root()
    out = []
    if not root.exists():
        return out
    cutoff = (now - timedelta(days=days)).strftime("%Y-%m-%d")
    for p in sorted(root.glob("devlog-*"), reverse=True):
        if not (DIR_RE.match(p.name) and (p / "state.json").exists()):
            continue
        st = json.loads((p / "state.json").read_text(encoding="utf-8"))
        ep = st.get("episode")
        if ep and cutoff <= st["date"] < now.strftime("%Y-%m-%d") and st.get("approved") is not False:
            out.append({"date": st["date"], "angle": ep.get("angle"), "repo": ep.get("repo")})
    return out


def _used_game_captures(now: datetime, days: int = 14) -> set:
    """최근 게임 개발 일지에 이미 쓴 캡처("저장소/경로") — 반려한 날 것도 다시 안 씀."""
    root = media_root()
    used = set()
    cutoff = (now - timedelta(days=days)).strftime("%Y-%m-%d")
    for p in root.glob("devlog-*") if root.exists() else []:
        if DIR_RE.match(p.name) and (p / "state.json").exists():
            st = json.loads((p / "state.json").read_text(encoding="utf-8"))
            if st.get("game") and st["date"] >= cutoff:
                used.add(f"{st['game']['repo']}/{st['game']['after']}")
    return used


def generate_devlog(now: datetime | None = None) -> dict:
    """개발 일지: 에피소드 요일이면 지난 7일 → 앱 에피소드(캐러셀+글), 아니면 지난 24시간 → Threads 게임 개발 일지.
    올릴 게 없으면(게임 커밋 없음 등) empty 상태만 남기고 아무것도 안 올림."""
    import devlog
    import devlog_card

    now = now or datetime.now(KST)
    date = now.strftime("%Y-%m-%d")
    key = f"devlog-{date}"
    existing = load_state(key)
    if existing is not None:
        return existing
    weekly = now.weekday() == episode_weekday()
    since, until = devlog.window(now, 7 if weekly else 1)
    groups = devlog.group_by_project(devlog.fetch_commits(since, until))

    dirname = f"{key}-{secrets.token_hex(8)}"
    out = media_root() / dirname
    out.mkdir(parents=True, exist_ok=True)
    state = {"kind": "devlog", "key": key, "date": date, "dir": dirname, "generated_at": now.isoformat(),
             "weekly": weekly, "approved": None, "decided_at": None, "preview_sent": False,
             "projects": [{"name": g["name"], "count": g["count"]} for g in groups], "posts": {}}
    ep = devlog.weekly_episode(groups, since, until, episode_history(now)) if weekly else None
    game = None if weekly else devlog.game_visual(groups, since, until, now, _used_game_captures(now))
    if weekly and ep is None or not weekly and game is None:
        state["empty"] = True
    elif not weekly:  # 게임 개발 일지: 전→후 화면 한 장
        after = devlog.fetch_image(game["repo"], game["after"])
        if after is None:
            state["empty"] = True
        else:
            before = devlog.fetch_image(game["repo"], game["before"])
            (out / "slide1.png").write_bytes(devlog_card.render_game(game, before, after))
            state.update(game=game, slides=1, devlog_text=game["text"],
                         posts={c: _new_post() for c in DEVLOG_CHANNELS})
    else:
        # 그림: 앱 아이콘·대표 화면(스토어 스크린샷), 그 주 캡처(저장소 social/YYYY-MM-DD-*.png)가 있으면 그걸.
        # 바이브 코딩 기록은 앱 하나가 아니라서 그림 없음
        repo = ep["repo"]
        images = {"icon": devlog.fetch_image(repo, ep.get("icon")) if repo else None,
                  "shot": devlog.fetch_image(repo, ep.get("shot")) if repo else None,
                  "capture": devlog.fetch_image(repo, devlog.week_capture(repo, since, until)) if repo else None}
        ep["has"] = {k: v is not None for k, v in images.items()}
        slides = devlog_card.render_episode(ep, images)
        for i, png in enumerate(slides, 1):
            (out / f"slide{i}.png").write_bytes(png)
        state.update(episode=ep, slides=len(slides), caption=ep["caption"], threads_text=ep["threads"],
                     posts={c: _new_post() for c in EPISODE_CHANNELS})
    with _lock:
        _save_state(state)
    return state


def threads_text(issues: list[dict], now: datetime | None = None) -> str:
    """Threads 본문(500자 제한, 해시태그 대신 주제 태그 하나)."""
    from social_card import _keyword

    now = now or datetime.now(KST)
    lines = [f"📰 {now.month}월 {now.day}일 오늘 가장 많이 보도된 이슈 TOP {min(5, len(issues))}", ""]
    for i, it in enumerate(issues[:5], 1):
        lines.append(f"{i}. {_keyword(it)} — {it.get('outlet_count', 0)}개 매체 · {it.get('article_count', 0)}건")
    # Threads는 본문 링크가 눌림(Mosseri: 링크를 일부러 낮추지 않음). 인스타 캡션 링크는 안 눌려서 거긴 프로필 링크로 안내
    lines += ["", "매체별 기사는 앱 ‘이슈팝’에서 👇", PLAY_URL, "#오늘의뉴스"]
    return "\n".join(lines)[:500]


# ---------- 미리보기 메일 ----------

def send_preview_email(state: dict) -> bool:
    import smtplib
    from email.message import EmailMessage

    to = os.environ.get("SOCIAL_PREVIEW_MAIL_TO")
    user = os.environ.get("FEEDBACK_SMTP_USER")
    password = os.environ.get("FEEDBACK_SMTP_PASSWORD")
    if not to or not user or not password:
        print("[social] 미리보기 메일 설정 없음(SOCIAL_PREVIEW_MAIL_TO / FEEDBACK_SMTP_*) — 건너뜀")
        return False
    t = times()
    key = state.get("key", state["date"])
    sched = ", ".join(f"{CHANNEL_LABELS[c]} {t[c][0]:02d}:{t[c][1]:02d}" for c in channels() if c in state["posts"])
    if state.get("kind") == "devlog":
        names = " · ".join(p["name"] for p in state.get("projects", []))
        what = "앱 에피소드" if state.get("weekly") else "게임 개발 일지"
        subject = f"[소피앱스 SNS] {state['date']} {what} 확인 — {names}"
        body = state.get("caption") or state.get("devlog_text") or ""
        body_label = "인스타그램 캡션" if state.get("caption") else "Threads 글"
    else:
        keywords = " · ".join(it.get("keyword") or "" for it in state["issues"])
        subject = f"[이슈팝 SNS] {state['date']} 게시 확인 — {keywords}"
        body, body_label = state["caption"], "인스타그램 캡션"
    msg = EmailMessage()
    msg["Subject"] = subject[:150]
    msg["From"] = os.environ.get("FEEDBACK_MAIL_FROM") or user
    msg["To"] = to
    mode = "확인 필요 — 승인해야 올라가요" if require_approval() else "자동 게시 모드 — 반려하면 안 올라가요"
    msg.set_content(
        f"오늘 SNS 게시물 미리보기예요. ({mode})\n\n"
        f"확인·승인: {review_url(key)}\n\n"
        f"예정: {sched}{' (dry-run: 실제로는 안 올라감)' if dry_run() else ''}\n\n"
        f"--- {body_label} ---\n{body}\n"
    )
    host = os.environ.get("FEEDBACK_SMTP_HOST") or "smtp.gmail.com"
    port = int(os.environ.get("FEEDBACK_SMTP_PORT") or 587)
    with smtplib.SMTP(host, port, timeout=20) as smtp:
        smtp.starttls()
        smtp.login(user, password)
        smtp.send_message(msg)
    return True


def decide(key: str, approve: bool) -> dict | None:
    with _lock:
        state = load_state(key)
        if state is None:
            return None
        state["approved"] = approve
        state["decided_at"] = datetime.now(KST).isoformat()
        _save_state(state)
        return state


_STATUS_KO = {"pending": "대기", "posted": "게시됨", "skipped": "건너뜀", "failed": "실패"}


def review_html(state: dict, sig: str) -> str:
    """메일 링크로 여는 확인 페이지. 승인/반려는 버튼(POST)으로만 — 메일 앱이 링크를 미리 열어 봐도 승인되지 않게."""
    from html import escape

    t = times()
    if state["approved"] is True:
        decision = "✅ 승인됨"
    elif state["approved"] is False:
        decision = "⛔ 반려됨 (오늘은 안 올라가요)"
    else:
        decision = "⏳ 대기 중" + (" — 승인해야 올라가요" if require_approval() else " — 반려하지 않으면 예정대로 올라가요")
    key = state.get("key", state["date"])
    mine = [c for c in channels() if c in state["posts"]]
    rows = "".join(
        f"<li>{CHANNEL_LABELS[c]} {t[c][0]:02d}:{t[c][1]:02d} — {_STATUS_KO.get(state['posts'][c]['status'], '')}"
        f"{' · ' + escape(state['posts'][c]['error']) if state['posts'][c].get('error') else ''}</li>"
        for c in mine
    )
    action = f"/social/review/{key}?sig={escape(sig)}"
    buttons = ""
    if any(state["posts"][c]["status"] == "pending" for c in mine):
        buttons = (
            f'<form method="post" action="{action}&action=approve" style="display:inline">'
            f'<button style="background:#17356b;color:#fff">승인</button></form> '
            f'<form method="post" action="{action}&action=reject" style="display:inline">'
            f'<button>반려(오늘 게시 안 함)</button></form>'
        )
    base = f"/social/media/{state['dir']}"
    devlog = state.get("kind") == "devlog"
    title = ("앱 에피소드" if state.get("weekly") else "게임 개발 일지") if devlog else "이슈팝 SNS"
    media = ""
    if not devlog:
        media = (f'<h3>카드 (Threads · Instagram 피드)</h3><img src="{base}/card.png" alt="카드">'
                 f'<h3>스토리</h3><img src="{base}/story.png" alt="스토리" style="max-width:320px">')
        if "ig_reel" in state["posts"]:
            media += f'<h3>릴스</h3><video src="{base}/reel.mp4" controls playsinline></video>'
    for i in range(1, (state.get("slides") or 0) + 1):
        media += f'<img src="{base}/slide{i}.png" alt="{i}장">'
    if state.get("slides"):
        media = "<h3>이미지</h3>" + media
    texts = ""
    for field, label in (("caption", "Instagram 캡션"), ("threads_text", "Threads 글"),
                         ("devlog_text", "Threads 게임 개발 일지")):
        if state.get(field):
            texts += f"<h3>{label}</h3><pre>{escape(state[field])}</pre>"
    if state.get("empty"):
        texts = "<p>이 기간 공개 저장소 커밋이 없어서 올릴 게 없어요.</p>"
    return f"""<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex">
<title>{title} 확인 {state['date']}</title>
<style>body{{font-family:sans-serif;max-width:560px;margin:0 auto;padding:16px;color:#14161c}}
img,video{{width:100%;border-radius:12px;margin:8px 0}} pre{{white-space:pre-wrap;background:#f4f4f1;padding:12px;border-radius:8px}}
button{{font-size:17px;padding:12px 20px;border-radius:10px;border:1px solid #17356b;margin:4px 0}}</style></head><body>
<h2>{state['date']} {title} 게시 확인</h2>
<p><b>{decision}</b>{' · dry-run(실제로는 안 올라감)' if dry_run() else ''}</p>
{buttons}
<ul>{rows}</ul>
{media}
{texts}
</body></html>"""


# ---------- 토큰 ----------

def _tokens_path() -> Path:
    return media_root() / "tokens.json"


def _load_tokens() -> dict:
    p = _tokens_path()
    if p.exists():
        return json.loads(p.read_text(encoding="utf-8"))
    return {}


def _save_tokens(tokens: dict) -> None:
    p = _tokens_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(".tmp")
    tmp.write_text(json.dumps(tokens), encoding="utf-8")
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.replace(tmp, p)


def get_token(service: str) -> str | None:
    """service: 'ig' | 'threads'. 저장된(갱신된) 토큰이 있으면 그걸, 없으면 환경변수."""
    saved = _load_tokens().get(service)
    env = os.environ.get("IG_ACCESS_TOKEN" if service == "ig" else "THREADS_ACCESS_TOKEN")
    # 환경변수를 새 토큰으로 바꿨으면(seed가 달라지면) 그걸 우선
    if saved and saved.get("seed") == _seed_hash(env):
        return saved["token"]
    return env


def _seed_hash(token: str | None) -> str:
    return hashlib.sha256((token or "").encode()).hexdigest()[:16]


REFRESH_URLS = {
    "ig": ("https://graph.instagram.com/refresh_access_token", "ig_refresh_token"),
    "threads": ("https://graph.threads.net/refresh_access_token", "th_refresh_token"),
}


def refresh_tokens_if_due(now: float | None = None) -> list[str]:
    """장기 토큰을 TOKEN_REFRESH_AFTER_DAYS마다 갱신. 갱신한 서비스 목록 반환."""
    now = now or time.time()
    tokens = _load_tokens()
    done = []
    for service, (url, grant) in REFRESH_URLS.items():
        env = os.environ.get("IG_ACCESS_TOKEN" if service == "ig" else "THREADS_ACCESS_TOKEN")
        if not env or (service == "ig" and not _ig_login_token(env)):
            continue  # 비즈니스 시스템 사용자 토큰(EAA…)은 만료가 없어 갱신하지 않음
        cur = tokens.get(service)
        if cur is None or cur.get("seed") != _seed_hash(env):
            # 처음 보는(새로 발급해 넣은) 환경변수 토큰: 지금을 기준으로 기록만 하고, 갱신은 주기가 됐을 때
            cur = tokens[service] = {"token": env, "seed": _seed_hash(env), "refreshed_at": now}
            _save_tokens(tokens)
        if now - cur.get("refreshed_at", 0) < TOKEN_REFRESH_AFTER_DAYS * 86400:
            continue
        token = cur["token"]
        if dry_run():
            print(f"[social] (dry-run) {service} 토큰 갱신 건너뜀")
            continue
        r = requests.get(url, params={"grant_type": grant, "access_token": token}, timeout=30)
        r.raise_for_status()
        new = r.json().get("access_token")
        if not new:
            raise RuntimeError(f"{service} 토큰 갱신 응답에 access_token 없음")
        tokens[service] = {"token": new, "seed": _seed_hash(env), "refreshed_at": now}
        _save_tokens(tokens)
        done.append(service)
    return done


# ---------- 게시 API ----------

def _ig_login_token(token: str) -> bool:
    """Instagram 로그인 토큰(IG…, 60일, ig_refresh_token으로 갱신)인지.
    아니면 통합 로그인(Facebook Login for Business)의 시스템 사용자 토큰(EAA…, 만료 없음) → graph.facebook.com."""
    return token.startswith("IG")


def _graph_ig(token: str) -> str:
    host = "graph.instagram.com" if _ig_login_token(token) else "graph.facebook.com"
    return f"https://{host}/{os.environ.get('IG_GRAPH_VERSION') or 'v23.0'}"


GRAPH_THREADS = "https://graph.threads.net/v1.0"


def _post(url: str, data: dict) -> dict:
    r = requests.post(url, data=data, timeout=60)
    if r.status_code >= 400:
        # 응답 본문에 토큰이 섞일 일은 없지만 길이는 자름
        raise RuntimeError(f"HTTP {r.status_code}: {r.text[:300]}")
    return r.json()


def _wait_container(url: str, token: str, field: str, ok: str, fail: tuple[str, ...],
                    timeout: float = 300, interval: float = 5, sleep=time.sleep) -> None:
    deadline = time.monotonic() + timeout
    while True:
        r = requests.get(url, params={"fields": field, "access_token": token}, timeout=30)
        r.raise_for_status()
        status = r.json().get(field)
        if status == ok:
            return
        if status in fail:
            raise RuntimeError(f"미디어 처리 실패: {status} {r.json()}")
        if time.monotonic() > deadline:
            raise RuntimeError(f"미디어 처리 시간 초과(마지막 상태 {status})")
        sleep(interval)


def publish_instagram(kind: str, media, caption: str, sleep=time.sleep) -> str:
    """kind: 'image' | 'reel' | 'carousel'(media=이미지 URL 목록, 2~10장). 반환: 게시물 id."""
    user, token = os.environ.get("IG_USER_ID"), get_token("ig")
    if not user or not token:
        raise RuntimeError("IG_USER_ID / IG_ACCESS_TOKEN 없음")
    base = _graph_ig(token)
    data = {"caption": caption, "access_token": token}
    if kind == "story":  # 스토리는 캡션이 없음(비즈니스 계정만 API로 올릴 수 있음)
        data = {"media_type": "STORIES", "image_url": media, "access_token": token}
    elif kind == "image":
        data["image_url"] = media
    elif kind == "carousel":
        children = [_post(f"{base}/{user}/media",
                          {"image_url": u, "is_carousel_item": "true", "access_token": token})["id"] for u in media]
        for cid in children:
            _wait_container(f"{base}/{cid}", token, "status_code", "FINISHED", ("ERROR", "EXPIRED"),
                            timeout=120, sleep=sleep)
        data.update(media_type="CAROUSEL", children=",".join(children))
    else:
        data.update(media_type="REELS", video_url=media, share_to_feed="true")
    container = _post(f"{base}/{user}/media", data)["id"]
    _wait_container(f"{base}/{container}", token, "status_code", "FINISHED", ("ERROR", "EXPIRED"),
                    timeout=600 if kind == "reel" else 120, sleep=sleep)
    return _post(f"{base}/{user}/media_publish", {"creation_id": container, "access_token": token})["id"]


def publish_threads(image: str | None, text: str, sleep=time.sleep) -> str:
    """image가 None이면 글만(TEXT)."""
    user, token = os.environ.get("THREADS_USER_ID"), get_token("threads")
    if not user or not token:
        raise RuntimeError("THREADS_USER_ID / THREADS_ACCESS_TOKEN 없음")
    data = {"media_type": "IMAGE", "image_url": image} if image else {"media_type": "TEXT"}
    container = _post(f"{GRAPH_THREADS}/{user}/threads", {**data, "text": text, "access_token": token})["id"]
    _wait_container(f"{GRAPH_THREADS}/{container}", token, "status", "FINISHED", ("ERROR", "EXPIRED"),
                    timeout=120, sleep=sleep)
    return _post(f"{GRAPH_THREADS}/{user}/threads_publish", {"creation_id": container, "access_token": token})["id"]


def _publish(channel: str, state: dict) -> str:
    if dry_run():
        print(f"[social] (dry-run) {CHANNEL_LABELS[channel]} 게시 건너뜀: {state['dir']}")
        return "dry-run"
    if channel == "threads":
        return publish_threads(media_url(state, "card.png"), state["threads_text"])
    if channel == "ig_feed":
        return publish_instagram("image", media_url(state, "card.png"), state["caption"])
    if channel == "ig_story":
        return publish_instagram("story", media_url(state, "story.png"), "")
    if channel == "ig_reel":
        return publish_instagram("reel", media_url(state, "reel.mp4"), state["caption"])
    if channel == "devlog_threads":
        image = media_url(state, "slide1.png") if state.get("slides") else None
        return publish_threads(image, state["devlog_text"])
    if channel == "episode_ig":
        if state["slides"] == 1:
            return publish_instagram("image", media_url(state, "slide1.png"), state["caption"])
        slides = [media_url(state, f"slide{i}.png") for i in range(1, state["slides"] + 1)]
        return publish_instagram("carousel", slides, state["caption"])
    if channel == "episode_threads":
        return publish_threads(media_url(state, "slide1.png"), state["threads_text"])
    raise ValueError(channel)


# ---------- 루프 한 번 ----------

_gen_failures: dict[str, tuple[int, datetime]] = {}  # key → (실패 횟수, 마지막 실패 시각)


def tick(get_issues, now: datetime | None = None) -> list[str]:
    """1분마다 호출. 해야 할 일(생성·메일·게시)을 하고 한 일 목록을 반환."""
    now = now or datetime.now(KST)
    date = now.strftime("%Y-%m-%d")
    did = _run_batch(date, "preview", ISSUEPOP_CHANNELS, lambda: generate(get_issues(), now=now), now, "")
    if devlog_enabled():
        did += _run_batch(f"devlog-{date}", "devlog_preview", DEVLOG_CHANNELS + EPISODE_CHANNELS,
                          lambda: generate_devlog(now), now, "devlog_")
    return did


def _run_batch(key: str, preview: str, batch_channels: tuple, make, now: datetime, tag: str) -> list[str]:
    """한 묶음(이슈팝 하루치 / 개발 일지 하루치): 생성 → 미리보기 메일 → 승인 확인 → 채널별 시각에 게시."""
    t = times()
    did: list[str] = []
    if now < _at(now, t[preview]):
        return did
    state = load_state(key)
    if state is None:
        active = [c for c in channels() if c in batch_channels]
        first_post = min((_at(now, t[c]) for c in active), default=_at(now, t[preview]))
        if now > first_post + timedelta(minutes=late_limit_minutes()):
            return did  # 오늘은 이미 너무 늦음(예: 서버가 하루 종일 꺼져 있다가 저녁에 켜짐)
        fails, last = _gen_failures.get(key, (0, None))
        if fails >= MAX_ATTEMPTS or (last and now - last < timedelta(minutes=GEN_RETRY_MINUTES)):
            return did  # 생성이 계속 실패하면 쉬었다가(GitHub 호출 제한 등), 3번 넘으면 그날은 포기
        try:
            state = make()
        except Exception:
            _gen_failures[key] = (fails + 1, now)
            raise
        _gen_failures.pop(key, None)
        did.append(f"{tag}generate")
    if not state["preview_sent"]:
        sent = False if state.get("empty") else send_preview_email(state)
        with _lock:
            state = load_state(key)
            state["preview_sent"] = True  # 설정이 없어 못 보낸 경우도 다시 시도하지 않음
            _save_state(state)
        if sent:
            did.append(f"{tag}preview_mail")

    if state["approved"] is False:
        return did
    if require_approval() and state["approved"] is not True:
        return did

    for c in channels():
        if c not in state["posts"]:
            continue
        post = state["posts"][c]
        if post["status"] in ("posted", "skipped", "failed"):
            continue
        due = _at(now, t[c])
        if now < due:
            continue
        if now > due + timedelta(minutes=late_limit_minutes()):
            post.update(status="skipped", error="게시 시각에서 너무 늦음")
        else:
            try:
                post["id"] = _publish(c, state)
                post["status"] = "posted"
                post["posted_at"] = now.isoformat()
                post["error"] = None
                did.append(c)
            except Exception as e:  # noqa: BLE001 - 다음 주기에 다시
                post["attempts"] += 1
                post["error"] = f"{type(e).__name__}: {e}"[:300]
                if post["attempts"] >= MAX_ATTEMPTS:
                    post["status"] = "failed"
                print(f"[social] {CHANNEL_LABELS[c]} 게시 실패({post['attempts']}회): {post['error']}")
        with _lock:
            fresh = load_state(key)
            fresh["posts"][c] = post
            _save_state(fresh)
            state = fresh
    return did
