# -*- coding: utf-8 -*-
"""
DB 스키마 (v0 — SQLite + SQLModel).

유료화 그림(backend/README.md의 "업데이트: 유료화 스키마 설계" 참고)을
염두에 두고 미리 짠 스키마예요. 지금 당장 로그인/결제를 구현하는 건
아니고, 나중에 붙일 때 테이블을 갈아엎지 않아도 되게 자리만 미리
잡아두는 목적이 큼 — `users`/`subscriptions`는 지금 아무도 안 채움.

**로컬 vs 서버 저장 구분** (2026-08-24 논의 결과):
  - 즐겨찾기 자체의 "1차 저장소"는 클라이언트(기기 로컬)로 하기로
    했었음 — 로그인 없이 쓸 수 있게. `user_favorites` 테이블은 나중에
    "로그인한 유저의 기기 간 동기화"가 필요해질 때 쓰는 거라, 지금은
    로그인 붙이기 전까지는 비어있는 게 정상.
  - 반대로 `devices`/`device_keyword_watches`는 처음부터 서버가 알아야
    함(푸시 알림을 서버가 보내야 하니까) — 로그인 없이도 필요한
    유일한 서버 저장소.

**알려진 한계**: `user_favorites.issue_id`가 `issues.id`를 참조하는데,
클러스터링이 30분마다 다시 돌면서 같은 사건도 클러스터 경계가 살짝
바뀌면 id가 안 겹칠 수 있음(그러면 즐겨찾기한 이슈가 다음 갱신 때
"사라져 보임"). v0에서는 감안하고 감 — 나중에 "같은 사건 판정"(기사
겹침 비율로 이전 이슈와 매칭)을 붙이면 해결됨.
"""

from __future__ import annotations

import json
from datetime import datetime, timezone

from sqlmodel import Field, Session, SQLModel, create_engine

DB_PATH = "news_trend.db"
engine = create_engine(f"sqlite:///{DB_PATH}", echo=False)


def now() -> datetime:
    return datetime.now(timezone.utc)


class Issue(SQLModel, table=True):
    __tablename__ = "issues"

    id: str = Field(primary_key=True)  # api.py의 _make_id (기사 링크 해시)
    keyword: str
    keywords_json: str  # ["카카오", "증권가"] 같은 리스트를 JSON 문자열로 저장
    category: str
    representative_title: str
    article_count: int
    outlet_count: int
    first_seen_at: datetime = Field(default_factory=now)
    last_seen_at: datetime = Field(default_factory=now)

    @property
    def keywords(self) -> list[str]:
        return json.loads(self.keywords_json)


class Article(SQLModel, table=True):
    __tablename__ = "articles"

    id: int | None = Field(default=None, primary_key=True)
    issue_id: str = Field(foreign_key="issues.id", index=True)
    outlet: str
    title: str
    link: str
    published_at: str | None = None


class ClusterSummary(SQLModel, table=True):
    """AI 요약 캐시(4번 유료 기능용). 이슈 하나당 1개, 재사용됨 —
    유저가 몇 명이든 LLM은 이슈당 딱 한 번만 호출하기로 한 설계."""

    __tablename__ = "cluster_summaries"

    issue_id: str = Field(primary_key=True, foreign_key="issues.id")
    summary_text: str
    generated_at: datetime = Field(default_factory=now)
    model_version: str = "manual-v0"  # 아직 실제 LLM 연동 전이라 수동 입력 표시


class Device(SQLModel, table=True):
    """로그인 없이도 푸시 알림을 보내려고 필요한 최소 식별자(5번,
    커스텀 키워드 알림용). 계정(User)과는 별개 — 로그인 안 해도 씀.

    digest_hour: "매일 이 시간에 오늘의 트렌드 요약 푸시(배너)를 보내줘"
    설정(2026-08-25 추가). null이면 미설정(끔). 기기당 하루 1회. v0
    한계: 기기의 실제 타임존을 모르니 일단 KST 기준 시(0~23)로 저장함 —
    나중에 해외 사용자를 받게 되면 타임존 필드를 따로 받아야 함.
    **실제 발송(FCM 등)은 아직 연동 안 됨** — 이 필드는 "보낼 준비"까지만.
    """

    __tablename__ = "devices"

    id: int | None = Field(default=None, primary_key=True)
    push_token: str = Field(unique=True, index=True)
    digest_hour: int | None = None
    created_at: datetime = Field(default_factory=now)


class DeviceKeywordWatch(SQLModel, table=True):
    __tablename__ = "device_keyword_watches"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int = Field(foreign_key="devices.id", index=True)
    keyword: str
    created_at: datetime = Field(default_factory=now)


class User(SQLModel, table=True):
    """지금은 아무도 안 채움 — 로그인(소셜 로그인 등) 붙일 때 쓸 자리만
    미리 잡아둠."""

    __tablename__ = "users"

    id: int | None = Field(default=None, primary_key=True)
    auth_provider: str | None = None  # "google", "apple" 등
    auth_provider_id: str | None = None
    created_at: datetime = Field(default_factory=now)


class Subscription(SQLModel, table=True):
    """유료화(1,3,4,7번 기능) — 지금은 안 채움."""

    __tablename__ = "subscriptions"

    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id")
    plan: str  # "free" | "premium"
    status: str  # "active" | "canceled" | "expired"
    started_at: datetime = Field(default_factory=now)
    expires_at: datetime | None = None
    payment_provider: str | None = None  # "app_store" | "play_store" | "stripe"


class UserFavorite(SQLModel, table=True):
    """3번(무제한 즐겨찾기+동기화). 로그인한 유저만 씀 — 비로그인
    즐겨찾기는 클라이언트 로컬 저장이라 이 테이블에 안 들어옴."""

    __tablename__ = "user_favorites"

    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="users.id")
    issue_id: str = Field(foreign_key="issues.id")
    created_at: datetime = Field(default_factory=now)


def init_db() -> None:
    SQLModel.metadata.create_all(engine)


def get_session() -> Session:
    return Session(engine)


def persist_issues(session: Session, clusters_by_id: dict[str, dict]) -> None:
    """클러스터링 결과(캐시)를 DB에 반영. 새 이슈는 기사까지 같이 저장하고,
    이미 있던 이슈는 article_count/outlet_count/last_seen_at만 갱신함
    (같은 id면 기사 구성이 사실상 동일하다고 보고 기사는 다시 안 넣음
    — _make_id 자체가 기사 링크 집합의 해시라서).
    """
    ts = now()
    for issue_id, c in clusters_by_id.items():
        existing = session.get(Issue, issue_id)
        if existing:
            existing.article_count = c["article_count"]
            existing.outlet_count = c["outlet_count"]
            existing.last_seen_at = ts
            session.add(existing)
            continue

        session.add(
            Issue(
                id=issue_id,
                keyword=c["keyword"],
                keywords_json=json.dumps(c["keywords"], ensure_ascii=False),
                category=c["category"],
                representative_title=c["representative_title"],
                article_count=c["article_count"],
                outlet_count=c["outlet_count"],
                first_seen_at=ts,
                last_seen_at=ts,
            )
        )
        for a in c["articles"]:
            session.add(
                Article(
                    issue_id=issue_id,
                    outlet=a["outlet"],
                    title=a["title"],
                    link=a.get("link", ""),
                    published_at=a.get("published"),
                )
            )
    session.commit()
