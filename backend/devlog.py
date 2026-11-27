"""만드는 과정 공개(build in public): GitHub 커밋 → 개발 일지 글·주간 에피소드.

- 매일: 지난 24시간 커밋이 있는 날만 Threads 한 줄 일지(글만). 앱마다 "이름 — 한 줄 소개"로 시작해서
  처음 보는 사람도 무슨 앱인지 알게.
- 주 1회(SOCIAL_EPISODE_WEEKDAY, 기본 일요일): **앱 하나에 집중**한 에피소드. 그 주 커밋이 가장 많은 앱을 골라
  훅 → 이 앱은요(소개+대표 화면) → 이번 주 바꾼 것 → 결과 → 써 보기, 5장 캐러셀 + Threads 글.
  화면은 각 저장소에 올라가 있는 스토어 스크린샷·아이콘(GitHub raw)을 쓰고, 그 주 캡처가 있으면 우선 씀:
  저장소의 social/ 폴더에 `YYYY-MM-DD-아무이름.png|jpg`로 넣어 두면 그 주 에피소드의 "바꾼 것" 장에 들어감.
소재는 **공개 저장소의 커밋 메시지만** 쓴다(Claude Code 대화 기록은 키·개인정보가 섞일 수 있어 안 씀).
글은 Claude가 쓰고(키 ANTHROPIC_KEY_SOCIAL, 없으면 커밋 제목으로 만든 기본 글), 올리기 전에
social.py의 미리보기·승인을 그대로 거친다.

환경변수:
  SOCIAL_GITHUB_USER       기본 LetsBeLikeSophie
  SOCIAL_DEVLOG_EXCLUDE    빼고 싶은 저장소 이름(쉼표). 예: "Appjupjup,ripe-weekly"
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

# 저장소 → 보여 줄 이름·한 줄 소개·그림(저장소 안 경로). app=False면 앱이 아니라 주간 주인공으로는 안 고름.
APPS = {
    "issue-pop": {"name": "이슈팝", "tagline": "여러 언론사 기사를 이슈별로 묶어 오늘 가장 많이 보도된 뉴스를 보여 주는 앱",
                  "icon": "app/assets/icon/app_icon_512_store.png",
                  "shot": "app/assets/screenshots/phone/Screenshot_20261003_155415.jpg"},
    "dailycut": {"name": "데일리컷", "tagline": "혜택·청약·물가 같은 생활 정보를 매일 카드로 모아 보여 주는 앱",
                 "icon": "store/icon-512.png", "shot": "store/screenshots/1_benefit.png"},
    "mehh": {"name": "Mehh", "tagline": "귀찮아서 못 한 사진 정리, 지울 만한 사진을 이유와 함께 골라 주는 앱",
             "icon": "docs/store/icon-512.png", "shot": "docs/store/screenshots-ko/1-home.png"},
    "cortex": {"name": "Cortex", "tagline": "어디서든 공유 버튼 하나로 저장하고 검색 한 번으로 다시 찾는 아카이브 앱"},
    "appjupjup": {"name": "앱줍줍", "tagline": "내 앱 올리고 남의 앱 줍줍, 한 줄 피드백을 주고받는 앱 품앗이"},
    "subwayrush": {"name": "지옥철", "tagline": "출근길 지하철 인파를 뚫고 지각 없이 환승역까지 가는 게임"},
    "camtrip": {"name": "CamTrip", "tagline": "메뉴판·영수증을 찍으면 폰에서 바로 번역하고 여행 경비로 정리해 주는 앱",
                "icon": "docs/store/icon-512.png"},
    "ripe-weekly": {"name": "Ripe Weekly", "tagline": "궁금한 분야를 적으면 AI가 매주 뜨는 것만 3분 리포트로 보내 주는 앱"},
    "tablelink": {"name": "TableLink", "tagline": "조건만 말하면 여러 테이블을 알아서 이어 고객 목록을 뽑아 주는 도구"},
    "my-little-sessions": {"name": "My Little Sessions",
                           "tagline": "Claude Code 작업 창을 픽셀아트 사무실 직원으로 보여 주는 데스크톱 앱",
                           "shot": "docs/screenshot-ko.png"},
    "sophies-office-hours": {"name": "Sophie's Office Hours", "tagline": "AI로 앱 만들다 막힌 비전공자를 위한 디버깅 상담소"},
    "portfolio": {"name": "포트폴리오 사이트", "tagline": "소피앱스의 앱들을 모아 둔 사이트", "app": False},
}


def app_info(repo: str) -> dict:
    a = APPS.get(repo.lower(), {})
    return {"repo": repo, "name": a.get("name", repo), "tagline": a.get("tagline", ""),
            "icon": a.get("icon"), "shot": a.get("shot"), "app": a.get("app", True)}


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
    """since~until 사이 공개 저장소 커밋(머지 제외, 빼는 목록 제외)."""
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
                        "message": _clean_message(msg)})
    return out


def group_by_project(commits: list[dict]) -> list[dict]:
    """[{repo, name, tagline, count, messages}] 커밋 많은 순."""
    groups: dict[str, list[str]] = {}
    for c in commits:
        groups.setdefault(c["repo"], []).append(c["message"])
    out = [{**app_info(r), "count": len(m), "messages": m} for r, m in groups.items()]
    return sorted(out, key=lambda g: -g["count"])


def pick_focus(groups: list[dict]) -> dict | None:
    """주간 에피소드 주인공: 앱(사이트 제외) 중 커밋이 가장 많은 것. 앱이 하나도 없으면 아무거나 1등."""
    apps = [g for g in groups if g["app"]]
    return (apps or groups or [None])[0]


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
- 한국어, 친근한 해요체. 1인 개발자 소피(@itssophie.dev)가 직접 쓰는 개발 일지 말투.
- 앱을 처음 보는 사람도 이해하게. 개발 용어는 풀어서, 앱을 쓰는 사람 입장에서 뭐가 달라졌는지가 보이게.
- 가격·매출·사용자 수·비밀번호·키·메일·서버 주소·회사나 다른 사람 이름은 쓰지 않는다.
- 커밋에 없는 사실을 지어내지 않는다. 과장 금지.
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


def daily_post(groups: list[dict], now: datetime) -> str:
    """Threads 한 줄 개발 일지(글만, 500자 이내). 앱마다 '이름 — 한 줄 소개'가 먼저 나오게."""
    groups = groups[:3]
    data = _ask(f"""오늘({now.month}월 {now.day}일) 한 작업의 커밋 메시지야. Threads에 올릴 짧은 개발 일지를 써 줘.
350자 이내. 앱마다 "앱 이름(무슨 앱인지 짧게) — 오늘 바꾼 것" 한두 줄로. 대괄호 옆 소개를 참고해서
처음 보는 사람도 무슨 앱인지 알게. 마지막 줄은 #개발일지 하나만.
{_RULES}
형식: {{"text": "..."}}

{_commit_block(groups, 12)}""")
    if data and isinstance(data.get("text"), str) and data["text"].strip():
        text = redact(data["text"].strip())
    else:  # Claude 키가 없거나 실패 → 커밋 제목으로 만든 기본 글
        lines = [f"🛠 {now.month}월 {now.day}일 개발 일지", ""]
        for g in groups:
            first = g["messages"][-1].splitlines()[0]  # GitHub는 최신순 → 맨 끝이 그날 첫 커밋
            more = f" 외 {g['count'] - 1}개" if g["count"] > 1 else ""
            lines.append(f"· {g['name']}" + (f" ({g['tagline']})" if g.get("tagline") else ""))
            lines.append(f"  → {_cut(first, 70)}{more}")
        lines += ["", "#개발일지"]
        text = "\n".join(lines)
    return text[:500]


def weekly_episode(groups: list[dict], start: datetime, end: datetime) -> dict | None:
    """앱 하나에 집중한 주간 에피소드. 그림은 넣지 않고(generate에서 따로 받음) 글과 앱 정보만."""
    g = pick_focus(groups)
    if g is None:
        return None
    span = f"{start.month}월 {start.day}일 ~ {end.month}월 {end.day}일"
    others = [o["name"] for o in groups if o is not g][:4]
    data = _ask(f"""이번 주({span}) {g['name']} 커밋 메시지야. {g['name']}은(는) "{g['tagline']}"이야.
이 앱 하나에 집중한 "이번 주 만든 것" 인스타 캐러셀(5장)과 Threads 글을 써 줘.
- hook: 1장 큰 제목. 앱을 몰라도 궁금해지는 문제 한 줄(24자 이내, 물음표나 말줄임 OK)
- problem: 무엇이 불편했는지(80자 이내, 쓰는 사람 입장)
- change: 그래서 어떻게 바꿨는지(100자 이내)
- result: 바꾸고 나니 뭐가 좋아졌는지 + 배운 점(80자 이내)
- points: 바뀐 점 2~3개(각 20자 이내)
- caption: 인스타 캡션(500자 이내). 첫 줄 훅 → 무슨 앱인지 한 줄 → 바꾼 이야기 → "프로필 링크에서 만나 보세요"
  → 해시태그 #개발일지 #1인개발 #buildinpublic
- threads: Threads 글(350자 이내, 캡션보다 짧고 수다스럽게, 마지막 줄 #개발일지)
{_RULES}
형식: {{"hook":"","problem":"","change":"","result":"","points":[""],"caption":"","threads":""}}

{_commit_block([g], 30)}""")
    data = data or {}
    subjects = [m.splitlines()[0] for m in g["messages"]]
    points = [x for x in (data.get("points") or []) if isinstance(x, str) and x.strip()][:3]
    name = g["name"]
    caption = data.get("caption") or "\n".join([
        f"🛠 이번 주 {name}에서 바꾼 것", "", f"{name} — {g['tagline']}", ""]
        + [f"· {_cut(s, 60)}" for s in subjects[:5]]
        + ["", "프로필 링크에서 만나 보세요.", "", "#개발일지 #1인개발 #buildinpublic"])
    threads = data.get("threads") or "\n".join([
        f"🛠 이번 주 {name} ({g['tagline']})", ""] + [f"· {_cut(s, 60)}" for s in subjects[:3]] + ["", "#개발일지"])
    return {
        "repo": g["repo"], "name": name, "tagline": g["tagline"], "icon": g.get("icon"), "shot": g.get("shot"),
        "count": g["count"], "span": span, "others": others,
        "hook": _cut(data.get("hook") or f"이번 주 {name}, 뭐가 바뀌었을까?", 26),
        "problem": _cut(data.get("problem") or "", 90),
        "change": _cut(data.get("change") or (subjects[-1] if subjects else ""), 110),
        "result": _cut(data.get("result") or "", 90),
        "points": [_cut(x, 22) for x in points] or [_cut(s, 22) for s in subjects[:3]],
        "caption": redact(caption.strip())[:2000],
        "threads": redact(threads.strip())[:500],
    }


def window(now: datetime, days: int) -> tuple[datetime, datetime]:
    return now - timedelta(days=days), now
