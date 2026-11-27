"""만드는 과정 공개(build in public): GitHub 커밋 → 게임 개발 일지·앱 에피소드.

- 매일(Threads): **게임 개발 일지** — 게임 저장소(GAME_REPOS)에 지난 24시간 커밋이 있는 날만, 글만.
- 주 1회(인스타 캐러셀 5장 + Threads, SOCIAL_EPISODE_WEEKDAY 기본 일요일): **앱 에피소드**. 매주 최근 커밋만
  정리하면 "무슨 얘긴지 모르겠다"가 돼서(2026-11-27 피드백) 그 주 상황에 맞는 소재 하나를 고름:
    new    이번 주 새로 만든 앱 저장소가 있으면 "이런 앱을 만들기 시작했어요"
    vibe   바이브 코딩 기록 — "이번 주 앱 N개에 커밋 M번, 왜 이렇게 많이?"(직전 에피소드가 story였고 많이 한 주)
    story  앱 이야기 — 앱마다 적어 둔 만든 이유(APPS[...]["why"])를 중심으로, 최근 커밋은 "이번 주엔"으로만
  앱 화면은 각 저장소의 스토어 스크린샷·아이콘(GitHub raw). 그 주 캡처를 쓰려면 그 앱 저장소의 social/ 폴더에
  `YYYY-MM-DD-이름.png|jpg`로 넣어 푸시.
소재는 **공개 저장소의 커밋 메시지·저장소 정보와 여기 적어 둔 앱 소개뿐**(Claude Code 대화 기록은 키·개인정보가
섞일 수 있어 안 씀). 글은 Claude(키 ANTHROPIC_KEY_SOCIAL, 없으면 기본 글), 올리기 전 social.py의 미리보기·승인.

환경변수:
  SOCIAL_GITHUB_USER       기본 LetsBeLikeSophie
  SOCIAL_GAME_REPOS        게임 저장소 추가(쉼표, 코드 안 고치고). 예: 새로 시작한 듀랑고 스타일 게임 저장소
  SOCIAL_DEVLOG_EXCLUDE    빼고 싶은 저장소 이름(쉼표)
  GITHUB_TOKEN             선택(없어도 공개 저장소는 읽힘 — 시간당 60회 제한이라 하루 몇 번이면 충분)
  SOCIAL_LLM_MODEL         기본 claude-sonnet-5-5
"""
from __future__ import annotations

import io
import json
import os
import re
from datetime import datetime, timedelta

import requests

GITHUB_API = "https://api.github.com"
RAW = "https://raw.githubusercontent.com"
DEFAULT_MODEL = "claude-sonnet-5-5"
MAX_IMAGE_BYTES = 8 * 1024 * 1024
VIBE_MIN_COMMITS = 20  # 이만큼은 해야 "바이브 코딩 기록" 소재가 됨

# 저장소 → 보여 줄 이름·한 줄 소개·만든 이유(why, 에피소드 이야기의 중심)·그림 경로·게임 여부.
# app=False: 앱이 아니라 에피소드 주인공으로 안 고름. game=True: 인스타 에피소드 대신 Threads 게임 개발 일지로.
APPS = {
    "issue-pop": {"name": "이슈팝", "tagline": "여러 언론사 기사를 이슈별로 묶어 오늘 가장 많이 보도된 뉴스를 보여 주는 앱",
                  "icon": "app/assets/icon/app_icon_512_store.png",
                  "shot": "app/assets/screenshots/phone/Screenshot_20261003_155415.jpg"},
    "dailycut": {"name": "데일리컷", "tagline": "혜택·청약·물가 같은 생활 정보를 매일 카드로 모아 보여 주는 앱",
                 "icon": "store/icon-512.png", "shot": "store/screenshots/1_benefit.png"},
    "mehh": {"name": "Mehh", "tagline": "귀찮아서 못 한 사진 정리, 지울 만한 사진을 이유와 함께 골라 주는 앱",
             "icon": "docs/store/icon-512.png", "shot": "docs/store/screenshots-ko/1-home.png"},
    "cortex": {"name": "Cortex", "tagline": "어디서든 공유 버튼 하나로 저장하고 검색 한 번으로 다시 찾는 아카이브 앱"},
    "appjupjup": {"name": "앱줍줍", "tagline": "내 앱 올리고 남의 앱 줍줍, 한 줄 피드백을 주고받는 앱 품앗이",
                  "why": "앱 홍보 사이트가 많은 건 알지만 내 목적과 달라서 직접 만들었다. 홍보가 아니라 만든 사람끼리 "
                         "서로 받아 써 보고 한 줄 피드백을 주고받는 곳. 앱을 계속 만들고 있어서 필요했다."},
    "camtrip": {"name": "CamTrip", "tagline": "메뉴판·영수증을 찍으면 폰에서 바로 번역하고 여행 경비로 정리해 주는 앱",
                "icon": "docs/store/icon-512.png"},
    "ripe-weekly": {"name": "Ripe Weekly", "tagline": "궁금한 분야를 적으면 AI가 매주 뜨는 것만 3분 리포트로 보내 주는 앱"},
    "tablelink": {"name": "TableLink", "tagline": "조건만 말하면 여러 테이블을 알아서 이어 고객 목록을 뽑아 주는 도구"},
    "my-little-sessions": {"name": "My Little Sessions",
                           "tagline": "Claude Code 작업 창을 픽셀아트 사무실 직원으로 보여 주는 데스크톱 앱",
                           "shot": "docs/screenshot-ko.png"},
    "sophies-office-hours": {"name": "Sophie's Office Hours", "tagline": "AI로 앱 만들다 막힌 비전공자를 위한 디버깅 상담소"},
    "portfolio": {"name": "포트폴리오 사이트", "tagline": "소피앱스의 앱들을 모아 둔 사이트", "app": False},
    # 게임 — Threads 게임 개발 일지로
    "subwayrush": {"name": "지옥철", "tagline": "출근길 지하철 인파를 뚫고 지각 없이 환승역까지 가는 게임", "game": True},
    "skyisland": {"name": "가라앉은 하늘섬", "tagline": "웹·모바일 브라우저로 하는 비동기 협동 전략 게임", "game": True},
}


def _extra_games() -> set[str]:
    return {x.strip().lower() for x in (os.environ.get("SOCIAL_GAME_REPOS") or "").split(",") if x.strip()}


def app_info(repo: str) -> dict:
    a = APPS.get(repo.lower(), {})
    return {"repo": repo, "name": a.get("name", repo), "tagline": a.get("tagline", ""), "why": a.get("why", ""),
            "icon": a.get("icon"), "shot": a.get("shot"), "app": a.get("app", True),
            "game": a.get("game", False) or repo.lower() in _extra_games()}


def app_name(repo: str) -> str:
    return app_info(repo)["name"]


# ---------- 민감한 내용 가리기 ----------

_REDACT = [
    (re.compile(r"[\w.+-]+@[\w-]+\.[\w.]+"), "[메일]"),
    (re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b"), "[주소]"),
    (re.compile(r"\b(?:sk|pk|ghp|gho|github_pat|xox[abp]|AKIA|AIza|EAA|IGAA|THAA)[\w-]{8,}"), "[키]"),
    (re.compile(r"\b[A-Za-z0-9_\-]{32,}\b"), "[키]"),  # 길게 이어진 토큰·해시
    (re.compile(r"https?://\S+"), "[링크]"),
]


def redact(text: str) -> str:
    for pat, rep in _REDACT:
        text = pat.sub(rep, text)
    return text


def _clean_message(msg: str) -> str:
    lines = [ln for ln in msg.strip().splitlines()
             if ln.strip() and not ln.lower().startswith(("co-authored-by", "signed-off-by"))]
    return redact("\n".join(lines))[:600]


# ---------- GitHub ----------

def _user() -> str:
    return os.environ.get("SOCIAL_GITHUB_USER") or "LetsBeLikeSophie"


def _headers() -> dict:
    h = {"Accept": "application/vnd.github+json", "User-Agent": "issuepop-social"}
    tok = os.environ.get("GITHUB_TOKEN")
    if tok:
        h["Authorization"] = f"Bearer {tok}"
    return h


def _get(url: str, params: dict | None = None):
    r = requests.get(url, params=params, headers=_headers(), timeout=30)
    if r.status_code in (404, 409):  # 없는 폴더 / 빈 저장소
        return []
    r.raise_for_status()
    return r.json()


def fetch_commits(since: datetime, until: datetime) -> list[dict]:
    """since~until 사이 공개 저장소 커밋(머지 제외, 빼는 목록 제외). 저장소 만든 날(created)도 같이."""
    user = _user()
    exclude = {x.strip().lower() for x in (os.environ.get("SOCIAL_DEVLOG_EXCLUDE") or "").split(",") if x.strip()}
    repos = _get(f"{GITHUB_API}/users/{user}/repos", {"per_page": 100, "sort": "pushed"})
    out = []
    for repo in repos:
        name = repo["name"]
        if repo.get("fork") or repo.get("private") or repo.get("archived") or name.lower() in exclude:
            continue
        if name.lower() == user.lower():  # 프로필 README 저장소
            continue
        pushed = datetime.fromisoformat(repo["pushed_at"].replace("Z", "+00:00"))
        if pushed < since:
            break  # pushed 순으로 정렬돼 있음
        commits = _get(f"{GITHUB_API}/repos/{user}/{name}/commits",
                       {"since": since.isoformat(), "until": until.isoformat(), "per_page": 100})
        for c in commits:
            if len(c.get("parents") or []) > 1:
                continue
            msg = c["commit"]["message"]
            if msg.startswith("Merge "):
                continue
            out.append({"repo": name, "sha": c["sha"][:7], "date": c["commit"]["author"]["date"],
                        "created": repo.get("created_at", ""), "message": _clean_message(msg)})
    return out


def group_by_project(commits: list[dict]) -> list[dict]:
    """[{repo, name, tagline, why, game, created, count, messages, days}] 커밋 많은 순."""
    groups: dict[str, dict] = {}
    for c in commits:
        g = groups.setdefault(c["repo"], {**app_info(c["repo"]), "created": c.get("created", ""),
                                          "count": 0, "messages": [], "days": set()})
        g["count"] += 1
        g["messages"].append(c["message"])
        if c.get("date"):
            g["days"].add(c["date"][:10])
    out = sorted(groups.values(), key=lambda g: -g["count"])
    for g in out:
        g["days"] = len(g["days"])
    return out


def fetch_image(repo: str, path: str | None):
    """저장소의 그림(스토어 스크린샷·아이콘·캡처)을 PIL 이미지로. 없거나 이상하면 None."""
    if not path:
        return None
    from PIL import Image

    try:
        r = requests.get(f"{RAW}/{_user()}/{repo}/HEAD/{path}", headers={"User-Agent": "issuepop-social"},
                         timeout=30)
        if r.status_code != 200 or len(r.content) > MAX_IMAGE_BYTES:
            return None
        im = Image.open(io.BytesIO(r.content))
        im.load()
        return im.convert("RGBA")
    except Exception:  # noqa: BLE001 - 그림 하나 없다고 에피소드를 못 만들면 안 됨
        return None


def week_capture(repo: str, since: datetime, until: datetime) -> str | None:
    """저장소 social/ 폴더에서 이번 주 날짜(YYYY-MM-DD-*.png|jpg)로 시작하는 캡처 중 가장 최근 것의 경로."""
    items = _get(f"{GITHUB_API}/repos/{_user()}/{repo}/contents/social")
    best = None
    for it in items if isinstance(items, list) else []:
        m = re.match(r"^(\d{4}-\d{2}-\d{2})-.+\.(png|jpe?g)$", it.get("name", ""), re.I)
        if not m or it.get("type") != "file":
            continue
        day = m.group(1)
        if since.strftime("%Y-%m-%d") <= day <= until.strftime("%Y-%m-%d") and (best is None or day >= best[0]):
            best = (day, it["path"])
    return best[1] if best else None


# ---------- 글쓰기 ----------

_RULES = """규칙:
- 한국어, 친근한 해요체. 혼자 바이브 코딩으로 앱과 게임을 만드는 1인 개발자 소피(@itssophie.dev)가 직접 쓰는 말투.
- 처음 보는 사람이 "오 재밌네" 하고 멈출 만한 것 위주. 개발 용어는 풀어서.
- 가격·매출·사용자 수·비밀번호·키·메일·서버 주소·회사나 다른 사람 이름은 쓰지 않는다.
- 주어진 정보(커밋·소개·만든 이유)에 없는 사실을 지어내지 않는다. 과장 금지.
- 출력은 JSON 하나만(설명·코드블록 없이)."""


def _ask(prompt: str) -> dict | None:
    import llm

    text = llm.complete(prompt, max_tokens=2500, temperature=0.7, purpose="social",
                        model=os.environ.get("SOCIAL_LLM_MODEL") or DEFAULT_MODEL)
    if not text:
        return None
    try:
        return json.loads(text[text.index("{"): text.rindex("}") + 1])
    except ValueError:
        return None


def _commit_block(groups: list[dict], per_project: int) -> str:
    parts = []
    for g in groups:
        msgs = "\n".join(f"  - {m.splitlines()[0][:200]}" for m in g["messages"][:per_project])
        head = f"[{g['name']}] {g['tagline']}" if g.get("tagline") else f"[{g['name']}]"
        parts.append(f"{head} — 커밋 {g['count']}개\n{msgs}")
    return "\n\n".join(parts)


def _cut(s: str, n: int) -> str:
    s = redact(" ".join(str(s or "").split()))
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


def _str(data: dict, key: str) -> str:
    v = data.get(key)
    return v.strip() if isinstance(v, str) else ""


def game_post(groups: list[dict], now: datetime) -> str | None:
    """Threads 게임 개발 일지(글만, 500자 이내). 게임 커밋이 없으면 None."""
    games = [g for g in groups if g["game"]][:2]
    if not games:
        return None
    data = _ask(f"""오늘({now.month}월 {now.day}일) 게임 개발 커밋이야. Threads에 올릴 "게임 개발 일지"를 써 줘.
350자 이내. 첫 줄은 "🎮 게임 개발 일지" 다음에 오늘 한 걸 한 문장으로. 게임 이름과 무슨 게임인지 짧게 넣어.
변화가 작아도 괜찮아 — 작은 진척도 솔직하고 재밌게. 마지막 줄은 #게임개발 #개발일지.
{_RULES}
형식: {{"text": "..."}}

{_commit_block(games, 12)}""") or {}
    text = _str(data, "text")
    if not text:  # Claude 키가 없거나 실패 → 커밋 제목으로 만든 기본 글
        lines = [f"🎮 게임 개발 일지 ({now.month}월 {now.day}일)", ""]
        for g in games:
            first = g["messages"][-1].splitlines()[0]  # GitHub는 최신순 → 맨 끝이 그날 첫 커밋
            more = f" 외 {g['count'] - 1}개" if g["count"] > 1 else ""
            lines.append(f"· {g['name']}" + (f" ({g['tagline']})" if g.get("tagline") else ""))
            lines.append(f"  → {_cut(first, 70)}{more}")
        lines += ["", "#게임개발 #개발일지"]
        text = "\n".join(lines)
    return redact(text)[:500]


def choose_angle(groups: list[dict], start: datetime, history: list[dict]) -> tuple[str, dict | None]:
    """이번 주 소재와 주인공 앱. history: 최근 에피소드들 [{angle, repo}] (최근 것이 앞)."""
    apps = [g for g in groups if g["app"] and not g["game"]]
    new = [g for g in apps if g.get("created") and g["created"][:10] >= start.strftime("%Y-%m-%d")]
    if new:
        return "new", new[0]
    total = sum(g["count"] for g in groups)
    last = history[0]["angle"] if history else None
    if total >= VIBE_MIN_COMMITS and last == "story":
        return "vibe", None
    # story 주인공: ① 만든 이유가 적힌 앱(이번 주 커밋 있는 쪽 먼저) ② 이번 주 작업한 앱. 최근 4번 안에 다룬 앱은 뒤로.
    # 이번 주 커밋이 없어도 만든 이유가 적힌 앱은 이야기할 수 있음(최근 커밋에만 묶이지 않게)
    recent = {(h.get("repo") or "").lower() for h in history[:4]}
    active = {g["repo"].lower(): g for g in apps}
    why_apps = [active.get(r) or {**app_info(r), "created": "", "count": 0, "messages": [], "days": 0}
                for r, a in APPS.items() if a.get("why") and not a.get("game") and a.get("app", True)]
    fresh = [g for g in sorted(why_apps, key=lambda g: -g["count"]) + apps if g["repo"].lower() not in recent]
    if fresh:
        return "story", fresh[0]
    if apps:
        return "story", apps[0]
    if total:
        return "vibe", None
    return "none", None


_SECTION = {  # 3장 제목, 첫·둘째 이야기 칸 이름
    "story": ("이 앱 이야기", "만든 이유", "이번 주엔"),
    "new": ("새로 시작한 앱", "왜 만드나요", "지금은 여기까지"),
    "vibe": ("이번 주 바이브 코딩", "이번 주 한 일", "왜 이렇게 많이?"),
}


def weekly_episode(groups: list[dict], start: datetime, end: datetime, history: list[dict] | None = None) -> dict | None:
    """주간 앱 에피소드. 소재(angle)에 따라 글을 쓰고, 그림은 넣지 않음(social.generate_devlog에서 받음)."""
    angle, g = choose_angle(groups, start, history or [])
    if angle == "none":
        return None
    span = f"{start.month}월 {start.day}일 ~ {end.month}월 {end.day}일"
    total = sum(x["count"] for x in groups)
    busy = [x for x in groups if x["app"]][:4]
    if angle == "vibe":
        brief = (f"이번 주 바이브 코딩 기록: 프로젝트 {len(groups)}개에 커밋 {total}번.\n"
                 "1장 훅은 이 숫자로 궁금하게, 이야기는 '이번 주 한 일'(앱별 한 줄) → '왜 이렇게 많이?'"
                 "(커밋에서 보이는 이유: 출시 준비, 피드백 반영 등).")
        block = _commit_block(groups[:5], 10)
    else:
        why = f'\n만든 이유(소피가 직접 쓴 키워드): "{g["why"]}"' if g.get("why") else ""
        started = f"\n저장소 만든 날: {g['created'][:10]}" if g.get("created") else ""
        brief = (f"{g['name']}: {g['tagline']}{why}{started}\n"
                 + ("이번 주에 새로 시작한 앱이야. '왜 만드나요' → '지금은 여기까지'로."
                    if angle == "new" else
                    "이번 주 커밋 정리가 아니라 이 앱 이야기야. 만든 이유가 중심이고, 이번 주 작업은 '이번 주엔'에서만 짧게."
                    " 꾸준히 만들고 있다는 느낌이 나게."))
        block = _commit_block([g], 25) if g["count"] else f"[{g['name']}] 이번 주 커밋 없음"
    sec = _SECTION[angle]
    data = _ask(f"""{span} 인스타 캐러셀(5장)과 Threads 글을 써 줘.
{brief}
- hook: 1장 큰 제목(24자 이내). 앱을 몰라도 멈춰서 넘겨 보고 싶게
- part1: '{sec[1]}' 칸(90자 이내)
- part2: '{sec[2]}' 칸(110자 이내)
- result: 4장 — 그래서 뭐가 좋아졌는지/앞으로(80자 이내)
- points: 핵심 2~3개(각 20자 이내)
- caption: 인스타 캡션(500자 이내). 첫 줄 훅 → 이야기 → "프로필 링크에서 만나 보세요" → #개발일지 #1인개발 #바이브코딩
- threads: Threads 글(350자 이내, 수다스럽게, 마지막 줄 #개발일지)
{_RULES}
형식: {{"hook":"","part1":"","part2":"","result":"","points":[""],"caption":"","threads":""}}

{block}""") or {}

    subjects = [m.splitlines()[0] for m in (g["messages"] if g else [])]
    if angle == "vibe":
        name, tagline, repo = "바이브 코딩 기록", f"이번 주 커밋 {total}번 · 프로젝트 {len(groups)}개", ""
        fb_hook = f"일주일에 커밋 {total}번, 무슨 일이?"
        fb1 = " / ".join(f"{x['name']} {x['count']}번" for x in busy)
        fb2 = ""
        fb_points = [_cut(f"{x['name']} — {x['tagline']}", 22) for x in busy[:3]]
    else:
        name, tagline, repo = g["name"], g["tagline"], g["repo"]
        fb_hook = (f"새로 만들기 시작한 앱, {name}" if angle == "new" else f"{name}, 왜 만들었냐면")
        fb1 = g.get("why") or tagline
        fb2 = subjects[-1] if subjects else ""
        fb_points = [_cut(s, 22) for s in subjects[:3]]
    points = [x for x in (data.get("points") or []) if isinstance(x, str) and x.strip()][:3]
    caption = _str(data, "caption") or "\n".join(
        [f"🛠 {fb_hook}", "", f"{name} — {tagline}", "", _cut(fb1, 200), "", "프로필 링크에서 만나 보세요.", "",
         "#개발일지 #1인개발 #바이브코딩"])
    threads = _str(data, "threads") or "\n".join([f"🛠 {fb_hook}", "", f"{name} — {tagline}", "", "#개발일지"])
    return {
        "angle": angle, "repo": repo, "name": name, "tagline": tagline,
        "icon": g.get("icon") if g else None, "shot": g.get("shot") if g else None,
        "count": g["count"] if g else total, "total": total, "span": span,
        "section": sec[0], "labels": [sec[1], sec[2]],
        "apps": [{"name": x["name"], "tagline": x["tagline"], "count": x["count"]} for x in busy],
        "others": [x["name"] for x in groups if x is not g and x["app"] and not x["game"]][:4] if g else [],
        "hook": _cut(_str(data, "hook") or fb_hook, 26),
        "part1": _cut(_str(data, "part1") or fb1, 110),
        "part2": _cut(_str(data, "part2") or fb2, 120),
        "result": _cut(_str(data, "result"), 90),
        "points": [_cut(x, 22) for x in points] or fb_points,
        "caption": redact(caption)[:2000],
        "threads": redact(threads)[:500],
    }


def window(now: datetime, days: int) -> tuple[datetime, datetime]:
    return now - timedelta(days=days), now
