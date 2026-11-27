"""만드는 과정 공개(build in public): GitHub 커밋 → 개발 일지 글·주간 에피소드.

- 매일: 지난 24시간 커밋이 있는 날만 Threads 한 줄 일지(글만).
- 주 1회(SOCIAL_EPISODE_WEEKDAY, 기본 일요일): 한 주 커밋을 프로젝트별로 묶어 "이번 주 만든 것"
  → 인스타 캐러셀(표지 + 프로젝트별 1장) + Threads 글(표지 이미지).
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

import json
import os
import re
from datetime import datetime, timedelta

import requests

GITHUB_API = "https://api.github.com"
DEFAULT_MODEL = "claude-sonnet-5-5"
MAX_PROJECTS = 5

# 저장소 이름 → 사람들에게 보여 줄 이름(포트폴리오 표기). 없으면 저장소 이름 그대로
APP_NAMES = {
    "issue-pop": "이슈팝",
    "dailycut": "데일리컷",
    "subwayrush": "지옥철",
    "appjupjup": "앱줍줍",
    "ripe-weekly": "Ripe Weekly",
    "mehh": "Mehh",
    "cortex": "Cortex",
    "camtrip": "CamTrip",
    "tablelink": "TableLink",
    "my-little-sessions": "My Little Sessions",
    "my-little-mods": "My Little Mods",
    "sophies-office-hours": "Sophie's Office Hours",
    "sophie-voice-mouse": "Sophie Voice Mouse",
    "portfolio": "포트폴리오 사이트",
}


def app_name(repo: str) -> str:
    return APP_NAMES.get(repo.lower(), repo)


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

def _headers() -> dict:
    h = {"Accept": "application/vnd.github+json", "User-Agent": "issuepop-social"}
    tok = os.environ.get("GITHUB_TOKEN")
    if tok:
        h["Authorization"] = f"Bearer {tok}"
    return h


def _get(url: str, params: dict) -> list:
    r = requests.get(url, params=params, headers=_headers(), timeout=30)
    if r.status_code == 409:  # 빈 저장소
        return []
    r.raise_for_status()
    return r.json()


def fetch_commits(since: datetime, until: datetime) -> list[dict]:
    """since~until 사이 공개 저장소 커밋(머지 제외, 빼는 목록 제외). 최신순이 아니라 저장소별로 모임."""
    user = os.environ.get("SOCIAL_GITHUB_USER") or "LetsBeLikeSophie"
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
    """[{repo, name, count, messages}] 커밋 많은 순."""
    groups: dict[str, list[str]] = {}
    for c in commits:
        groups.setdefault(c["repo"], []).append(c["message"])
    out = [{"repo": r, "name": app_name(r), "count": len(m), "messages": m} for r, m in groups.items()]
    return sorted(out, key=lambda g: -g["count"])


# ---------- 글쓰기 ----------

_RULES = """규칙:
- 한국어, 친근한 해요체. 1인 개발자 소피(@itssophie.dev)가 직접 쓰는 개발 일지 말투.
- 개발 용어는 풀어서. 무엇이 불편했는지 → 어떻게 바꿨는지 → 그래서 뭐가 좋아졌는지가 보이게.
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
        parts.append(f"[{g['name']}] 커밋 {g['count']}개\n{msgs}")
    return "\n\n".join(parts)


def _cut(s: str, n: int) -> str:
    s = redact(" ".join(str(s or "").split()))
    return s if len(s) <= n else s[: n - 1].rstrip() + "…"


def daily_post(groups: list[dict], now: datetime) -> str:
    """Threads 한 줄 개발 일지(글만, 500자 이내)."""
    groups = groups[:3]
    data = _ask(f"""오늘({now.month}월 {now.day}일) 한 작업의 커밋 메시지야. Threads에 올릴 짧은 개발 일지를 써 줘.
3~6줄, 350자 이내. 첫 줄은 오늘 한 일을 한 문장으로. 프로젝트 이름을 넣어. 마지막 줄은 #개발일지 하나만.
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
            lines.append(f"· {g['name']}: {_cut(first, 70)}{more}")
        lines += ["", "#개발일지"]
        text = "\n".join(lines)
    return text[:500]


def weekly_episode(groups: list[dict], start: datetime, end: datetime) -> dict:
    """주간 에피소드: {title, intro, projects:[{repo,name,count,headline,story,points}], caption, threads}."""
    groups = groups[:MAX_PROJECTS]
    total = sum(g["count"] for g in groups)
    span = f"{start.month}월 {start.day}일 ~ {end.month}월 {end.day}일"
    data = _ask(f"""이번 주({span}) 커밋 메시지를 프로젝트별로 모았어. "이번 주 만든 것" 에피소드로 정리해 줘.
인스타 캐러셀(표지 1장 + 프로젝트별 1장)과 Threads 글에 쓸 거야.
- title: 이번 주를 한마디로(20자 이내, 궁금해지게)
- intro: 표지 부제(45자 이내)
- projects: 아래 프로젝트마다 하나씩, 같은 순서로. repo는 대괄호 안 이름 그대로.
  headline(18자 이내), story(100자 이내, 문제→해결), points(바뀐 점 2~3개, 각 22자 이내)
- caption: 인스타 캡션(600자 이내, 첫 줄이 훅, 프로젝트별 한두 줄, 끝에 해시태그 #개발일지 #1인개발 #buildinpublic)
- threads: Threads 글(400자 이내, 캡션보다 짧고 수다스럽게, 해시태그는 #개발일지 하나)
{_RULES}
형식: {{"title":"","intro":"","projects":[{{"repo":"","headline":"","story":"","points":[""]}}],"caption":"","threads":""}}

{_commit_block(groups, 25)}""")
    by_name = {}
    if data and isinstance(data.get("projects"), list):
        for p in data["projects"]:
            if isinstance(p, dict):
                by_name[str(p.get("repo", "")).strip()] = p
    projects = []
    for g in groups:
        p = by_name.get(g["name"]) or by_name.get(g["repo"]) or {}
        subjects = [m.splitlines()[0] for m in g["messages"]]
        points = [x for x in (p.get("points") or []) if isinstance(x, str) and x.strip()][:3]
        projects.append({
            "repo": g["repo"],
            "name": g["name"],
            "count": g["count"],
            "headline": _cut(p.get("headline") or subjects[-1], 24),
            "story": _cut(p.get("story") or f"이번 주 커밋 {g['count']}개.", 120),
            "points": [_cut(x, 28) for x in points] or [_cut(s, 28) for s in subjects[:3]],
        })
    names = ", ".join(p["name"] for p in projects)
    caption = data.get("caption") if data else None
    threads = data.get("threads") if data else None
    if not caption:
        caption = "\n".join([f"🛠 이번 주 만든 것 ({span})", ""]
                            + [f"· {p['name']} — {p['headline']}" for p in projects]
                            + ["", "만드는 과정을 매주 정리해서 올려요.", "", "#개발일지 #1인개발 #buildinpublic"])
    if not threads:
        threads = "\n".join([f"🛠 이번 주 만든 것 ({span})", ""]
                            + [f"· {p['name']}: {p['headline']}" for p in projects] + ["", "#개발일지"])
    return {
        "title": _cut((data or {}).get("title") or "이번 주 만든 것", 22),
        "intro": _cut((data or {}).get("intro") or f"{names}", 48),
        "span": span,
        "total": total,
        "projects": projects,
        "caption": redact(caption.strip())[:2000],
        "threads": redact(threads.strip())[:500],
    }


def window(now: datetime, days: int) -> tuple[datetime, datetime]:
    return now - timedelta(days=days), now
