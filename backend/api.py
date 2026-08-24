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
import time
from collections import Counter
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel

import db
from pipeline import run

REFRESH_INTERVAL_SECONDS = 30 * 60  # 30분마다 재수집+재클러스터링

_cache: dict[str, dict] = {}
_last_refresh: float | None = None
_last_error: str | None = None
_refresh_lock = asyncio.Lock()


def _make_id(cluster: dict) -> str:
    """클러스터 안 기사 링크(없으면 제목)를 정렬해서 해시 — 같은 기사
    묶음이면 재수집 후에도 같은 id가 나오게(완전 보장은 아니지만 v0로 충분)."""
    keys = sorted(a.get("link") or a["title"] for a in cluster["articles"])
    return hashlib.sha1("|".join(keys).encode("utf-8")).hexdigest()[:12]


async def refresh_cache() -> None:
    global _cache, _last_refresh, _last_error
    async with _refresh_lock:
        try:
            clusters = await asyncio.to_thread(run, live=True)
        except Exception as e:  # noqa: BLE001 - 한 번 실패해도 다음 주기에 재시도, 서버는 안 죽음
            _last_error = str(e)
            return
        _cache = {_make_id(c): c for c in clusters}
        _last_refresh = time.time()
        _last_error = None

        def _persist():
            with db.get_session() as session:
                db.persist_issues(session, _cache)

        await asyncio.to_thread(_persist)


async def _refresh_loop() -> None:
    while True:
        await asyncio.sleep(REFRESH_INTERVAL_SECONDS)
        await refresh_cache()


@asynccontextmanager
async def lifespan(app: FastAPI):
    db.init_db()
    await refresh_cache()  # 첫 요청부터 데이터가 있도록 시작 시 한 번 동기적으로 채움
    task = asyncio.create_task(_refresh_loop())
    yield
    task.cancel()


app = FastAPI(title="뉴스 트렌드 API", lifespan=lifespan)


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


@app.get("/trending", response_model=list[IssueSummary])
async def get_trending(
    limit: int = Query(40, ge=1, le=200),
    category: str | None = None,
):
    """Main.dc.html "오늘 많이 언급된 키워드" 화면용. 매체 커버리지 우선 정렬."""
    items = list(_cache.items())
    if category:
        items = [(cid, c) for cid, c in items if c["category"] == category]
    items.sort(key=lambda kv: (-kv[1]["outlet_count"], -kv[1]["article_count"]))
    return [_to_summary(cid, c) for cid, c in items[:limit]]


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
async def get_archive(since: str | None = None, limit: int = Query(50, ge=1, le=200)):
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


class FavoriteIn(BaseModel):
    user_id: int
    issue_id: str


@app.post("/favorites")
async def add_favorite(body: FavoriteIn):
    """3번(무제한 즐겨찾기+동기화, 유료) — 로그인한 유저용. 비로그인
    즐겨찾기는 클라이언트 로컬 저장이라 이 엔드포인트를 안 씀."""
    with db.get_session() as session:
        if session.get(db.Issue, body.issue_id) is None:
            raise HTTPException(status_code=404, detail="issue not found")
        fav = db.UserFavorite(user_id=body.user_id, issue_id=body.issue_id)
        session.add(fav)
        session.commit()
        session.refresh(fav)
        return {"id": fav.id, "user_id": fav.user_id, "issue_id": fav.issue_id}


@app.get("/favorites/{user_id}", response_model=list[IssueSummary])
async def list_favorites(user_id: int):
    with db.get_session() as session:
        from sqlmodel import select

        favs = session.exec(select(db.UserFavorite).where(db.UserFavorite.user_id == user_id)).all()
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
