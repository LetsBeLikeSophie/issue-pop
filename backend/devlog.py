"""만드는 과정 공개(build in public): GitHub 커밋 → 게임 개발 일지·앱 에피소드. **전부 한 장, 짧게**
(2026-11-27 피드백: 장수·글이 많으면 3초 안에 넘김).

- 매일(Threads): **게임 개발 일지 = 화면 위주**. 게임 저장소(APPS의 game=True, SOCIAL_GAME_REPOS로 추가)의
  social/ 폴더에 새 캡처(`YYYY-MM-DD-이름.png|jpg`)가 있는 날만, 바로 앞 캡처와 전→후로 한 장 + 짧은 글.
  화면이 안 바뀐 날은 커밋이 있어도 안 올림. 이미 올린 캡처는 다시 안 씀.
- 주 1회(인스타 피드 + Threads, SOCIAL_EPISODE_WEEKDAY 기본 일요일): **앱 에피소드 한 장**, 소재에 따라 형식이 다름
    new    이번 주 새로 만든 앱 저장소 → C 개발 일지 메모(3~4줄)
    vibe   바이브 코딩 기록(커밋 20개 이상 + 직전이 story) → D 숫자 한 방
    story  앱 이야기(APPS의 why = 만든 이유 중심, 이번 주 커밋 없어도 가능) → A 앱 색 배경 + 큰 글씨 두 마디
  앱마다 배경색이 다름(APPS의 color, 없으면 앱 아이콘에서 뽑음). 최근 다룬 앱·같은 소재는 피함.
소재는 **공개 저장소의 커밋 메시지·캡처와 여기 적어 둔 앱 소개뿐**(Claude Code 대화 기록은 키·개인정보가 섞일 수
있어 안 씀). 글은 Claude(키 ANTHROPIC_KEY_SOCIAL, 없으면 기본 글), 올리기 전 social.py의 미리보기·승인.

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

# 저장소 → 보여 줄 이름·한 줄 소개·만든 이유(why, 에피소드 이야기의 중심)·그림 경로·앱 색(color, 없으면 아이콘에서)·게임 여부.
# app=False: 앱이 아니라 에피소드 주인공으로 안 고름. game=True: 인스타 에피소드 대신 Threads 게임 개발 일지로.
APPS = {
    "issue-pop": {"name": "이슈팝", "color": (23, 53, 107), "tagline": "여러 언론사 기사를 이슈별로 묶어 오늘 가장 많이 보도된 뉴스를 보여 주는 앱",
                  "icon": "app/assets/icon/app_icon_512_store.png",
                  "shot": "app/assets/screenshots/phone/Screenshot_20261003_155415.jpg"},
    "dailycut": {"name": "데일리컷", "tagline": "혜택·청약·물가 같은 생활 정보를 매일 카드로 모아 보여 주는 앱",
                 "icon": "store/icon-512.png", "shot": "store/screenshots/1_benefit.png"},
    "mehh": {"name": "Mehh", "tagline": "귀찮아서 못 한 사진 정리, 지울 만한 사진을 이유와 함께 골라 주는 앱",
             "icon": "docs/store/icon-512.png", "shot": "docs/store/screenshots-ko/1-home.png"},
    "cortex": {"name": "Cortex", "tagline": "어디서든 공유 버튼 하나로 저장하고 검색 한 번으로 다시 찾는 아카이브 앱"},
    "appjupjup": {"name": "앱줍줍", "color": (242, 106, 27), "tagline": "내 앱 올리고 남의 앱 줍줍, 한 줄 피드백을 주고받는 앱 품앗이",
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
            "icon": a.get("icon"), "shot": a.get("shot"), "color": a.get("color"), "app": a.get("app", True),
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


def list_captures(repo: str) -> list[tuple[str, str]]:
    """저장소 social/ 폴더의 캡처 [(YYYY-MM-DD, 경로)] 날짜순. 파일 이름은 `YYYY-MM-DD-아무이름.png|jpg`."""
    items = _get(f"{GITHUB_API}/repos/{_user()}/{repo}/contents/social")
    out = []
    for it in items if isinstance(items, list) else []:
        m = re.match(r"^(\d{4}-\d{2}-\d{2})-.+\.(png|jpe?g)$", it.get("name", ""), re.I)
        if m and it.get("type") == "file":
            out.append((m.group(1), it["path"]))
    return sorted(out)


def week_capture(repo: str, since: datetime, until: datetime) -> str | None:
    """이번 주 날짜 캡처 중 가장 최근 것의 경로."""
    inside = [p for day, p in list_captures(repo)
              if since.strftime("%Y-%m-%d") <= day <= until.strftime("%Y-%m-%d")]
    return inside[-1] if inside else None


# ---------- 글쓰기 ----------

_RULES = """규칙:
- 한국어. 혼자 바이브 코딩으로 앱과 게임을 만드는 1인 개발자 소피(@itssophie.dev)가 직접 쓰는 말투.
- **짧게.** 3초 안에 읽히고 "오?" 하고 멈추게. 설명하지 말고 궁금하게.
- 가격·매출·사용자 수·비밀번호·키·메일·서버 주소·회사나 다른 사람 이름은 쓰지 않는다.
- 주어진 정보(커밋·소개·만든 이유)에 없는 사실을 지어내지 않는다. 과장 금지.
- 출력은 JSON 하나만(설명·코드블록 없이)."""


# Threads 글은 소피가 실제로 쓰는 말투로(2026-11-27 @itssophie.dev 글·답글을 읽고 정리). 인스타 캡션은 그대로 존댓말.
THREADS_TONE = """Threads 글 말투(소피가 직접 쓰는 것처럼):
- 반말, 친구한테 말하듯. 줄 짧게 끊어서 2~4줄.
- 귀여운 소리 나는 맞춤법 살짝: "만들구 이쏘", "귀차나서", "~했지렁", "~자너", "딱조은", "마니".
- 글자 하나를 자음·모음으로 쪼개 쓰기(한 글에 한 번쯤): "ㄴ ㅏ를 위한", "창업하시ㄱ ㅓ든", "했ㅈ ㅣ렁".
- 자기 디스 농담 가끔: 토큰 녹이는 중💸, 휴먼이 병목, 반나절 걸려 겨우 이만큼.
- 끝은 팔로워한테 가볍게 묻거나 부탁: "다들 어떤 거 해?", "어때 보여?", "잘 부탁해".
- 이모지는 👾 💜 를 꼭 섞고, 필요하면 💸 💦 🔥 조금. 해시태그는 맨 끝 하나만.
- 예(실제 소피 글): "불타는 금요일 반나절 걸려 자동화 중인데 / 한게 겨우 이메일 뚫고 이런것 뿌니네 / 다들 어떤걸 자동화 하구 있으까"
  "무료로 만들어 놓은 뉴스앱 매달 -6천원💸", "제 피씨는 클로드가 장악ㅋㅋㅋ 휴먼이 병목"
"""


def _ask(prompt: str) -> dict | None:
    import llm

    text = llm.complete(prompt, max_tokens=1500, temperature=0.8, purpose="social",
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


# ---------- 게임 개발 일지(화면 위주) ----------

def game_visual(groups: list[dict], since: datetime, until: datetime, now: datetime,
                used: set | None = None) -> dict | None:
    """게임 저장소 social/에 이 기간 새 캡처가 있으면 {repo, name, tagline, before, after, text}.
    화면이 안 바뀐 날(캡처 없음)은 커밋이 있어도 None — 게임 일지는 보이는 변화만 올림.
    캡처 이름엔 날짜만 있어서 하루 창이 겹치므로, 이미 올린 캡처(used: "저장소/경로")는 뺌."""
    used = used or set()
    for g in [g for g in groups if g["game"]]:
        caps = list_captures(g["repo"])
        new = [(d, p) for d, p in caps if since.strftime("%Y-%m-%d") <= d <= until.strftime("%Y-%m-%d")
               and f"{g['repo']}/{p}" not in used]
        if not new:
            continue
        after = new[-1]
        older = [c for c in caps if c < after and c[0] < after[0]] or [c for c in caps if c < after]
        before = older[-1][1] if older else None
        data = _ask(f"""게임 "{g['name']}"({g['tagline']})의 오늘 화면이 바뀌었어. Threads에 이미지와 같이 올릴 짧은 글.
화면(그래픽·시야·연출)에서 뭐가 달라졌는지만, 3줄 이내 70자 이내. 마지막 줄 #게임개발
캡처 파일 이름: 전={before or '없음'}, 후={after[1]}
{THREADS_TONE}
{_RULES}
형식: {{"text": "..."}}

{_commit_block([g], 15)}""") or {}
        text = _str(data, "text") or f"{g['name']} 오늘 화면 바뀌었ㅈ ㅣ렁👾\n전 → 후 어때 보여?💜\n#게임개발"
        return {"repo": g["repo"], "name": g["name"], "tagline": g["tagline"], "color": g.get("color"),
                "before": before, "after": after[1], "text": redact(text)[:300]}
    return None


# ---------- 앱 에피소드(한 장) ----------

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


def weekly_episode(groups: list[dict], start: datetime, end: datetime, history: list[dict] | None = None) -> dict | None:
    """주간 앱 에피소드 한 장. angle: story(A 한 줄 임팩트) / new(C 개발 일지 메모) / vibe(D 숫자 한 방)."""
    angle, g = choose_angle(groups, start, history or [])
    if angle == "none":
        return None
    total = sum(x["count"] for x in groups)
    n_projects = len([x for x in groups if x["app"]])
    tail = """- caption: 인스타 캡션(250자 이내). 첫 줄 한마디 → 한두 줄 → "프로필 링크에서" → #개발일지 #1인개발 #바이브코딩
- threads: Threads 글(150자 이내, 이미지와 같이 올라감, 마지막 줄 #개발일지). 아래 Threads 말투로.
""" + THREADS_TONE
    if angle == "vibe":
        data = _ask(f"""이번 주 바이브 코딩 기록: 프로젝트 {n_projects}개에 커밋 {total}번. 이미지에는 큰 숫자 {total}과 두 줄만 들어가.
- line1, line2: 숫자 아래 두 줄(각 10자 이내). 예: "앱 4개를 동시에" / "굴리면 생기는 일"
{tail}
{_RULES}
형식: {{"line1":"","line2":"","caption":"","threads":""}}

{_commit_block(groups[:5], 8)}""") or {}
        busy = [x for x in groups if x["app"]][:4]
        ep = {"name": "바이브 코딩 기록", "tagline": "", "repo": "", "number": total, "label": "이번 주 커밋",
              "line1": _cut(_str(data, "line1") or f"앱 {n_projects}개를 동시에", 14),
              "line2": _cut(_str(data, "line2") or "굴리면 생기는 일", 14),
              "apps": [{"name": x["name"], "count": x["count"]} for x in busy]}
        fb = f"이번 주 커밋 {total}번 · 프로젝트 {n_projects}개\n\n" + " / ".join(f"{x['name']} {x['count']}번" for x in busy)
        th = (f"이번 주 커밋 {total}번 찍음👾\nㄴ ㅏ 앱 {n_projects}개 동시에 굴리는 중… 토큰 녹는 소리💸\n"
              f"다들 이번 주 뭐 만들었어?💜")
    elif angle == "new":
        why = f'\n만든 이유: "{g["why"]}"' if g.get("why") else ""
        data = _ask(f"""새로 만들기 시작한 앱 "{g['name']}": {g['tagline']}{why}
이미지는 손으로 쓴 개발 일지 메모 한 장이야. 3~4줄, 각 12자 이내. 앞줄은 계기, 마지막 두 줄은 그래서 만든 것.
예: "앱이 계속 생기는데" / "써 줄 사람이 없었다." / "그래서 서로 써 주는" / "곳을 만들었다."
- lines: 위 메모 줄들(목록)
{tail}
{_RULES}
형식: {{"lines":[""],"caption":"","threads":""}}

{_commit_block([g], 15)}""") or {}
        lines = [_cut(x, 14) for x in (data.get("lines") or []) if isinstance(x, str) and x.strip()][:4]
        ep = {"lines": lines or [f"새로 만들기 시작했다.", _cut(g["tagline"], 14)],
              "date_label": f"{end.month}월 {end.day}일 · 바이브 코딩 중"}
        fb = f"새로 만들기 시작한 앱, {g['name']}\n\n{g['tagline']}"
        th = f"새 앱 만들기 시작했ㅈ ㅣ렁👾\n{g['name']} — {g['tagline']}\n잘 부탁해💜"
    else:
        why = f'\n만든 이유(소피가 직접 쓴 키워드): "{g["why"]}"' if g.get("why") else ""
        data = _ask(f"""앱 "{g['name']}": {g['tagline']}{why}
이미지는 앱 색 배경에 큰 글씨 두 마디뿐이야.
- line1: 누구나 고개를 끄덕일 한마디(12자 이내). 예: "앱 홍보 사이트, 많죠."
- line2: 뒤집는 한마디(12자 이내). 예: "근데 이건 홍보가 아니에요."
{tail}
{_RULES}
형식: {{"line1":"","line2":"","caption":"","threads":""}}

{_commit_block([g], 15) if g["count"] else ""}""") or {}
        ep = {"line1": _cut(_str(data, "line1") or g["name"], 16),
              "line2": _cut(_str(data, "line2") or g["tagline"], 28)}
        fb = f"{g['name']} — {g['tagline']}" + (f"\n\n{g['why']}" if g.get("why") else "")
        th = f"{g['name']} 왜 만들었냐면👾\n{g.get('why') or g['tagline']}\n그래서 ㄴ ㅏ 만들구 이쏘💜"
    if g is not None:
        ep.update(name=g["name"], tagline=g["tagline"], repo=g["repo"], icon=g.get("icon"), color=g.get("color"))
    caption = _str(data, "caption") or f"{fb}\n\n프로필 링크에서 만나 보세요.\n\n#개발일지 #1인개발 #바이브코딩"
    threads = _str(data, "threads") or f"{th}\n#개발일지"
    others = [x["name"] for x in groups if x is not g and x["app"] and not x["game"]][:4] if g else []
    return {**ep, "angle": angle, "count": g["count"] if g else total, "total": total,
            "span": f"{start.month}월 {start.day}일 ~ {end.month}월 {end.day}일", "others": others,
            "caption": redact(caption)[:1000], "threads": redact(threads)[:400]}


def window(now: datetime, days: int) -> tuple[datetime, datetime]:
    return now - timedelta(days=days), now
