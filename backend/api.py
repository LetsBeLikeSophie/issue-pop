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
import os
import re
import secrets
import time
from collections import Counter
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from urllib.parse import urlparse
from zoneinfo import ZoneInfo

import bcrypt
import firebase_admin
import requests
from firebase_admin import messaging
from fastapi import Depends, FastAPI, Header, HTTPException, Query, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse, Response
from fastapi.security import HTTPBasic, HTTPBasicCredentials
from pydantic import BaseModel
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

import cluster_audit
import db
import quotes
import sources
import stocks
import word_of_day
from pipeline import run

REFRESH_INTERVAL_SECONDS = 30 * 60  # 30분마다 재수집+재클러스터링
# 2026-09-11: 클러스터 감사(cluster_audit.py) — 트래픽 적은 새벽 시간에
# 하루 한 번만 돎(라이브 클러스터링과는 별개, LLM 배치 호출이라 비쌀 건
# 없지만 그래도 굳이 피크 시간에 돌 이유는 없어서).
CLUSTER_AUDIT_HOUR_KST = 4
CLUSTER_AUDIT_CHECK_INTERVAL_SECONDS = 30 * 60
DIGEST_CHECK_INTERVAL_SECONDS = 5 * 60  # 다이제스트 대상 확인 주기
DIGEST_DEDUPE_WINDOW_SECONDS = 50 * 60  # 이 안에 이미 보냈으면 재발송 안 함
# 2026-09-14: 오늘의 단어를 유저가 그날 처음 GET /word-of-day를 부를 때
# 그 자리에서(사전 API 최대 15번 + LLM 1번, 순차 호출) 계산해서 그
# 첫 요청이 눈에 띄게 느리다는 피드백을 받음("너무 늦게 뜨거든") —
# 유저 요청을 기다리지 않고 미리 계산해두려고 백그라운드 루프를 따로 둠.
WORD_OF_DAY_CHECK_INTERVAL_SECONDS = 10 * 60
# 2026-09-26: 관심 종목 추가 자동완성용 SEC 티커 카탈로그(stocks.py의
# _fetch_sec_catalog)가 "서버 프로세스당 한 번만" 캐싱돼서, 서버가 오래
# 안 재시작되면 SEC 쪽 신규 상장/폐지가 계속 안 반영된다는 지적으로
# 추가함 — 회사 목록이 하루에도 몇 번씩 바뀌는 건 아니라서 하루 주기면
# 충분하다고 판단.
STOCK_CATALOG_REFRESH_INTERVAL_SECONDS = 24 * 60 * 60
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
_stock_quote_cache: dict[str, dict] = {}  # 티커 → 가격/변동(quotes.py 참고)
_usd_krw_rate: float | None = None  # "$ 탭하면 원화로" 토글용, 하루 단위 갱신으로 충분

# 2026-09-20: 실제 푸시 발송(FCM) — 날씨 API 키처럼 사용자가 직접 발급
# 받아야 하는 자격증명이라(Firebase 콘솔 > 프로젝트 설정 > 서비스 계정 >
# 새 비공개 키 생성), 서버 환경변수 GOOGLE_APPLICATION_CREDENTIALS로 키
# 파일 경로를 주면 그걸로 인증함. firebase_admin.initialize_app()은
# 인자 없이 부르면 이 환경변수를 자동으로 읽지만(Application Default
# Credentials), **실제 인증은 미룸** — 키가 없거나 잘못돼도 여기선 항상
# 성공한 것처럼 보임(실측 확인). 그래서 _firebase_ready는 "초기화
# 자체가 안 됐는지"만 걸러주고, 진짜 방어선은 _send_digest()의
# try/except임 — 키가 없으면 messaging.send() 시점에 ValueError로
# 실패하고, 그건 거기서 로그만 찍고 조용히 넘어감(서버는 안 죽음).
_firebase_ready = False
try:
    firebase_admin.initialize_app()
    _firebase_ready = True
except Exception as e:  # noqa: BLE001 — 초기화 자체가 실패하는 경우는 드물지만 방어
    print(f"[firebase] 초기화 실패 — 다이제스트는 로그만 찍는 스텁으로 동작함: {e}")


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
    global _cache, _last_refresh, _last_error, _weather_cache, _stock_news_cache, _stock_quote_cache, _usd_krw_rate
    async with _refresh_lock:
        try:
            clusters = await asyncio.to_thread(run, live=True)
        except Exception as e:  # noqa: BLE001 - 한 번 실패해도 다음 주기에 재시도, 서버는 안 죽음
            _last_error = str(e)
            return
        # 2026-09-26: "관심 이슈 알림" 대상(새로 생긴 이슈 id)을 구하려고
        # 갱신 전 id 집합을 남겨둠. 서버 막 시작해서 _cache가 아직 비어
        # 있을 때(old_ids가 빈 집합)는 사실상 전부가 "새 이슈"로 잡혀서
        # 재시작할 때마다 쓸데없이 알림이 우르르 나갈 수 있어서, 그 경우엔
        # 새 이슈 체크 자체를 건너뜀.
        old_ids = set(_cache.keys())
        _cache = {_make_id(c): c for c in clusters}
        _last_refresh = time.time()
        _last_error = None
        new_issue_ids = (set(_cache.keys()) - old_ids) if old_ids else set()

        weather = await asyncio.to_thread(_fetch_weather)
        if weather is not None:
            _weather_cache = weather

        tickers = await asyncio.to_thread(_all_watched_tickers)
        _stock_news_cache = await asyncio.to_thread(stocks.fetch_all, tickers)
        _stock_quote_cache = await asyncio.to_thread(quotes.fetch_quotes, tickers)
        rate = await asyncio.to_thread(quotes.fetch_usd_krw_rate)
        if rate is not None:
            _usd_krw_rate = rate

        def _persist():
            with db.get_session() as session:
                db.persist_issues(session, _cache)
                # persist_issues가 새 이슈는 first_seen_at=지금으로 넣고
                # 기존 이슈는 안 건드리므로, 여기서 다시 읽어오면 "이
                # id가 DB에 처음 잡힌 시각"을 그대로 얻을 수 있음("N일째
                # 보도 중" 배지용, IssueSummary.first_seen_at 참고).
                rows = session.exec(
                    db.select(db.Issue.id, db.Issue.first_seen_at).where(db.Issue.id.in_(_cache.keys()))
                ).all()
                for issue_id, first_seen_at in rows:
                    if issue_id in _cache:
                        _cache[issue_id]["first_seen_at"] = first_seen_at.isoformat()
                pruned = db.prune_old_issues(session)
                if pruned:
                    print(f"[prune] 오래된 이슈 {pruned}건 정리함")
                pruned_embeddings = db.prune_old_embedding_cache(session)
                if pruned_embeddings:
                    print(f"[prune] 오래된 임베딩 캐시 {pruned_embeddings}건 정리함")

        await asyncio.to_thread(_persist)

        if new_issue_ids:
            await asyncio.to_thread(_check_keyword_alerts, new_issue_ids)


async def _refresh_loop() -> None:
    while True:
        await asyncio.sleep(REFRESH_INTERVAL_SECONDS)
        await refresh_cache()


_DIGEST_TITLE_MAX_LEN = 40  # 공유 카드(share_card.dart)와 같은 한 줄 미리보기 길이 기준


def _truncate(text: str, max_len: int) -> str:
    return text if len(text) <= max_len else text[:max_len].rstrip() + "…"


def _build_digest_text() -> str:
    """다이제스트 알림 본문. 아직 실제 LLM 요약이 없어서(cluster_summaries는
    수동 입력만 가능, README 참고) AI 요약이 아니라 매체 커버리지 1위
    이슈를 그대로 씀 — v0로는 이 정도가 정직한 수준.

    2026-09-14: 발송 미리보기로 보다가 "키워드만 있으니 무슨 뉴스인지
    안 와닿는다, 공유 카드(share_card.dart)처럼 대표 기사 미리보기 한
    줄을 같이 넣으면 좋겠다"는 피드백을 받음.

    2026-09-26: 상위 5개를 다 나열했었는데, "어차피 알림 배너엔 한두 줄만
    보이니 1위만 미리보기로 보여주고 카테고리 태그를 앞에 다는 게
    낫겠다"는 피드백으로 축소함 — 어차피 배너에서 안 보이던 2~5위는
    실질적으로 아무도 못 읽고 있었음. 반환값의 첫 줄이 알림 제목으로
    쓰이는 관례는 그대로 유지(_DigestPreviewSheet가 첫 줄을 title로
    split해서 씀, _send_digest도 title은 별도로 고정값을 씀).
    """
    items = sorted(_cache.values(), key=lambda c: (-c["outlet_count"], -c["article_count"]))
    if not items:
        return "오늘의 이슈팝\n오늘의 트렌드를 아직 준비 중이에요."
    top = items[0]
    headline = f"[{top['category']}] {_truncate(top['representative_title'], _DIGEST_TITLE_MAX_LEN)}"
    # 2026-09-26: 알림 제목을 "오늘의 트렌드"에서 앱 설정 화면의 이름과
    # 맞춰 "오늘의 이슈팝"으로 바꿈(사용자가 설정에서 보는 이름과 실제
    # 받는 알림 제목이 다르면 헷갈린다는 지적).
    return f"오늘의 이슈팝\n{headline}"


def _send_push(device: db.Device, title: str, body: str, session) -> bool:
    """실제 FCM 발송 — 다이제스트/관심 이슈 알림/오늘의 단어 알림이
    공유하는 공용 헬퍼(2026-09-26에 _send_digest에서 뽑아냄, 세 알림이
    각자 UnregisteredError 처리를 따로 갖고 있으면 하나 고칠 때 나머지를
    잊어버리기 쉬워서). Firebase 자격증명이 없으면(로컬 개발 등) 로그만
    찍는 스텁으로 동작함. 토큰이 만료/무효면(재설치, 알림 권한 취소,
    앱 삭제 등) FCM이 UnregisteredError로 알려주는데, 그 기기는 앞으로도
    계속 실패할 뿐이라 아예 지워서 다음 확인부터 안 걸리게 함 — 안 지우면
    영원히 실패하는 발송을 계속 시도하게 됨. 이 기기를 삭제했으면 True를
    돌려줌(호출하는 쪽이 그 뒤 last_*_sent_at 갱신 등을 건너뛰게)."""
    if not _firebase_ready:
        print(f"[push] (Firebase 미설정, 로그만) device={device.id} title={title!r} body={body!r}")
        return False
    # firebase-admin 7.x에서 Message.token이 deprecated(Message.fid로
    # 대체 예정)로 경고가 뜨지만 아직 동작은 함 — fid의 정확한 의미가
    # 문서화가 안 돼 있어서 섣불리 안 바꿈. SDK가 token을 실제로 없애면
    # 그때 다시 확인.
    message = messaging.Message(
        notification=messaging.Notification(title=title, body=body),
        token=device.push_token,
    )
    try:
        messaging.send(message)
        print(f"[push] device={device.id} 발송 완료: {title}")
    except messaging.UnregisteredError:
        print(f"[push] device={device.id} 토큰 만료 — 기기 삭제")
        session.delete(device)
        return True
    except Exception as e:  # noqa: BLE001 — FCM 쪽 일시 오류 등 다양하게 옴
        print(f"[push] device={device.id} 발송 실패: {e}")
    return False


def _send_digest(device: db.Device, text: str, session) -> bool:
    """다이제스트 텍스트(첫 줄=제목, 나머지=본문 관례 — _build_digest_text
    참고)를 _send_push용으로 나눠서 보냄."""
    title, _, body = text.partition("\n")
    return _send_push(device, title, body or title, session)


def _issue_matches_keyword(issue: dict, keyword: str) -> bool:
    """/search 엔드포인트와 같은 매칭 기준(대표 키워드/보조 키워드/대표
    헤드라인 중 하나라도 부분 일치)."""
    kw = keyword.lower()
    return (
        kw in issue["keyword"].lower()
        or any(kw in k.lower() for k in issue["keywords"])
        or kw in issue["representative_title"].lower()
    )


def _matching_issues(keywords: list[str], issue_ids) -> list[dict]:
    """주어진 이슈 id들 중 keywords 아무거나와 매칭되는 이슈를 매체
    커버리지 순으로 정렬해서 돌려줌."""
    matched = [_cache[iid] for iid in issue_ids if iid in _cache and any(_issue_matches_keyword(_cache[iid], kw) for kw in keywords)]
    matched.sort(key=lambda c: (-c["outlet_count"], -c["article_count"]))
    return matched


def _keyword_alert_message(matched: list[dict]) -> tuple[str, str]:
    """관심 이슈 알림의 제목/본문 — 다이제스트와 같은 "[카테고리] 제목"
    한 줄 포맷. 이번 주기에 여러 이슈가 매칭되면 1위만 보여주고 나머지는
    건수로만 덧붙임(이슈마다 따로 보내면 스팸처럼 느껴질 수 있어서)."""
    title = "관심 키워드에 새 소식이 떴어요"
    top = matched[0]
    headline = f"[{top['category']}] {_truncate(top['representative_title'], _DIGEST_TITLE_MAX_LEN)}"
    if len(matched) > 1:
        headline += f" 외 {len(matched) - 1}건"
    return title, headline


def _in_quiet_hours(hour: int, quiet_start: int, quiet_end: int) -> bool:
    """관심 이슈 알림의 "조용한 시간대"(이 시간엔 알림 금지) 판정.
    2026-09-26 추가 — "실시간 트렌드 알림" 6개 옵션을 걷어내면서도, 그 중
    유일하게 실제로 쓸모 있던 "조용한 시간대"만 관심 이슈 알림에 가볍게
    다시 붙임(체크주기/최소매체수/하루최대알림/카테고리 필터는 안 씀 —
    복잡도만 늘리고 실사용 근거가 약했음).

    quiet_start == quiet_end면 "설정 안 함"(항상 알림 허용)으로 취급.
    quiet_start > quiet_end면 자정을 넘어가는 구간(예: 23시~7시)으로 봄."""
    if quiet_start == quiet_end:
        return False
    if quiet_start < quiet_end:
        return quiet_start <= hour < quiet_end
    return hour >= quiet_start or hour < quiet_end


def _check_keyword_alerts(new_issue_ids: set[str]) -> list[int]:
    """새로 뜬 이슈가 있으면, 관심 이슈 알림을 켠 기기의 관심 키워드와
    매칭해서 발송함(조용한 시간대인 기기는 이번 주기엔 건너뜀 — 나중에
    몰아서 보내주는 게 아니라 그냥 이번 매칭은 놓침, 알림의 성격상
    "그때 떴다는 사실" 자체가 핵심이라 나중에 보내는 건 의미가 약하다고
    판단함). refresh_cache()가 새 _cache를 만든 직후에 호출됨.

    2026-09-26: 이슈 id는 재클러스터링 때마다 바뀔 수 있다는 알려진
    한계가 있어서(README 참고) "새 id"가 항상 "진짜 새로운 사건"은
    아닐 수 있음 — 그래도 그 경우조차 "표현이 크게 바뀐 갱신"인 거라
    알림이 완전히 틀린 건 아니라고 보고 이 정도로 감."""
    if not new_issue_ids:
        return []
    from sqlmodel import select

    now_hour = datetime.now(KST).hour
    sent_to: list[int] = []
    with db.get_session() as session:
        devices = session.exec(select(db.Device).where(db.Device.keyword_alert_enabled)).all()
        if not devices:
            return []
        watches = session.exec(select(db.DeviceKeywordWatch)).all()
        keywords_by_device: dict[int, list[str]] = {}
        for w in watches:
            keywords_by_device.setdefault(w.device_id, []).append(w.keyword)

        for device in devices:
            if _in_quiet_hours(now_hour, device.keyword_alert_quiet_start, device.keyword_alert_quiet_end):
                continue
            keywords = keywords_by_device.get(device.id)
            if not keywords:
                continue
            matched = _matching_issues(keywords, new_issue_ids)
            if not matched:
                continue
            title, body = _keyword_alert_message(matched)
            if _send_push(device, title, body, session):
                continue  # 토큰 만료로 기기 삭제됨
            sent_to.append(device.id)
        session.commit()
    return sent_to


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
            if _send_digest(device, _build_digest_text(), session):
                continue  # 토큰 만료로 기기 자체가 삭제됨 — last_digest_sent_at 갱신 대상 아님
            device.last_digest_sent_at = now_utc
            session.add(device)
            sent_to.append(device.id)
        session.commit()
    return sent_to


def _word_of_day_alert_check(force: bool = False) -> list[int]:
    """지금 KST 시각과 기기별 word_of_day_hour가 일치하면(또는 force=True면
    시각 무관하게) 오늘의 단어 알림을 켠 기기에 발송함 — digest_hour와
    같은 패턴으로 2026-09-26에 서버 전체 고정 시각에서 기기별 설정
    가능하게 바꿈("오늘의 이슈팝이랑 왜 다르게 고정이냐"는 피드백).
    중복방지도 _digest_check와 동일(last_word_of_day_sent_at). word_of_day는
    이미 _word_of_day_loop가 하루 한 번만 새로 뽑아서 캐싱해두므로
    (=idempotent) 여기선 그냥 오늘 값을 가져다 쓰기만 함."""
    row = _get_or_create_word_of_day()
    if row is None or not row.word:
        return []
    title = "오늘의 단어"
    body = f"{row.word}" + (f" — {row.example}" if row.example else "")

    from sqlmodel import select

    now_kst = datetime.now(KST)
    sent_to: list[int] = []
    now_utc = datetime.now(timezone.utc)
    with db.get_session() as session:
        query = select(db.Device).where(db.Device.word_of_day_enabled)
        if not force:
            query = query.where(db.Device.word_of_day_hour == now_kst.hour)
        devices = session.exec(query).all()
        for device in devices:
            if not force and device.last_word_of_day_sent_at is not None:
                last_sent = device.last_word_of_day_sent_at
                if last_sent.tzinfo is None:
                    last_sent = last_sent.replace(tzinfo=timezone.utc)
                if (now_utc - last_sent).total_seconds() < DIGEST_DEDUPE_WINDOW_SECONDS:
                    continue
            if _send_push(device, title, body, session):
                continue  # 토큰 만료로 기기 자체가 삭제됨
            device.last_word_of_day_sent_at = now_utc
            session.add(device)
            sent_to.append(device.id)
        session.commit()
    return sent_to


async def _digest_loop() -> None:
    while True:
        await asyncio.sleep(DIGEST_CHECK_INTERVAL_SECONDS)
        await asyncio.to_thread(_digest_check)
        await asyncio.to_thread(_word_of_day_alert_check)


def _run_cluster_audit() -> int:
    """지금 캐시(_cache)의 클러스터들을 LLM으로 감사해서 의심되는 것들을
    db.ClusterAuditFinding에 저장함. 30분 라이브 클러스터링은 전혀 안
    건드리는 별도 읽기 전용 점검 — 반환값은 이번에 찾은 개수.

    2026-09-11: 이슈가 200개 넘으면 배치가 십수 개라 전체를 다 처리하는 데
    몇 분씩 걸림 — 배치마다 바로 커밋해서, 중간에 서버가 재시작되거나
    (배포 중 자주 그럼) 요청이 타임아웃나도 그때까지 찾은 건 안 날아가게
    함(원래는 끝까지 다 돈 다음 한 번에 저장했는데, 그러다 통째로 유실된
    적이 있었음).

    수동 테스트용으로 POST /admin/cluster-audit/run에서도 이 함수를
    그대로 씀(스케줄 시간까지 안 기다리고 바로 돌려볼 수 있게)."""
    clusters = [
        {
            "issue_id": issue_id,
            "keyword": c["keyword"],
            "category": c["category"],
            "titles": [a["title"] for a in c.get("articles", [])],
        }
        for issue_id, c in _cache.items()
    ]

    today = datetime.now(KST).strftime("%Y-%m-%d")
    total_findings = 0
    for batch in cluster_audit.iter_batches(clusters):
        findings = cluster_audit.audit_one_batch(batch)
        if not findings:
            continue
        with db.get_session() as session:
            for f in findings:
                c = _cache.get(f["issue_id"])
                session.add(
                    db.ClusterAuditFinding(
                        date=today,
                        issue_id=f["issue_id"],
                        keyword=c["keyword"] if c else "",
                        category=c["category"] if c else "",
                        problem_type=f["problem_type"],
                        detail=f["detail"],
                        suggested_fix=f.get("suggested_fix", ""),
                    )
                )
            session.commit()
        total_findings += len(findings)

    with db.get_session() as session:
        # 오늘 이미 실행했다는 마커 — 재시작해도 하루에 두 번 안 돌게 함.
        existing_run = session.get(db.ClusterAuditRun, today)
        if existing_run:
            existing_run.finding_count = total_findings
        else:
            session.add(db.ClusterAuditRun(date=today, finding_count=total_findings))
        session.commit()
    return total_findings


def _cluster_audit_check() -> bool:
    """지금 KST 시각이 CLUSTER_AUDIT_HOUR_KST이고 오늘 아직 안 돌았으면
    실행함. 실행했으면 True."""
    today = datetime.now(KST).strftime("%Y-%m-%d")
    if datetime.now(KST).hour != CLUSTER_AUDIT_HOUR_KST:
        return False
    with db.get_session() as session:
        if session.get(db.ClusterAuditRun, today) is not None:
            return False
    _run_cluster_audit()
    return True


async def _cluster_audit_loop() -> None:
    while True:
        await asyncio.sleep(CLUSTER_AUDIT_CHECK_INTERVAL_SECONDS)
        await asyncio.to_thread(_cluster_audit_check)


async def _word_of_day_loop() -> None:
    """오늘의 단어를 미리 계산해두는 백그라운드 루프.

    원래는 GET /word-of-day를 그날 처음 부르는 사람이 계산까지 그
    자리에서 기다렸음(사전 API 순차 호출 최대 15번 + LLM 1번이라 꽤
    걸림) — 서버 재시작 직후라서 느린 게 아니라 매일 첫 요청마다
    반복되는 구조적인 문제였음. `_get_or_create_word_of_day`는 이미
    있으면 그냥 반환하는 idempotent 함수라, 여기서 주기적으로 미리
    불러두면 실제 유저는 거의 항상 DB에 이미 저장된 값만 받아감."""
    while True:
        await asyncio.to_thread(_get_or_create_word_of_day)
        await asyncio.sleep(WORD_OF_DAY_CHECK_INTERVAL_SECONDS)


async def _stock_catalog_refresh_loop() -> None:
    """관심 종목 자동완성용 SEC 티커 카탈로그를 하루 한 번 다시 받아옴
    (stocks.refresh_sec_catalog 참고) — 서버 시작 시 첫 캐싱은
    stocks._fetch_sec_catalog()가 요청 들어올 때 알아서 하므로, 여기선
    그 다음부터의 주기적 갱신만 담당함(그래서 sleep을 먼저 함)."""
    while True:
        await asyncio.sleep(STOCK_CATALOG_REFRESH_INTERVAL_SECONDS)
        await asyncio.to_thread(stocks.refresh_sec_catalog)


@asynccontextmanager
async def lifespan(app: FastAPI):
    db.init_db()
    await refresh_cache()  # 첫 요청부터 데이터가 있도록 시작 시 한 번 동기적으로 채움
    refresh_task = asyncio.create_task(_refresh_loop())
    digest_task = asyncio.create_task(_digest_loop())
    cluster_audit_task = asyncio.create_task(_cluster_audit_loop())
    word_of_day_task = asyncio.create_task(_word_of_day_loop())
    stock_catalog_task = asyncio.create_task(_stock_catalog_refresh_loop())
    yield
    refresh_task.cancel()
    digest_task.cancel()
    cluster_audit_task.cancel()
    word_of_day_task.cancel()
    stock_catalog_task.cancel()


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
    image: str | None = None


class IssueSummary(BaseModel):
    id: str
    keyword: str
    keywords: list[str]
    category: str
    representative_title: str
    article_count: int
    outlet_count: int
    # 2026-09-08: "이슈 추이" 배지("N일째 보도 중")용 — 진짜 일별 그래프를
    # 그릴 히스토리 데이터는 없어서(db.py의 prune_old_issues 문서 참고,
    # 예전에 "의미없다"고 판단해서 안 만들기로 함) 대신 이 이슈 id가 DB에
    # 처음 잡힌 시각만 노출. _cache는 재수집마다 새로 만들어지는 딕셔너리라
    # 여기 안 들어있고, refresh_cache()가 DB에서 읽어와 채워줌.
    first_seen_at: str | None = None


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
        first_seen_at=c.get("first_seen_at"),
    )


def _to_detail(issue_id: str, c: dict) -> IssueDetail:
    return IssueDetail(
        **_to_summary(issue_id, c).model_dump(),
        outlets=[OutletBreakdown(outlet=o, count=n) for o, n in c["outlets"].items()],
        articles=[
            ArticleOut(
                outlet=a["outlet"],
                title=a["title"],
                link=a.get("link", ""),
                published=a.get("published"),
                image=a.get("image"),
            )
            for a in c["articles"]
        ],
    )


# 2026-09-07: 기사 썸네일 이미지용 프록시 — Flutter 웹(CanvasKit 렌더러)이
# CORS 허용 헤더 없는 이미지는 못 그림(실측 확인: 연합뉴스 이미지 서버가
# Access-Control-Allow-Origin을 아예 안 보냄 — 브라우저 <img> 태그로는
# 잘 뜨는데 CanvasKit 캔버스에 텍스처로 올릴 때만 막힘). 서버가 대신
# 받아와서 CORS 허용 헤더를 붙여 다시 내려줌. 아무 URL이나 프록시하면
# SSRF/무단 대역폭 사용 통로가 될 수 있어서, 실제 수집 중인 매체
# 도메인만 허용함(sources.py의 RSS_SOURCES와 대응).
_ALLOWED_IMAGE_DOMAINS = (
    "yna.co.kr", "mt.co.kr", "sbs.co.kr", "donga.com", "ohmynews.com",
    "mk.co.kr", "hani.co.kr", "khan.co.kr", "seoul.co.kr",
    # 2026-09-26: 헤럴드경제(10번째 매체, 2026-09-20 추가)가 여기 빠져있어서
    # 이미지 프록시가 계속 403(domain not allowed)을 내고 있었음 — 실제
    # 원인은 헤럴드경제 쪽 핫링크 방지가 아니라 그냥 이 허용 목록에
    # 추가를 깜빡한 것.
    "heraldcorp.com",
)


@app.get("/image-proxy")
async def image_proxy(url: str):
    host = urlparse(url).hostname or ""
    if not any(host == d or host.endswith(f".{d}") for d in _ALLOWED_IMAGE_DOMAINS):
        raise HTTPException(status_code=403, detail="domain not allowed")
    try:
        res = await asyncio.to_thread(requests.get, url, headers={"User-Agent": "Mozilla/5.0"}, timeout=8)
        res.raise_for_status()
    except Exception as e:  # noqa: BLE001 - 이미지 하나 실패해도 프론트가 텍스트만 보여주면 됨
        raise HTTPException(status_code=502, detail=f"failed to fetch image: {e}") from e
    return Response(
        content=res.content,
        media_type=res.headers.get("Content-Type", "image/jpeg"),
        headers={"Access-Control-Allow-Origin": "*", "Cache-Control": "public, max-age=86400"},
    )


@app.get("/health")
async def health():
    return {
        "status": "ok" if _cache else "warming_up",
        "issue_count": len(_cache),
        "last_refresh": _last_refresh,
        "last_error": _last_error,
    }


@app.get("/sources")
async def get_sources(response: Response):
    """2026-09-26: 설정 화면 "앱 정보"에 "이 앱이 어떤 매체를 모아 보여주는지"
    보여주려고 추가 — sources.py(코드테이블)의 실제 수집 중인 매체만
    노출함(political_leaning 등 내부 참고용 메타데이터는 뺌 — 예전에
    "매체 성향 필터" UI를 만들었다가 애초에 성향별 채팅방 자체를 안
    하기로 하면서 제거한 적 있어서, 성향 관련 정보는 일반 사용자
    화면에 다시 노출하지 않음). 코드 배포로만 바뀌는 정적 목록이라
    길게 캐싱해도 안전함."""
    response.headers["Cache-Control"] = "public, max-age=3600"
    return [{"outlet": s["outlet"], "category": s["category"]} for s in sources.RSS_SOURCES]


@app.get("/categories")
async def get_categories(response: Response):
    # 2026-09-26: 서버가 30분마다만 캐시를 갱신하는데(_cache) 이 엔드포인트는
    # Cache-Control이 없어서 Cloudflare가 매 요청마다 도쿄 원본까지 왕복시킴
    # (cf-cache-status: DYNAMIC 실측 확인). 30분 갱신 주기보다 훨씬 짧은
    # max-age로 안전하게 엣지 캐싱만 열어줌 — 첫 로드 속도 개선.
    response.headers["Cache-Control"] = "public, max-age=60"
    return Counter(c["category"] for c in _cache.values())


@app.get("/stats")
async def get_stats(response: Response):
    """홈 화면 마스트헤드 통계용("전체기사"/이슈 수). 캐시가 이미 메모리에
    있어서 집계만 하는 거라 가벼움 — /trending?limit=1000처럼 이슈 수백
    개를 기사까지 통째로 내려받을 필요가 없음(2026-08-24: 그렇게 했다가
    첫 화면 로딩이 느려졌다는 피드백을 받고 이 엔드포인트로 분리함)."""
    response.headers["Cache-Control"] = "public, max-age=60"
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
async def search_issues(
    response: Response,
    q: str = "",
    limit: int = Query(60, ge=1, le=1000),
    category: str | None = None,
):
    """대표 키워드/보조 키워드/대표 헤드라인에 부분 일치하는 이슈 요약만
    내려줌(기사 목록 제외 — 넓은 검색어일 때 타이핑마다 무거워지는 걸
    막으려고, 2026-08-24 실측 피드백).

    2026-08-25: q를 빈 문자열로도 부를 수 있게 함(전체 매칭) — 클라이언트가
    검색할 때마다 서버를 부르는 대신, 가벼운 요약 목록 전체를 한 번만
    받아서 타이핑마다 로컬에서 걸러내게 하려고("이슈판" 프로토타입만큼
    검색이 즉각적이지 않다는 피드백. 서버 호출을 매번 하면 로컬 필터보다
    느릴 수밖에 없어서, 데이터를 가볍게 만들고 클라이언트가 들고 있는
    쪽으로 다시 바꿈)."""
    response.headers["Cache-Control"] = "public, max-age=60"
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
    response: Response,
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
    response.headers["Cache-Control"] = "public, max-age=60"
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
async def get_stock_catalog(response: Response):
    """2026-09-06: "티커를 미리 알고 있어야 하는 게 불편하다"는 피드백으로
    추가 — 종목 추가 시 자동완성 검색용. /search와 같은 패턴으로 전체를
    한 번에 내려주고 클라이언트가 타이핑마다 로컬에서 걸러냄."""
    # 2026-09-26: 코드 배포로만 바뀌는 정적 목록이라 길게 캐싱해도 안전함.
    response.headers["Cache-Control"] = "public, max-age=3600"
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
                    "quote": _stock_quote_cache.get(w.ticker),
                }
            )
        return result


@app.get("/fx/usd-krw")
async def get_usd_krw_rate(response: Response):
    """2026-09-07: 관심 종목 가격을 "탭하면 원화로" 토글하는 기능용 —
    환율은 자주 안 바뀌니까 하루 단위 캐시(quotes.fetch_usd_krw_rate,
    refresh_cache에서 갱신)만 읽음. 아직 한 번도 못 가져왔으면(서버
    막 시작 직후 등) 503."""
    if _usd_krw_rate is None:
        raise HTTPException(status_code=503, detail="exchange rate not available yet")
    # 2026-09-26: 서버도 하루 단위로만 갱신하니 엣지에서도 그만큼 캐싱 가능.
    response.headers["Cache-Control"] = "public, max-age=3600"
    return {"usd_krw": _usd_krw_rate}


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
    if ticker not in _stock_quote_cache:
        quote = await asyncio.to_thread(quotes.fetch_quote, ticker)
        if quote is not None:
            _stock_quote_cache[ticker] = quote
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
    """매일 정해진 시간에 오늘의 트렌드 요약을 푸시로 보내는 기능의 설정
    저장. 2026-09-20부터 실제 발송(FCM)도 됨 — 서버에
    GOOGLE_APPLICATION_CREDENTIALS(Firebase 서비스 계정 키)가 설정돼
    있으면 진짜로 나가고, 없으면 로그만 찍는 스텁으로 조용히 동작함
    (_send_digest 참고). 기기당 하루 1회."""
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


class KeywordAlertIn(BaseModel):
    enabled: bool
    quiet_start: int
    quiet_end: int


def _keyword_alert_dict(device: db.Device) -> dict:
    return {
        "device_id": device.id,
        "keyword_alert_enabled": device.keyword_alert_enabled,
        "keyword_alert_quiet_start": device.keyword_alert_quiet_start,
        "keyword_alert_quiet_end": device.keyword_alert_quiet_end,
    }


@app.put("/devices/{device_id}/keyword-alert")
async def set_keyword_alert(device_id: int, body: KeywordAlertIn):
    """"관심 이슈 알림" — 이 기기가 등록한 관심 키워드와 매칭되는 새
    이슈가 뜨면 알림(word_of_day-alert와 같은 단계 구성).
    2026-09-26: 옵션만 많고 실제 발송이 없던 "실시간 트렌드 알림"(6개
    설정)을 걷어내고 대신 이걸로 대체함 — 관심 키워드 화면이 이미 있으니
    새 UI 없이 토글 하나로 "그 키워드에 새 소식 뜨면 알려줘"가 됨.
    quiet_start/quiet_end("조용한 시간대")만 그 6개 중 유일하게 실제
    쓸모 있던 옵션이라 같이 가져옴 — _in_quiet_hours 참고."""
    if not (0 <= body.quiet_start <= 23) or not (0 <= body.quiet_end <= 23):
        raise HTTPException(status_code=422, detail="quiet hours must be 0-23")
    with db.get_session() as session:
        device = session.get(db.Device, device_id)
        if device is None:
            raise HTTPException(status_code=404, detail="device not registered")
        device.keyword_alert_enabled = body.enabled
        device.keyword_alert_quiet_start = body.quiet_start
        device.keyword_alert_quiet_end = body.quiet_end
        session.add(device)
        session.commit()
        return _keyword_alert_dict(device)


@app.get("/devices/{device_id}/keyword-alert")
async def get_keyword_alert(device_id: int):
    with db.get_session() as session:
        device = session.get(db.Device, device_id)
        if device is None:
            raise HTTPException(status_code=404, detail="device not registered")
        return _keyword_alert_dict(device)


@app.post("/devices/{device_id}/keyword-alert/run")
async def run_keyword_alert_check(device_id: int):
    """개발/테스트용 — 새 이슈가 실제로 뜨길 기다리지 않고, 지금 캐시에
    있는 이슈 전체를 대상으로 이 기기의 관심 키워드와 매칭해서 즉시
    발송함(운영 로직인 _check_keyword_alerts는 refresh_cache 직후 "새로
    생긴 이슈"만 대상으로 함 — 매칭 기준은 동일). keyword_alert_enabled
    여부와 무관하게 테스트 목적으로 보냄."""

    def _run() -> dict:
        from sqlmodel import select

        with db.get_session() as session:
            device = session.get(db.Device, device_id)
            if device is None:
                raise HTTPException(status_code=404, detail="device not registered")
            keywords = [
                w.keyword
                for w in session.exec(
                    select(db.DeviceKeywordWatch).where(db.DeviceKeywordWatch.device_id == device_id)
                ).all()
            ]
            if not keywords:
                return {"sent": False, "reason": "등록된 관심 키워드가 없어요"}
            matched = _matching_issues(keywords, _cache.keys())
            if not matched:
                return {"sent": False, "reason": "지금 캐시에서 매칭되는 이슈가 없어요"}
            title, body = _keyword_alert_message(matched)
            _send_push(device, title, body, session)
            session.commit()
            return {"sent": True, "title": title, "body": body}

    return await asyncio.to_thread(_run)


@app.get("/digest/preview")
async def digest_preview():
    """2026-09-10: 실제 발송(FCM)은 아직 서비스 계정 키가 없어서 못 붙였는데,
    "그럼 도대체 뭐가 발송되는거야"라는 질문에 답하려고 만든 엔드포인트 —
    _build_digest_text()가 지금 이 순간 만들어내는 텍스트를 그대로 보여줌
    (발송/기기 조회 등 부수효과 전혀 없음, 설정 화면의 "미리보기"에서 씀)."""
    return {"text": _build_digest_text()}


def _get_or_create_word_of_day() -> db.WordOfDay | None:
    """오늘(KST) 단어가 이미 골라져 있으면 그대로 재사용하고, 없으면 지금
    캐시에서 하나 뽑아 저장함 — 재계산 주기(30분)마다 바뀌면 "오늘의
    단어"라는 말이 무색해지니 하루 한 번만 고름."""
    today = datetime.now(KST).strftime("%Y-%m-%d")
    with db.get_session() as session:
        existing = session.get(db.WordOfDay, today)
        if existing is not None:
            return existing
        picked = word_of_day.pick_word(_cache)
        if picked is None:
            return None
        word, example, definition = picked
        row = db.WordOfDay(date=today, word=word, example=example, definition=definition)
        session.add(row)
        session.commit()
        session.refresh(row)
        return row


@app.get("/word-of-day")
async def get_word_of_day():
    """2026-09-11: 오늘 기사에서 뽑은 단어 + 예문 + 뜻풀이(국립국어원
    API 연동 전까지는 null). 설정 화면의 "오늘의 단어" 미리보기에서 씀."""
    row = await asyncio.to_thread(_get_or_create_word_of_day)
    if row is None:
        return {"date": None, "word": None, "example": None, "definition": None}
    return {"date": row.date, "word": row.word, "example": row.example, "definition": row.definition}


class WordOfDayAlertIn(BaseModel):
    enabled: bool
    hour: int


def _word_of_day_alert_dict(device: db.Device) -> dict:
    return {
        "device_id": device.id,
        "word_of_day_enabled": device.word_of_day_enabled,
        "word_of_day_hour": device.word_of_day_hour,
    }


@app.put("/devices/{device_id}/word-of-day-alert")
async def set_word_of_day_alert(device_id: int, body: WordOfDayAlertIn):
    """오늘의 단어 알림 — 2026-09-26: "오늘의 이슈팝이랑 왜 시각을 못
    고르냐"는 피드백으로, 서버 전체 고정 9시에서 digest_hour와 같은
    기기별 시각 선택으로 바꿈."""
    if not (0 <= body.hour <= 23):
        raise HTTPException(status_code=422, detail="hour must be 0-23")
    with db.get_session() as session:
        device = session.get(db.Device, device_id)
        if device is None:
            raise HTTPException(status_code=404, detail="device not registered")
        device.word_of_day_enabled = body.enabled
        device.word_of_day_hour = body.hour
        session.add(device)
        session.commit()
        return _word_of_day_alert_dict(device)


@app.get("/devices/{device_id}/word-of-day-alert")
async def get_word_of_day_alert(device_id: int):
    with db.get_session() as session:
        device = session.get(db.Device, device_id)
        if device is None:
            raise HTTPException(status_code=404, detail="device not registered")
        return _word_of_day_alert_dict(device)


@app.post("/digest/run")
async def run_digest_check():
    """개발/테스트용 — 지금 KST 시각이 되길 기다리지 않고 다이제스트
    스케줄러를 즉시 한 번 실행함(5분마다 자동으로도 돌긴 함). Firebase
    자격증명이 서버에 설정돼 있으면 실제로 발송되고, 없으면 로그만
    찍는 스텁으로 동작함(_send_digest 참고)."""
    sent_to = await asyncio.to_thread(_digest_check)
    return {"checked_hour_kst": datetime.now(KST).hour, "sent_to_device_ids": sent_to}


@app.post("/word-of-day/alert-run")
async def run_word_of_day_alert_check(force: bool = False):
    """개발/테스트용 — 기기별 설정 시각까지 기다리지 않고 즉시 한 번
    실행함. force=true면 시각 일치 여부·중복방지 둘 다 무시하고
    무조건 발송함(그 외엔 /digest/run과 같은 규칙)."""
    sent_to = await asyncio.to_thread(_word_of_day_alert_check, force)
    return {"checked_hour_kst": datetime.now(KST).hour, "sent_to_device_ids": sent_to}


_cluster_audit_running = False


async def _run_cluster_audit_background() -> None:
    global _cluster_audit_running
    try:
        await asyncio.to_thread(_run_cluster_audit)
    finally:
        _cluster_audit_running = False


@app.post("/admin/cluster-audit/run")
async def run_cluster_audit_now():
    """개발/테스트용 — 새벽 스케줄(CLUSTER_AUDIT_HOUR_KST)까지 안 기다리고
    지금 캐시로 바로 감사를 돌림. 초반이라 버그를 빨리 많이 찾아야 해서
    (2026-09-11) 수동으로 여러 번 돌려볼 수 있게 남겨둠 — 오늘 이미
    스케줄로 실행됐어도 이 엔드포인트는 상관없이 또 돌림(마커 갱신됨).

    2026-09-11: 이슈 200개 넘으면 배치가 십수 개라 몇 분 걸리는데, 끝날
    때까지 기다렸다 응답하면 nginx/Cloudflare 프록시 타임아웃(60초)에
    걸려서 504가 남 — 그래서 백그라운드로 던져놓고 바로 응답함. 진행
    상황은 GET /admin/cluster-audit/findings로 중간중간 확인하면 됨
    (배치마다 바로 커밋되니까 도는 중에도 그때까지 찾은 게 보임)."""
    global _cluster_audit_running
    if _cluster_audit_running:
        return {"status": "already_running", "issue_count": len(_cache)}
    _cluster_audit_running = True
    asyncio.create_task(_run_cluster_audit_background())
    return {"status": "started", "issue_count": len(_cache)}


@app.get("/admin/cluster-audit/status")
async def cluster_audit_status():
    return {"running": _cluster_audit_running}


@app.get("/admin/cluster-audit/findings")
async def list_cluster_audit_findings(reviewed: bool | None = None, limit: int = Query(100, le=500)):
    """검토 대기열 조회 — reviewed=false로 필터하면 아직 안 본 것만."""
    from sqlmodel import select

    with db.get_session() as session:
        stmt = select(db.ClusterAuditFinding).order_by(db.ClusterAuditFinding.created_at.desc()).limit(limit)
        if reviewed is not None:
            stmt = stmt.where(db.ClusterAuditFinding.reviewed == reviewed)
        rows = session.exec(stmt).all()
        return [
            {
                "id": r.id,
                "date": r.date,
                "issue_id": r.issue_id,
                "keyword": r.keyword,
                "category": r.category,
                "problem_type": r.problem_type,
                "detail": r.detail,
                "suggested_fix": r.suggested_fix,
                "reviewed": r.reviewed,
            }
            for r in rows
        ]


@app.put("/admin/cluster-audit/findings/{finding_id}")
async def mark_cluster_audit_finding_reviewed(finding_id: int):
    """검토 완료 표시(진짜 버그로 확인해서 규칙/회귀 테스트에 반영했든,
    오탐이라 넘기기로 했든 — 어느 쪽이든 "봤음" 표시만 함)."""
    with db.get_session() as session:
        finding = session.get(db.ClusterAuditFinding, finding_id)
        if finding is None:
            raise HTTPException(status_code=404, detail="finding not found")
        finding.reviewed = True
        session.add(finding)
        session.commit()
        return {"id": finding_id, "reviewed": True}


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


# 2026-09-22: /feedback 조회 화면(피드백함)에 걸어두는 관리자 인증.
# 계정은 하나뿐이라 별도 로그인 화면/세션 없이 HTTP Basic으로 충분함 —
# 값은 systemd env.conf(ADMIN_USERNAME/ADMIN_PASSWORD)에만 두고 코드에는
# 안 넣음. 둘 중 하나라도 서버에 설정 안 돼 있으면(로컬 개발 등) 그냥
# 열어주는 대신 항상 401을 돌려줌 — fail-open으로 두면 설정을 깜빡했을 때
# 피드백이 그대로 공개돼버림.
_admin_security = HTTPBasic()
_ADMIN_USERNAME = os.environ.get("ADMIN_USERNAME")
_ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD")


def _require_admin(credentials: HTTPBasicCredentials = Depends(_admin_security)) -> None:
    unauthorized = HTTPException(status_code=401, detail="unauthorized", headers={"WWW-Authenticate": "Basic"})
    if _ADMIN_USERNAME is None or _ADMIN_PASSWORD is None:
        raise unauthorized
    valid_user = secrets.compare_digest(credentials.username, _ADMIN_USERNAME)
    valid_pass = secrets.compare_digest(credentials.password, _ADMIN_PASSWORD)
    if not (valid_user and valid_pass):
        raise unauthorized


class FeedbackIn(BaseModel):
    device_id: int | None = None
    message: str
    contact_email: str | None = None


@app.post("/feedback")
@limiter.limit("5/hour")
async def submit_feedback(request: Request, body: FeedbackIn):
    """베타 "고객의 소리" — 답장 없는 일방향 제출. 로그인 없이도 보낼 수
    있음(device_id는 선택, 있으면 어느 기기에서 왔는지 참고용).
    2026-09-22: 설정 화면 "문의하기"가 mailto: 대신 이 엔드포인트를
    부르는 인앱 폼으로 바뀌면서 무분별 제출 방지용 rate limit(IP당
    시간당 5건)을 걸고, 선택 입력으로 contact_email을 받음(있으면
    직접 답장할 때 씀 — 답장 자동화는 아직 없음)."""
    message = body.message.strip()
    if not message:
        raise HTTPException(status_code=422, detail="message must not be empty")
    contact_email = body.contact_email.strip() if body.contact_email else None
    if contact_email and not _EMAIL_RE.match(contact_email):
        raise HTTPException(status_code=422, detail="invalid contact_email")
    with db.get_session() as session:
        fb = db.Feedback(device_id=body.device_id, message=message, contact_email=contact_email or None)
        session.add(fb)
        session.commit()
        session.refresh(fb)
        return {"id": fb.id, "created_at": fb.created_at}


@app.get("/feedback")
async def list_feedback(_: None = Depends(_require_admin)):
    """개발용 — 제출된 피드백을 최신순으로 확인(관리자 화면이 따로
    없어서 지금은 그냥 API로 직접 조회)."""
    with db.get_session() as session:
        from sqlmodel import select

        items = session.exec(select(db.Feedback).order_by(db.Feedback.created_at.desc())).all()
        return [
            {
                "id": f.id,
                "device_id": f.device_id,
                "message": f.message,
                "contact_email": f.contact_email,
                "created_at": f.created_at,
            }
            for f in items
        ]


@app.get("/privacy", response_class=HTMLResponse)
async def privacy_policy():
    """앱스토어/플레이스토어 제출용 개인정보처리방침 — 정적 페이지라
    DB/인증 없이 그냥 반환함. 2026-09-26 작성: 이 시점에 앱이 실제로
    수집하는 항목만 정직하게 반영함(계정/로그인 기능은 백엔드에 API는
    있지만 앱 화면에 아직 연결 안 해서 실사용자는 안 거치므로 여기
    안 적음 — 나중에 붙이면 이 페이지도 같이 갱신해야 함). 법률
    자문을 대신하지 않는 초안이라는 점을 페이지 자체에도 명시함."""
    page_html = """<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>개인정보처리방침 — Issue Pop</title>
<style>
  body { font-family: -apple-system, "Malgun Gothic", sans-serif; background: #EEF1EA;
         color: #232A20; max-width: 680px; margin: 0 auto; padding: 32px 20px 60px; line-height: 1.6; }
  h1 { font-size: 22px; margin-bottom: 4px; }
  .updated { color: #8B9280; font-size: 13px; margin-bottom: 24px; }
  h2 { font-size: 16px; margin-top: 28px; margin-bottom: 8px; color: #35503F; }
  p, li { font-size: 14px; }
  ul { padding-left: 20px; }
  table { width: 100%; border-collapse: collapse; margin: 8px 0; font-size: 13px; }
  th, td { text-align: left; padding: 8px; border: 1px solid #D7DBC9; }
  th { background: #E4E9DA; }
  .contact { background: #fff; border: 1px solid #D7DBC9; border-radius: 10px; padding: 14px; margin-top: 8px; }
</style>
</head>
<body>
  <h1>개인정보처리방침</h1>
  <p class="updated">시행일자: 2026년 9월 26일</p>

  <p>Issue Pop(이하 "이슈판")은 이용자의 개인정보를 소중히 여기며,
  「개인정보 보호법」 등 관련 법령을 준수하기 위해 노력합니다. 본
  방침은 이슈판 앱(웹 포함)이 수집하는 정보와 이용 방법을 안내합니다.</p>

  <h2>1. 수집하는 개인정보 항목</h2>
  <p>이슈판은 회원가입이나 로그인 없이 이용할 수 있으며, 계정 정보(이름,
  생년월일, 전화번호 등)를 수집하지 않습니다. 아래 항목만 서비스 제공을
  위해 수집합니다.</p>
  <table>
    <tr><th>항목</th><th>수집 시점</th><th>비고</th></tr>
    <tr><td>기기 식별용 푸시 토큰(또는 임의 토큰)</td><td>앱 최초 실행 시</td>
        <td>알림 발송 대상 식별용. 이름 등 개인 식별 정보 아님</td></tr>
    <tr><td>등록한 관심 키워드·관심 종목(티커)</td><td>이용자가 직접 등록 시</td>
        <td>위 기기 식별자에만 연결됨</td></tr>
    <tr><td>알림 설정(발송 시각, 조용한 시간대 등)</td><td>이용자가 설정 변경 시</td>
        <td>위 기기 식별자에만 연결됨</td></tr>
    <tr><td>문의 내용 및 답장받을 이메일(선택)</td><td>"문의하기" 이용 시</td>
        <td>이메일은 입력한 경우에만 수집되며, 답장 목적에만 사용</td></tr>
    <tr><td>접속 IP, 기기/브라우저 정보</td><td>서비스 이용 시 자동 생성</td>
        <td>부정 이용 방지·오류 분석 목적, 서버 접속 기록에만 보관</td></tr>
  </table>
  <p>"저장한 이슈(즐겨찾기)"는 서버로 전송되지 않고 이용자의 기기
  안에만 저장됩니다.</p>

  <h2>2. 개인정보의 수집 및 이용 목적</h2>
  <ul>
    <li>알림 발송(관심 키워드 소식, 매일 트렌드 요약, 오늘의 단어)</li>
    <li>이용자가 등록한 관심 키워드·종목 관리</li>
    <li>문의 응대 및 답변 발송</li>
    <li>부정 이용 방지, 서비스 오류 확인 및 개선</li>
  </ul>

  <h2>3. 보유 및 이용 기간</h2>
  <p>목적 달성 후 지체 없이 파기합니다. 다만 문의 내역은 답변 완료 후
  일정 기간(최대 1년) 보관 후 파기하며, 관련 법령에서 별도 보관을
  요구하는 경우 그 기간을 따릅니다. 앱을 삭제하면 서버에 남아있던
  해당 기기의 알림 설정·관심 키워드도 더 이상 사용되지 않으며, 일정
  기간 미접속 시 정기적으로 정리됩니다.</p>

  <h2>4. 개인정보의 제3자 제공</h2>
  <p>이슈판은 이용자의 개인정보를 원칙적으로 외부에 제공하지 않습니다.
  다만 알림 발송을 위해 아래 업체에 처리를 위탁합니다.</p>
  <ul>
    <li><b>Google Firebase Cloud Messaging</b> — 푸시 알림 발송 (수탁 정보:
    기기 푸시 토큰)</li>
  </ul>

  <h2>5. 이용자의 권리</h2>
  <p>이용자는 앱 내 설정 화면에서 언제든지 알림을 끄거나 등록한 키워드·
  종목을 삭제할 수 있습니다. 그 외 문의사항은 아래 연락처로 요청해
  주시면 지체 없이 조치합니다.</p>

  <h2>6. 개인정보 보호책임자</h2>
  <div class="contact">
    <p style="margin:0">이메일: contact@issue-pop.com</p>
    <p style="margin:4px 0 0">앱 내 "설정 → 문의하기"로도 연락하실 수 있습니다.</p>
  </div>

  <h2>7. 방침 변경</h2>
  <p>본 방침은 법령·서비스 변경에 따라 수정될 수 있으며, 변경 시 이
  페이지를 통해 공지합니다.</p>
</body>
</html>"""
    return HTMLResponse(content=page_html)


@app.get("/feedback/view", response_class=HTMLResponse)
async def view_feedback(_: None = Depends(_require_admin)):
    """브라우저로 바로 열어서 볼 수 있는 피드백 목록(최신순). 2026-09-22:
    비밀 URL 방식(아는 사람만 열어봄)이던 걸 HTTP Basic 인증으로 바꿈 —
    URL이 새어나가도 계정 없인 못 봄(_require_admin 참고)."""
    with db.get_session() as session:
        from sqlmodel import select

        items = session.exec(select(db.Feedback).order_by(db.Feedback.created_at.desc())).all()

    # SQLite는 timezone 정보 없이 저장해서 읽어오면 naive datetime이 됨
    # (db.now()가 항상 UTC로 저장하니 그걸로 tag만 붙여서 KST로 변환).
    def _kst(dt: datetime) -> str:
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(KST).strftime("%Y-%m-%d %H:%M")

    # 사용자가 직접 입력한 텍스트라 그대로 HTML에 꽂으면 XSS 위험이 있음
    # — 반드시 이스케이프하고 넣음.
    rows = "".join(
        f"""<li class="row">
            <div class="meta">
                <span class="time">{_kst(f.created_at)}</span>
                <span class="device">{'기기 #' + str(f.device_id) if f.device_id else '기기 정보 없음'}</span>
            </div>
            <p class="message">{html.escape(f.message)}</p>
            {f'<p class="contact">답장: {html.escape(f.contact_email)}</p>' if f.contact_email else ''}
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
  .contact {{ font-size: 12px; color: #35503F; margin: 6px 0 0; font-weight: 600; }}
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
