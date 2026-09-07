# -*- coding: utf-8 -*-
"""
FastAPI 엔드포인트 (v0).

와이어프레임이 필요로 하는 두 화면을 그대로 반영함:
  - Main.dc.html "오늘 많이 언급된 키워드" → GET /trending
  - IssueDetail.dc.html "매체별 보도 분포 + 전체 관련기사" → GET /issues/{id}

아키텍처: 요청마다 클러스터링을 다시 돌리지 않음. 이슈 임베딩 계산이
461건 기준 20~80초 걸려서(backend/README.md 참고) 매 요청마다 하면
느리고 서버도 무거워짐. 대신:
  1. 서버 시작 시 한 번 파이프라인을 돌려서 캐시를 채움.
  2. 그 뒤로는 백그라운드 태스크가 REFRESH_INTERVAL_SECONDS마다 한 번씩
     다시 돌려서 캐시를 갱신함.
  3. API는 항상 이 캐시(딕셔너리)만 읽어서 응답함 — 그래서 응답이 빠름.

이 구조 덕분에 서버 스펙 요구사항이 낮아짐(요청 처리 자체는 가벼움,
무거운 연산은 백그라운드에서 가끔만 일어남) — 인프라 선택(라즈베리파이
vs 클라우드 VM)과 무관하게 잘 작동하는 이유이기도 함.

실행: uvicorn api:app --reload --port 8000
"""

from __future__ import annotations

import asyncio
import hashlib
import html
import json
import re
import secrets
import time
from collections import Counter
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from zoneinfo import ZoneInfo

import bcrypt
import requests
from fastapi import FastAPI, Header, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from pydantic import BaseModel
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

import db
import stocks
from pipeline import run

REFRESH_INTERVAL_SECONDS = 30 * 60  # 30분마다 재수집+재클러스터링
DIGEST_CHECK_INTERVAL_SECONDS = 5 * 60  # 다이제스트 대상 확인 주기
DIGEST_DEDUPE_WINDOW_SECONDS = 50 * 60  # 이 안에 이미 보냈으면 재발송 안 함
KST = ZoneInfo("Asia/Seoul")

# 홈 화면 "오늘 날씨" 카드용. 기상청 공식 API는 계정 가입 + 키 발급이
# 필요해서(FCM/LLM처럼 사용자가 직접 해야 하는 일) 대신 키 없이 바로 쓸
# 수 있는 Open-Meteo(무료, 비상업적 이용 시 인증 불필요)로 씀. 좌표는
# 서울 고정 — 나중에 위치 기능이 생기면 그때 사용자 위치로 바꾸면 됨.
WEATHER_LAT, WEATHER_LON = 37.5665, 126.9780

_cache: dict[str, dict] = {}
_last_refresh: float | None = None
_last_error: str | None = None
_refresh_lock = asyncio.Lock()
_weather_cache: dict | None = None
_stock_news_cache: dict[str, list[dict]] = {}  # 티커 → 최신 뉴스(stocks.py 참고)


def _make_id(cluster: dict) -> str:
    """클러스터 안 기사 링크(없으면 제목)를 정렬해서 해시 — 같은 기사
    묶음이면 재수집 후에도 같은 id가 나오게(완전 보장은 아니지만 v0로 충분)."""
    keys = sorted(a.get("link") or a["title"] for a in cluster["articles"])
    return hashlib.sha1("|".join(keys).encode("utf-8")).hexdigest()[:12]


def _fetch_weather(lat: float | None = None, lon: float | None = None) -> dict | None:
    """어제/오늘/내일 최고·최저기온만 받아옴. "평년 대비"나 "폭염특보
    N일째" 같은 문구는 일부러 안 넣음 — 그건 기상청이 여러 조건을 보고
    공식적으로 발효하는 거라, 기온만 보고 우리가 흉내 내서 표시하면
    실제 특보가 아닌데 특보처럼 보이는 문제가 생길 수 있음(안전 관련
    정보라 더 조심스럽게 감). 실측 가능한 숫자(기온)만 정직하게 보여줌.

    2026-08-26: lat/lon을 받으면 그 좌표로, 안 주면 서울 기본값으로.
    사용자가 위치 권한에 동의하면 기기 좌표를 넘겨받아 씀(앱 쪽에서
    처리, 동의 안 하면 그냥 기본값 씀)."""
    lat = lat if lat is not None else WEATHER_LAT
    lon = lon if lon is not None else WEATHER_LON
    try:
        res = requests.get(
            "https://api.open-meteo.com/v1/forecast",
            params={
                "latitude": lat,
                "longitude": lon,
                "daily": "temperature_2m_max,temperature_2m_min,weathercode",
                "timezone": "Asia/Seoul",
                "past_days": 1,
                "forecast_days": 2,
            },
            timeout=10,
        )
        res.raise_for_status()
        data = res.json()
        highs = data["daily"]["temperature_2m_max"]
        lows = data["daily"]["temperature_2m_min"]
        dates = data["daily"]["time"]
        codes = data["daily"]["weathercode"]
        if len(highs) < 3:
            return None
        return {
            "location": "내 위치" if (lat, lon) != (WEATHER_LAT, WEATHER_LON) else "서울",
            "date": dates[1],
            "yesterday_high": highs[0],
            "today_high": highs[1],
            "today_low": lows[1],
            "tomorrow_high": highs[2],
            # WMO 코드 → 아이콘/문구 매핑은 앱 쪽에서 함(어제/오늘/내일 각각).
            "yesterday_weather_code": codes[0],
            "today_weather_code": codes[1],
            "tomorrow_weather_code": codes[2],
        }
    except Exception as e:  # noqa: BLE001 - 날씨 조회 실패해도 나머지 앱은 정상 동작해야 함
        print(f"[weather] 조회 실패: {e}")
        return None


def _all_watched_tickers() -> list[str]:
    """지금까지 어떤 기기든 등록한 적 있는 티커 전부 + STARTER_TICKERS.
    기본 10개는 아직 아무도 등록 안 했어도 항상 갱신해둠(첫 기기가 조회할
    때 시드되자마자 바로 뉴스가 있어야 하니까)."""
    from sqlmodel import select

    with db.get_session() as session:
        rows = session.exec(select(db.DeviceStockWatch.ticker)).all()
    return sorted(set(rows) | set(stocks.STARTER_TICKERS))


def _seed_stock_watches(session, device_id: int) -> None:
    """이 기기가 관심 종목을 한 번도 등록한 적 없으면 STARTER_TICKERS로
    자동으로 채워둠(화면이 비어있지 않게) — 그 다음부턴 완전히 사용자 편집
    (기본값도 지울 수 있음, stocks.py 참고)."""
    from sqlmodel import select

    existing = session.exec(
        select(db.DeviceStockWatch).where(db.DeviceStockWatch.device_id == device_id)
    ).first()
    if existing is not None:
        return
    for ticker in stocks.STARTER_TICKERS:
        session.add(db.DeviceStockWatch(device_id=device_id, ticker=ticker))
    session.commit()


async def refresh_cache() -> None:
    global _cache, _last_refresh, _last_error, _weather_cache, _stock_news_cache
    async with _refresh_lock:
        try:
            clusters = await asyncio.to_thread(run, live=True)
        except Exception as e:  # noqa: BLE001 - 한 번 실패해도 다음 주기에 재시도, 서버는 안 죽음
            _last_error = str(e)
            return
        _cache = {_make_id(c): c for c in clusters}
        _last_refresh = time.time()
        _last_error = None

        weather = await asyncio.to_thread(_fetch_weather)
        if weather is not None:
            _weather_cache = weather

        tickers = await asyncio.to_thread(_all_watched_tickers)
        _stock_news_cache = await asyncio.to_thread(stocks.fetch_all, tickers)

        def _persist():
            with db.get_session() as session:
                db.persist_issues(session, _cache)
                pruned = db.prune_old_issues(session)
                if pruned:
                    print(f"[prune] 오래된 이슈 {pruned}건 정리함")

        await asyncio.to_thread(_persist)


async def _refresh_loop() -> None:
    while True:
        await asyncio.sleep(REFRESH_INTERVAL_SECONDS)
        await refresh_cache()


def _build_digest_text(limit: int = 5) -> str:
    """다이제스트 알림 본문. 아직 실제 LLM 요약이 없어서(cluster_summaries는
    수동 입력만 가능, README 참고) AI 요약이 아니라 매체 커버리지 상위
    이슈 랭킹을 그대로 씀 — v0로는 이 정도가 정직한 수준."""
    items = sorted(_cache.values(), key=lambda c: (-c["outlet_count"], -c["article_count"]))[:limit]
    if not items:
        return "오늘의 트렌드를 아직 준비 중이에요."
    lines = [f"{i+1}. {c['keyword']} ({c['outlet_count']}개 매체)" for i, c in enumerate(items)]
    return "오늘의 트렌드\n" + "\n".join(lines)


def _send_digest_stub(device: db.Device, text: str) -> None:
    """실제 푸시 발송 자리 — FCM 등 연동 전까지는 로그만 찍음. 나중에
    이 함수 안쪽만 실제 발송 호출로 바꿔 끼우면 됨(device.push_token,
    text만 있으면 됨)."""
    print(f"[digest] (발송 안 함, 로그만) device={device.id} token={device.push_token[:8]}...\n{text}")


def _digest_check() -> list[int]:
    """지금 KST 시각과 digest_hour가 일치하는 기기를 찾아서 발송(스텁)함.
    같은 시간대에 중복 발송하지 않으려고 last_digest_sent_at을 확인함
    (5분마다 확인하는데 매번 보내면 한 시간대에 최대 12번 보낼 수 있어서).
    수동 테스트용으로 POST /digest/run에서도 이 함수를 그대로 씀."""
    from sqlmodel import select

    now_kst = datetime.now(KST)
    sent_to: list[int] = []
    with db.get_session() as session:
        devices = session.exec(
            select(db.Device).where(db.Device.digest_hour == now_kst.hour)
        ).all()
        now_utc = datetime.now(timezone.utc)
        for device in devices:
            if device.last_digest_sent_at is not None:
                # SQLite는 timezone 정보 없이 저장해서 읽어오면 naive
                # datetime이 됨 — 저장할 땐 항상 UTC였으니 그걸로 다시
                # tag만 붙여서 비교함.
                last_sent = device.last_digest_sent_at
                if last_sent.tzinfo is None:
                    last_sent = last_sent.replace(tzinfo=timezone.utc)
                if (now_utc - last_sent).total_seconds() < DIGEST_DEDUPE_WINDOW_SECONDS:
                    continue
            _send_digest_stub(device, _build_digest_text())
            device.last_digest_sent_at = now_utc
            session.add(device)
            sent_to.append(device.id)
        session.commit()
    return sent_to


async def _digest_loop() -> None:
    while True:
        await asyncio.sleep(DIGEST_CHECK_INTERVAL_SECONDS)
        await asyncio.to_thread(_digest_check)


@asynccontextmanager
async def lifespan(app: FastAPI):
    db.init_db()
    await refresh_cache()  # 첫 요청부터 데이터가 있도록 시작 시 한 번 동기적으로 채움
    refresh_task = asyncio.create_task(_refresh_loop())
    digest_task = asyncio.create_task(_digest_loop())
    yield
    refresh_task.cancel()
    digest_task.cancel()


app = FastAPI(title="뉴스 트렌드 API", lifespan=lifespan)


def _rate_limit_key(request: Request) -> str:
    """slowapi 기본 get_remote_address(request.client.host)는 Cloudflare 뒤에서
    무용지물임 — uvicorn이 기본으로 X-Forwarded-For를 신뢰해서 request.client.host를
    덮어쓰는데, Cloudflare는 요청마다 다른 엣지 서버 IP로 이 값을 채워서 같은 사람이
    보낸 요청도 매번 다른 IP로 보임(실측 확인함: 연속 12번 요청이 전부 다른 IP로
    찍힘). Cloudflare가 실제 방문자 IP를 넣어주는 CF-Connecting-IP 헤더를 우선
    씀 — 8000번 포트 직접 접근을 막아뒀으니(2026-08-31) Cloudflare를 거치지 않고는
    이 헤더를 위조해서 우회할 방법이 없음."""
    return request.headers.get("cf-connecting-ip") or get_remote_address(request)


# 로그인/가입 무차별 대입 공격 방지. IP당 요청 수를 세는 방식이라 프로세스가
# 하나뿐인 지금 배포 구조에 딱 맞음(메모리 내 카운터 — 여러 워커/서버로
# 늘어나면 Redis 같은 공유 저장소로 바꿔야 함).
limiter = Limiter(key_func=_rate_limit_key)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# 플러터 웹 개발 서버(다른 포트)에서 호출하려면 CORS 허용이 필요함.
# 나중에 실제 배포 도메인이 정해지면 origin을 좁혀야 함 — 지금은 로컬
# 개발용으로 localhost 전체를 허용.
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
    allow_methods=["*"],
    allow_headers=["*"],
)


class OutletBreakdown(BaseModel):
    outlet: str
    count: int


class ArticleOut(BaseModel):
    outlet: str
    title: str
    link: str
    published: str | None = None


class IssueSummary(BaseModel):
    id: str
    keyword: str
    keywords: list[str]
    category: str
    representative_title: str
    article_count: int
    outlet_count: int


class IssueDetail(IssueSummary):
    outlets: list[OutletBreakdown]
    articles: list[ArticleOut]


def _to_summary(issue_id: str, c: dict) -> IssueSummary:
    return IssueSummary(
        id=issue_id,
        keyword=c["keyword"],
        keywords=c["keywords"],
        category=c["category"],
        representative_title=c["representative_title"],
        article_count=c["article_count"],
        outlet_count=c["outlet_count"],
    )


def _to_detail(issue_id: str, c: dict) -> IssueDetail:
    return IssueDetail(
        **_to_summary(issue_id, c).model_dump(),
        outlets=[OutletBreakdown(outlet=o, count=n) for o, n in c["outlets"].items()],
        articles=[
            ArticleOut(outlet=a["outlet"], title=a["title"], link=a.get("link", ""), published=a.get("published"))
            for a in c["articles"]
        ],
    )


@app.get("/health")
async def health():
    return {
        "status": "ok" if _cache else "warming_up",
        "issue_count": len(_cache),
        "last_refresh": _last_refresh,
        "last_error": _last_error,
    }


@app.get("/categories")
async def get_categories():
    return Counter(c["category"] for c in _cache.values())


@app.get("/stats")
async def get_stats():
    """홈 화면 마스트헤드 통계용("전체기사"/이슈 수). 캐시가 이미 메모리에
    있어서 집계만 하는 거라 가벼움 — /trending?limit=1000처럼 이슈 수백
    개를 기사까지 통째로 내려받을 필요가 없음(2026-08-24: 그렇게 했다가
    첫 화면 로딩이 느려졌다는 피드백을 받고 이 엔드포인트로 분리함)."""
    return {
        "issue_count": len(_cache),
        "article_count": sum(c["article_count"] for c in _cache.values()),
    }


@app.get("/weather")
async def get_weather(lat: float | None = None, lon: float | None = None):
    """홈 화면 "오늘 날씨" 카드용(design/Main.dc.html). lat/lon을 주면
    (사용자가 위치 권한에 동의한 경우) 그 좌표로 그때그때 새로 조회함 —
    서버가 미리 캐싱해둔 건 기본 위치(서울)뿐이라서. lat/lon 없이 부르면
    서버 시작 시/30분마다 갱신되는 기본 위치 캐시를 그대로 씀(빠름).
    Open-Meteo 조회 실패 시(네트워크 문제 등) 503을 줌, 앱은 그때
    플레이스홀더를 그대로 보여주면 됨."""
    if lat is not None and lon is not None:
        weather = await asyncio.to_thread(_fetch_weather, lat, lon)
        if weather is None:
            raise HTTPException(status_code=503, detail="weather data not available")
        return weather
    if _weather_cache is None:
        raise HTTPException(status_code=503, detail="weather data not available yet")
    return _weather_cache


@app.get("/search", response_model=list[IssueSummary])
async def search_issues(q: str = "", limit: int = Query(60, ge=1, le=1000), category: str | None = None):
    """대표 키워드/보조 키워드/대표 헤드라인에 부분 일치하는 이슈 요약만
    내려줌(기사 목록 제외 — 넓은 검색어일 때 타이핑마다 무거워지는 걸
    막으려고, 2026-08-24 실측 피드백).

    2026-08-25: q를 빈 문자열로도 부를 수 있게 함(전체 매칭) — 클라이언트가
    검색할 때마다 서버를 부르는 대신, 가벼운 요약 목록 전체를 한 번만
    받아서 타이핑마다 로컬에서 걸러내게 하려고("이슈판" 프로토타입만큼
    검색이 즉각적이지 않다는 피드백. 서버 호출을 매번 하면 로컬 필터보다
    느릴 수밖에 없어서, 데이터를 가볍게 만들고 클라이언트가 들고 있는
    쪽으로 다시 바꿈)."""
    ql = q.lower()
    items = [
        (cid, c)
        for cid, c in _cache.items()
        if (category is None or c["category"] == category)
        and (
            ql in c["keyword"].lower()
            or any(ql in k.lower() for k in c["keywords"])
            or ql in c["representative_title"].lower()
        )
    ]
    items.sort(key=lambda kv: (-kv[1]["outlet_count"], -kv[1]["article_count"]))
    return [_to_summary(cid, c) for cid, c in items[:limit]]


@app.get("/trending", response_model=list[IssueDetail])
async def get_trending(
    limit: int = Query(40, ge=1, le=1000),
    category: str | None = None,
):
    """Main.dc.html "오늘 많이 언급된 키워드" 화면용. 매체 커버리지 우선 정렬.

    2026-08-24: 요약(IssueSummary) 대신 상세(IssueDetail, 기사 목록 포함)를
    통째로 내려주는 걸로 바꿈 — 플러터 쪽에서 카드를 펼칠 때마다
    /issues/{id}를 다시 부르니까 "이슈판" 정적 프로토타입보다 체감
    반응속도가 느리다는 피드백을 받았음. 처음부터 다 갖고 있으면 펼치기도
    검색도 네트워크 왕복 없이 즉시 됨(이슈판이 원래 그랬던 것처럼).
    이슈 40개 × 기사 몇~십여 건 수준이라 응답 크기 증가는 감당 가능한
    수준으로 판단."""
    items = list(_cache.items())
    if category:
        items = [(cid, c) for cid, c in items if c["category"] == category]
    items.sort(key=lambda kv: (-kv[1]["outlet_count"], -kv[1]["article_count"]))
    return [_to_detail(cid, c) for cid, c in items[:limit]]


@app.get("/issues/{issue_id}", response_model=IssueDetail)
async def get_issue(issue_id: str):
    """IssueDetail.dc.html "매체별 보도 분포 + 전체 관련기사" 화면용."""
    c = _cache.get(issue_id)
    if c is None:
        raise HTTPException(status_code=404, detail="issue not found")
    return _to_detail(issue_id, c)


@app.post("/refresh")
async def force_refresh():
    """개발/테스트용 수동 갱신 트리거 (30분 기다리기 싫을 때)."""
    await refresh_cache()
    return {"issue_count": len(_cache), "last_refresh": _last_refresh, "last_error": _last_error}


# --- 아래부터는 유료화 스키마(backend/README.md, 2026-08-24) 검증용 엔드포인트.
# 실제 로그인/결제는 아직 없어서 user_id/device_id를 클라이언트가 그냥
# 숫자로 넘기는 식으로 되어 있음 — 나중에 인증 붙이면 토큰에서 뽑아내는
# 걸로 교체하면 됨. 지금은 스키마가 실제로 동작하는지 확인하는 목적.


@app.get("/archive", response_model=list[IssueSummary])
async def get_archive(since: str | None = None, limit: int = Query(50, ge=1, le=1000)):
    """1번(히스토리/아카이브). 캐시가 아니라 DB에서 읽음 — 캐시는 30분마다
    갈아엎이지만 DB는 계속 쌓이니까, "예전 이슈"를 보려면 DB를 봐야 함.
    since 생략하면 최근 이슈부터."""
    with db.get_session() as session:
        from sqlmodel import select

        stmt = select(db.Issue).order_by(db.Issue.first_seen_at.desc()).limit(limit)
        if since:
            stmt = select(db.Issue).where(db.Issue.first_seen_at >= since).order_by(
                db.Issue.first_seen_at.desc()
            ).limit(limit)
        issues = session.exec(stmt).all()
        return [
            IssueSummary(
                id=i.id,
                keyword=i.keyword,
                keywords=i.keywords,
                category=i.category,
                representative_title=i.representative_title,
                article_count=i.article_count,
                outlet_count=i.outlet_count,
            )
            for i in issues
        ]


class SummaryIn(BaseModel):
    summary_text: str


@app.get("/issues/{issue_id}/summary")
async def get_summary(issue_id: str):
    """4번(AI 요약). 실제 LLM 연동은 아직 없음 — 캐싱 구조(이슈당 1번만
    생성해서 재사용)만 먼저 검증하는 용도로 수동 입력/조회만 됨."""
    with db.get_session() as session:
        summary = session.get(db.ClusterSummary, issue_id)
        if summary is None:
            raise HTTPException(status_code=404, detail="summary not generated yet")
        return {
            "issue_id": issue_id,
            "summary_text": summary.summary_text,
            "generated_at": summary.generated_at,
            "model_version": summary.model_version,
        }


@app.post("/issues/{issue_id}/summary")
async def set_summary(issue_id: str, body: SummaryIn):
    """개발용 — 실제로는 백그라운드 갱신 때 "새로 생긴 이슈"에 한해 LLM을
    호출해서 채우게 될 자리(README 참고). 지금은 수동으로만 채움."""
    with db.get_session() as session:
        if session.get(db.Issue, issue_id) is None:
            raise HTTPException(status_code=404, detail="issue not found")
        existing = session.get(db.ClusterSummary, issue_id)
        if existing:
            existing.summary_text = body.summary_text
            existing.generated_at = db.now()
            session.add(existing)
        else:
            session.add(db.ClusterSummary(issue_id=issue_id, summary_text=body.summary_text))
        session.commit()
        return {"issue_id": issue_id, "summary_text": body.summary_text}


class DeviceIn(BaseModel):
    push_token: str


@app.post("/devices")
async def register_device(body: DeviceIn):
    """5번(커스텀 키워드 알림, 무료) — 로그인 없이도 알림 보내려면
    최소한 이 기기가 어떤 push_token인지는 서버가 알아야 함."""
    with db.get_session() as session:
        from sqlmodel import select

        existing = session.exec(select(db.Device).where(db.Device.push_token == body.push_token)).first()
        if existing:
            return {"device_id": existing.id}
        device = db.Device(push_token=body.push_token)
        session.add(device)
        session.commit()
        session.refresh(device)
        return {"device_id": device.id}


class WatchIn(BaseModel):
    device_id: int
    keyword: str


@app.post("/watches")
async def add_watch(body: WatchIn):
    with db.get_session() as session:
        if session.get(db.Device, body.device_id) is None:
            raise HTTPException(status_code=404, detail="device not registered")
        watch = db.DeviceKeywordWatch(device_id=body.device_id, keyword=body.keyword)
        session.add(watch)
        session.commit()
        session.refresh(watch)
        return {"id": watch.id, "device_id": watch.device_id, "keyword": watch.keyword}


@app.get("/watches/{device_id}")
async def list_watches(device_id: int):
    with db.get_session() as session:
        from sqlmodel import select

        watches = session.exec(
            select(db.DeviceKeywordWatch).where(db.DeviceKeywordWatch.device_id == device_id)
        ).all()
        return [{"id": w.id, "keyword": w.keyword, "created_at": w.created_at} for w in watches]


@app.delete("/watches/{watch_id}")
async def delete_watch(watch_id: int):
    with db.get_session() as session:
        watch = session.get(db.DeviceKeywordWatch, watch_id)
        if watch is not None:
            session.delete(watch)
            session.commit()
        return {"ok": True}


@app.get("/stocks/catalog")
async def get_stock_catalog():
    """2026-09-06: "티커를 미리 알고 있어야 하는 게 불편하다"는 피드백으로
    추가 — 종목 추가 시 자동완성 검색용. /search와 같은 패턴으로 전체를
    한 번에 내려주고 클라이언트가 타이핑마다 로컬에서 걸러냄."""
    return stocks.catalog()


@app.get("/devices/{device_id}/stocks")
async def list_stock_watches(device_id: int):
    """6번(관심 종목/브랜드 뉴스, 2026-09-06 추가) — 이 기기가 등록한
    티커 목록 + 각 티커 최신 뉴스(캐시, 30분마다 갱신). 한 번도 등록한
    적 없으면 STARTER_TICKERS로 자동 시드함(_seed_stock_watches).
    기사 목록을 여기서 통째로 내려주는 건 /trending과 같은 이유 —
    화면에서 바로 보여줄 데이터라 왕복을 늘릴 필요가 없어서."""
    with db.get_session() as session:
        from sqlmodel import select

        if session.get(db.Device, device_id) is None:
            raise HTTPException(status_code=404, detail="device not registered")
        _seed_stock_watches(session, device_id)
        watches = session.exec(
            select(db.DeviceStockWatch).where(db.DeviceStockWatch.device_id == device_id)
        ).all()
        result = []
        for w in watches:
            name, sector = stocks.ticker_meta(w.ticker)
            result.append(
                {
                    "id": w.id,
                    "ticker": w.ticker,
                    "name": name,
                    "sector": sector,
                    "news": _stock_news_cache.get(w.ticker, []),
                }
            )
        return result


class StockWatchIn(BaseModel):
    device_id: int
    ticker: str


@app.post("/stocks")
async def add_stock_watch(body: StockWatchIn):
    ticker = body.ticker.strip().upper()
    if not ticker:
        raise HTTPException(status_code=422, detail="ticker must not be empty")
    with db.get_session() as session:
        from sqlmodel import select

        if session.get(db.Device, body.device_id) is None:
            raise HTTPException(status_code=404, detail="device not registered")
        # 2026-09-06: 같은 티커를 두 번 추가하면 칩/카드가 중복으로 뜨는
        # 문제("있는 건 추가 안 되어야 할 것 같다" 피드백) — register_device와
        # 같은 패턴으로, 이미 있으면 새로 안 만들고 기존 걸 그대로 돌려줌.
        existing = session.exec(
            select(db.DeviceStockWatch).where(
                db.DeviceStockWatch.device_id == body.device_id,
                db.DeviceStockWatch.ticker == ticker,
            )
        ).first()
        watch = existing or db.DeviceStockWatch(device_id=body.device_id, ticker=ticker)
        if existing is None:
            session.add(watch)
            session.commit()
            session.refresh(watch)
        name, sector = stocks.ticker_meta(ticker)
    # 2026-09-06: 다음 30분 갱신 주기까지 기다리지 않고 이 티커 하나만
    # 바로 가져옴("추가하면 그 뉴스는 바로 안 받아와지냐"는 피드백) —
    # 이미 다른 기기가 등록해서 캐시에 있으면 다시 안 부름(할당량 절약).
    if ticker not in _stock_news_cache:
        _stock_news_cache[ticker] = await asyncio.to_thread(stocks.fetch_one_with_translation, ticker)
    return {"id": watch.id, "device_id": watch.device_id, "ticker": ticker, "name": name, "sector": sector}


@app.delete("/stocks/{watch_id}")
async def delete_stock_watch(watch_id: int):
    with db.get_session() as session:
        watch = session.get(db.DeviceStockWatch, watch_id)
        if watch is not None:
            session.delete(watch)
            session.commit()
        return {"ok": True}


class DigestIn(BaseModel):
    hour: int | None = None  # 0~23(KST), null이면 끔


@app.put("/devices/{device_id}/digest")
async def set_digest(device_id: int, body: DigestIn):
    """매일 정해진 시간에 오늘의 트렌드 요약을 푸시(배너)로 보내는 기능의
    "설정 저장"까지만 함 — 실제 발송(FCM 등 푸시 서비스 연동)은 아직
    없음, 나중에 붙일 자리만 미리 만들어둠. 기기당 하루 1회."""
    if body.hour is not None and not (0 <= body.hour <= 23):
        raise HTTPException(status_code=422, detail="hour must be 0-23")
    with db.get_session() as session:
        device = session.get(db.Device, device_id)
        if device is None:
            raise HTTPException(status_code=404, detail="device not registered")
        device.digest_hour = body.hour
        session.add(device)
        session.commit()
        return {"device_id": device_id, "digest_hour": device.digest_hour}


@app.get("/devices/{device_id}/digest")
async def get_digest(device_id: int):
    with db.get_session() as session:
        device = session.get(db.Device, device_id)
        if device is None:
            raise HTTPException(status_code=404, detail="device not registered")
        return {"device_id": device_id, "digest_hour": device.digest_hour}


def _alert_settings_dict(device: db.Device) -> dict:
    return {
        "device_id": device.id,
        "periodic_alert_enabled": device.periodic_alert_enabled,
        "periodic_interval_minutes": device.periodic_interval_minutes,
        "quiet_hours_start": device.quiet_hours_start,
        "quiet_hours_end": device.quiet_hours_end,
        "min_outlet_count": device.min_outlet_count,
        "alert_categories": device.alert_categories,
        "max_daily_alerts": device.max_daily_alerts,
    }


class AlertSettingsIn(BaseModel):
    periodic_alert_enabled: bool
    periodic_interval_minutes: int
    quiet_hours_start: int
    quiet_hours_end: int
    min_outlet_count: int
    alert_categories: list[str] | None = None
    max_daily_alerts: int


@app.get("/devices/{device_id}/alert-settings")
async def get_alert_settings(device_id: int):
    """새로 뜨거나 급상승한 이슈를 재계산 주기마다 체크해서 알려주는
    "주기적 알림" 설정 — UI/설정 저장까지만 되어 있고, 실제 감지·발송
    로직은 아직 없음(digest_hour와 같은 단계)."""
    with db.get_session() as session:
        device = session.get(db.Device, device_id)
        if device is None:
            raise HTTPException(status_code=404, detail="device not registered")
        return _alert_settings_dict(device)


@app.put("/devices/{device_id}/alert-settings")
async def set_alert_settings(device_id: int, body: AlertSettingsIn):
    if not (0 <= body.quiet_hours_start <= 23) or not (0 <= body.quiet_hours_end <= 23):
        raise HTTPException(status_code=422, detail="quiet hours must be 0-23")
    if body.periodic_interval_minutes not in (30, 60, 120, 180):
        raise HTTPException(status_code=422, detail="periodic_interval_minutes must be 30/60/120/180")
    if body.min_outlet_count < 1:
        raise HTTPException(status_code=422, detail="min_outlet_count must be >= 1")
    if body.max_daily_alerts < 1:
        raise HTTPException(status_code=422, detail="max_daily_alerts must be >= 1")
    with db.get_session() as session:
        device = session.get(db.Device, device_id)
        if device is None:
            raise HTTPException(status_code=404, detail="device not registered")
        device.periodic_alert_enabled = body.periodic_alert_enabled
        device.periodic_interval_minutes = body.periodic_interval_minutes
        device.quiet_hours_start = body.quiet_hours_start
        device.quiet_hours_end = body.quiet_hours_end
        device.min_outlet_count = body.min_outlet_count
        device.alert_categories_json = (
            json.dumps(body.alert_categories, ensure_ascii=False) if body.alert_categories else None
        )
        device.max_daily_alerts = body.max_daily_alerts
        session.add(device)
        session.commit()
        session.refresh(device)
        return _alert_settings_dict(device)


@app.post("/digest/run")
async def run_digest_check():
    """개발/테스트용 — 지금 KST 시각이 되길 기다리지 않고 다이제스트
    스케줄러를 즉시 한 번 실행함(5분마다 자동으로도 돌긴 함). 실제
    발송은 안 하고 로그만 찍음(_send_digest_stub 참고, FCM 연동 전)."""
    sent_to = await asyncio.to_thread(_digest_check)
    return {"checked_hour_kst": datetime.now(KST).hour, "sent_to_device_ids": sent_to}


class FavoriteIn(BaseModel):
    issue_id: str


@app.post("/favorites")
async def add_favorite(body: FavoriteIn, authorization: str | None = Header(default=None)):
    """3번(무제한 즐겨찾기+동기화, 유료) — 로그인한 유저용. 비로그인
    즐겨찾기는 클라이언트 로컬 저장이라 이 엔드포인트를 안 씀.
    2026-08-28: 로그인 붙으면서 user_id를 클라이언트가 직접 지정하던
    것에서 Authorization 토큰으로 알아내는 걸로 바꿈(전엔 아무 user_id나
    넣으면 남의 즐겨찾기에 쓸 수 있는 구멍이었음)."""
    with db.get_session() as session:
        user = _current_user(session, authorization)
        if session.get(db.Issue, body.issue_id) is None:
            raise HTTPException(status_code=404, detail="issue not found")
        fav = db.UserFavorite(user_id=user.id, issue_id=body.issue_id)
        session.add(fav)
        session.commit()
        session.refresh(fav)
        return {"id": fav.id, "user_id": fav.user_id, "issue_id": fav.issue_id}


@app.get("/favorites", response_model=list[IssueSummary])
async def list_favorites(authorization: str | None = Header(default=None)):
    with db.get_session() as session:
        from sqlmodel import select

        user = _current_user(session, authorization)
        favs = session.exec(select(db.UserFavorite).where(db.UserFavorite.user_id == user.id)).all()
        result = []
        for f in favs:
            i = session.get(db.Issue, f.issue_id)
            if i is None:
                continue  # 알려진 한계: 클러스터 경계가 바뀌어 사라진 경우 (db.py 참고)
            result.append(
                IssueSummary(
                    id=i.id,
                    keyword=i.keyword,
                    keywords=i.keywords,
                    category=i.category,
                    representative_title=i.representative_title,
                    article_count=i.article_count,
                    outlet_count=i.outlet_count,
                )
            )
        return result


class FeedbackIn(BaseModel):
    device_id: int | None = None
    message: str


@app.post("/feedback")
async def submit_feedback(body: FeedbackIn):
    """베타 "고객의 소리" — 답장 없는 일방향 제출. 로그인 없이도 보낼 수
    있음(device_id는 선택, 있으면 어느 기기에서 왔는지 참고용)."""
    message = body.message.strip()
    if not message:
        raise HTTPException(status_code=422, detail="message must not be empty")
    with db.get_session() as session:
        fb = db.Feedback(device_id=body.device_id, message=message)
        session.add(fb)
        session.commit()
        session.refresh(fb)
        return {"id": fb.id, "created_at": fb.created_at}


@app.get("/feedback")
async def list_feedback():
    """개발용 — 제출된 피드백을 최신순으로 확인(관리자 화면이 따로
    없어서 지금은 그냥 API로 직접 조회)."""
    with db.get_session() as session:
        from sqlmodel import select

        items = session.exec(select(db.Feedback).order_by(db.Feedback.created_at.desc())).all()
        return [
            {"id": f.id, "device_id": f.device_id, "message": f.message, "created_at": f.created_at}
            for f in items
        ]


@app.get("/feedback/view", response_class=HTMLResponse)
async def view_feedback():
    """개발용 — 브라우저로 바로 열어서 볼 수 있는 피드백 목록(최신순).
    로그인 화면 없이 그냥 이 URL만 아는 사람(=나)이 열어보는 용도라서
    인증은 따로 안 둠 — 배포 후에는 이 경로를 외부에 안 알려주면 됨."""
    with db.get_session() as session:
        from sqlmodel import select

        items = session.exec(select(db.Feedback).order_by(db.Feedback.created_at.desc())).all()

    # 사용자가 직접 입력한 텍스트라 그대로 HTML에 꽂으면 XSS 위험이 있음
    # — 반드시 이스케이프하고 넣음.
    rows = "".join(
        f"""<li class="row">
            <div class="meta">
                <span class="time">{f.created_at.strftime('%Y-%m-%d %H:%M')}</span>
                <span class="device">{'기기 #' + str(f.device_id) if f.device_id else '기기 정보 없음'}</span>
            </div>
            <p class="message">{html.escape(f.message)}</p>
        </li>"""
        for f in items
    )
    empty = '<p class="empty">아직 들어온 의견이 없어요.</p>' if not items else ""

    page_html = f"""<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>피드백 — 뉴스 트렌드</title>
<style>
  body {{ font-family: -apple-system, "Malgun Gothic", sans-serif; background: #EEF1EA;
         color: #232A20; max-width: 640px; margin: 0 auto; padding: 24px 16px; }}
  h1 {{ font-size: 18px; margin-bottom: 4px; }}
  .count {{ color: #8B9280; font-size: 13px; margin-bottom: 20px; }}
  ul {{ list-style: none; padding: 0; margin: 0; }}
  .row {{ background: #fff; border: 1px solid #D7DBC9; border-radius: 10px;
          padding: 14px; margin-bottom: 10px; }}
  .meta {{ display: flex; justify-content: space-between; font-size: 11px;
           color: #8B9280; margin-bottom: 6px; }}
  .message {{ font-size: 14px; line-height: 1.5; white-space: pre-wrap; margin: 0; }}
  .empty {{ color: #8B9280; font-size: 13px; }}
</style>
</head>
<body>
  <h1>피드백함</h1>
  <p class="count">총 {len(items)}건 · 최신순</p>
  <ul>{rows}</ul>
  {empty}
</body>
</html>"""
    return HTMLResponse(content=page_html)


# --- 로그인(이메일+비밀번호). 2026-08-28: 구글/애플 로그인은 각각 API
# 크리덴셜 발급이 필요해서(사용자가 직접 콘솔에서 해야 하는 일, FCM/LLM
# 키와 같은 종류) 당장은 이메일+비밀번호만 구현함. 세션은 정식 JWT가
# 아니라 그냥 무작위 토큰을 DB에 저장해두고 대조하는 v0 방식 —
# db.UserSession 참고.

# 완벽한 이메일 검증(실제로 메일이 도달하는지)은 인증 메일을 보내봐야
# 알 수 있는데, 그건 이메일 발송 서비스 API 키가 필요해서(FCM/LLM과 같은
# 종류의 블로커) v0 범위 밖임. 여기선 "형식이 이메일처럼 생겼는지"만
# 정규식으로 걸러냄 — RFC 5322 전체를 구현하진 않고, 실사용에서 걸러야
# 할 흔한 오타(골뱅이 없음, 도메인에 마침표 없음 등)만 잡는 실용적인 수준.
_EMAIL_RE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


def _hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def _verify_password(password: str, hashed: str) -> bool:
    return bcrypt.checkpw(password.encode("utf-8"), hashed.encode("utf-8"))


def _current_user(session, authorization: str | None) -> db.User:
    """Authorization: Bearer <token> 헤더로 로그인한 유저를 찾음.
    없거나 잘못됐으면 401."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="missing bearer token")
    token = authorization.removeprefix("Bearer ").strip()
    user_session = session.get(db.UserSession, token)
    if user_session is None:
        raise HTTPException(status_code=401, detail="invalid or expired session")
    user = session.get(db.User, user_session.user_id)
    if user is None:
        raise HTTPException(status_code=401, detail="invalid session")
    return user


class SignupIn(BaseModel):
    email: str
    password: str


@app.post("/auth/signup")
@limiter.limit("5/minute")
async def signup(request: Request, body: SignupIn):
    email = body.email.strip().lower()
    if not _EMAIL_RE.match(email):
        raise HTTPException(status_code=422, detail="invalid email")
    if len(body.password) < 8:
        raise HTTPException(status_code=422, detail="password must be at least 8 characters")
    with db.get_session() as session:
        from sqlmodel import select

        existing = session.exec(select(db.User).where(db.User.email == email)).first()
        if existing is not None:
            raise HTTPException(status_code=409, detail="email already registered")
        user = db.User(email=email, password_hash=_hash_password(body.password))
        session.add(user)
        session.commit()
        session.refresh(user)
        token = secrets.token_hex(32)
        session.add(db.UserSession(token=token, user_id=user.id))
        session.commit()
        return {"user_id": user.id, "email": user.email, "token": token}


class LoginIn(BaseModel):
    email: str
    password: str


@app.post("/auth/login")
@limiter.limit("10/minute")
async def login(request: Request, body: LoginIn):
    email = body.email.strip().lower()
    with db.get_session() as session:
        from sqlmodel import select

        user = session.exec(select(db.User).where(db.User.email == email)).first()
        if user is None or user.password_hash is None or not _verify_password(body.password, user.password_hash):
            raise HTTPException(status_code=401, detail="invalid email or password")
        token = secrets.token_hex(32)
        session.add(db.UserSession(token=token, user_id=user.id))
        session.commit()
        return {"user_id": user.id, "email": user.email, "token": token}


@app.post("/auth/logout")
async def logout(authorization: str | None = Header(default=None)):
    if not authorization or not authorization.startswith("Bearer "):
        return {"ok": True}
    token = authorization.removeprefix("Bearer ").strip()
    with db.get_session() as session:
        user_session = session.get(db.UserSession, token)
        if user_session is not None:
            session.delete(user_session)
            session.commit()
        return {"ok": True}


@app.get("/auth/me")
async def get_me(authorization: str | None = Header(default=None)):
    with db.get_session() as session:
        user = _current_user(session, authorization)
        return {"user_id": user.id, "email": user.email}
