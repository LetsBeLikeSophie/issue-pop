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
from datetime import datetime, timedelta, timezone

from sqlmodel import Field, Session, SQLModel, create_engine, delete, select

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
    last_digest_sent_at: 같은 시간대에 중복 발송 안 하려고 스케줄러가
    기록함(api.py의 _digest_check 참고).
    **실제 발송(FCM 등)은 아직 연동 안 됨** — 스케줄러는 "누구한테 언제
    보내야 하는지"만 찾아내고, 실제 발송은 로그만 찍는 스텁으로 남겨둠
    (backend/README.md 참고).
    """

    __tablename__ = "devices"

    id: int | None = Field(default=None, primary_key=True)
    push_token: str = Field(unique=True, index=True)
    digest_hour: int | None = None
    last_digest_sent_at: datetime | None = None  # 같은 시간대에 중복 발송 방지용
    created_at: datetime = Field(default_factory=now)

    # 2026-09-05: 다이제스트(하루 한 번)와 별개로, 새로 뜨거나 급상승한
    # 이슈를 재계산 주기마다 체크해서 알려주는 "주기적 알림" 설정 —
    # UI부터 먼저 만들고, 실제 감지/발송 로직은 다음 단계.
    periodic_alert_enabled: bool = False
    periodic_interval_minutes: int = 60  # 30분 재계산 주기의 배수만 의미 있음(30/60/120/180)
    quiet_hours_start: int = 8  # 이 시각부터
    quiet_hours_end: int = 23  # 이 시각까지만 알림(그 외엔 조용히)
    min_outlet_count: int = 5  # 이 매체 수 이상인 이슈만 알림
    alert_categories_json: str | None = None  # null=전체 카테고리, 아니면 ["정치","경제"] 같은 JSON 배열
    max_daily_alerts: int = 10

    # 2026-09-11: "오늘의 단어"(오늘 기사에서 뽑은 어려운 말 + 뜻풀이) 알림
    # on/off — digest_hour와 마찬가지로 설정 저장까지만, 실제 발송은 아직.
    word_of_day_enabled: bool = False

    @property
    def alert_categories(self) -> list[str] | None:
        return json.loads(self.alert_categories_json) if self.alert_categories_json else None


class DeviceKeywordWatch(SQLModel, table=True):
    __tablename__ = "device_keyword_watches"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int = Field(foreign_key="devices.id", index=True)
    keyword: str
    created_at: datetime = Field(default_factory=now)


class DeviceStockWatch(SQLModel, table=True):
    """2026-09-06: 관심 종목(브랜드) 등록 — S&P500 전체를 미리 다 가져오는
    대신, 기기마다 관심 있는 티커만 등록해서 그것만 가져오는 구조로 함
    (device_keyword_watches와 같은 패턴). 기기가 처음 이 기능을 켤 때
    STARTER_TICKERS로 자동 시드되고, 그 다음부턴 완전히 사용자 편집
    (기본값도 지울 수 있음) — api.py의 _seed_stock_watches 참고."""

    __tablename__ = "device_stock_watches"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int = Field(foreign_key="devices.id", index=True)
    ticker: str
    created_at: datetime = Field(default_factory=now)


class TranslatedHeadline(SQLModel, table=True):
    """2026-09-06: 관심 종목 뉴스(영어) 번역 캐시 — 파파고는 무료 할당량이
    넉넉하지 않아서(하루 단위), 같은 헤드라인을 30분마다 돌아오는 갱신
    주기마다 매번 다시 번역하면 금방 소진됨. cluster_summaries와 같은
    설계(한 번 번역하면 재사용) — 원문 텍스트 해시를 키로 써서 같은
    헤드라인이 여러 티커/여러 번 등장해도 번역 API는 한 번만 호출함
    (stocks.py의 _translate_cached 참고)."""

    __tablename__ = "translated_headlines"

    text_hash: str = Field(primary_key=True)
    original_text: str
    translated_text: str
    translated_at: datetime = Field(default_factory=now)


class WordOfDay(SQLModel, table=True):
    """2026-09-11: "오늘의 단어" — 오늘 수집된 기사 제목에서 뽑은 단어 +
    예문(word_of_day.py의 pick_word 참고). KST 날짜를 기본키로 써서
    하루에 한 번만 고르고(재계산 주기마다 바뀌면 안 되니까) 그 뒤로는
    캐시처럼 재사용함. definition은 국립국어원 표준국어대사전 Open API
    연동 전까지는 null — 연동되면 채워 넣을 자리."""

    __tablename__ = "word_of_day"

    date: str = Field(primary_key=True)  # "2026-09-11" (KST)
    word: str
    example: str
    definition: str | None = None
    created_at: datetime = Field(default_factory=now)


class Feedback(SQLModel, table=True):
    """베타 "고객의 소리" — 답장 기능 없는 일방향 제출함(2026-08-27).
    로그인 없이도 보낼 수 있게 device_id는 선택(있으면 어느 기기에서
    왔는지 참고용, 필수 아님)."""

    __tablename__ = "feedback"

    id: int | None = Field(default=None, primary_key=True)
    device_id: int | None = Field(default=None, foreign_key="devices.id")
    message: str
    created_at: datetime = Field(default_factory=now)


class User(SQLModel, table=True):
    """2026-08-28: 로그인 기능 추가하면서 채워짐. 구글/애플 로그인은
    각각 API 크리덴셜 발급이 필요해서(FCM/LLM 키와 같은 종류의, 사용자가
    직접 해야 하는 일) 당장은 이메일+비밀번호 방식만 구현함 —
    auth_provider/auth_provider_id는 나중에 소셜 로그인 붙일 때 쓸 자리로
    남겨둠(이메일 계정은 이 둘이 null)."""

    __tablename__ = "users"

    id: int | None = Field(default=None, primary_key=True)
    email: str | None = Field(default=None, unique=True, index=True)
    password_hash: str | None = None
    auth_provider: str | None = None  # "google", "apple" 등
    auth_provider_id: str | None = None
    created_at: datetime = Field(default_factory=now)


class UserSession(SQLModel, table=True):
    """로그인 세션. 정식 JWT 대신 그냥 무작위 토큰을 DB에 저장해두고
    맞는지 조회하는 v0 방식 — 세션 만료/갱신 같은 건 아직 없음(로그아웃
    하면 바로 삭제되는 정도). 나중에 필요해지면 만료 시각을 추가하면 됨."""

    __tablename__ = "user_sessions"

    token: str = Field(primary_key=True)
    user_id: int = Field(foreign_key="users.id", index=True)
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


def _migrate_devices_table() -> None:
    """SQLModel.metadata.create_all()은 이미 있는 테이블엔 새 컬럼을
    안 넣어줌 — 이미 배포된 서버의 devices 테이블은 예전 스키마 그대로라
    여기서 직접 ALTER TABLE로 채워줌(있으면 건너뜀, 여러 번 실행해도
    안전함). 기존 행의 새 컬럼은 SQLModel의 기본값으로 채움.
    """
    with engine.connect() as conn:
        existing = {row[1] for row in conn.exec_driver_sql("PRAGMA table_info(devices)").fetchall()}
        additions = {
            "periodic_alert_enabled": "INTEGER NOT NULL DEFAULT 0",
            "periodic_interval_minutes": "INTEGER NOT NULL DEFAULT 60",
            "quiet_hours_start": "INTEGER NOT NULL DEFAULT 8",
            "quiet_hours_end": "INTEGER NOT NULL DEFAULT 23",
            "min_outlet_count": "INTEGER NOT NULL DEFAULT 5",
            "alert_categories_json": "TEXT",
            "max_daily_alerts": "INTEGER NOT NULL DEFAULT 10",
            "word_of_day_enabled": "INTEGER NOT NULL DEFAULT 0",
        }
        for column, ddl in additions.items():
            if column not in existing:
                conn.exec_driver_sql(f"ALTER TABLE devices ADD COLUMN {column} {ddl}")
        conn.commit()


def init_db() -> None:
    SQLModel.metadata.create_all(engine)
    _migrate_devices_table()


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


def prune_old_issues(session: Session, retention_days: int = 3) -> int:
    """오래된 이슈(와 그 기사들)를 지움.

    2026-09-05 실측: 히스토리 기능이 없어서(사용자가 "의미없다"고 판단해서
    안 만들기로 함) 지난 이슈를 읽는 곳이 앱에 하나도 없는데도 DB는
    무한정 쌓이고 있었음 — 배포 8일 만에 이슈 19,465건/기사 48,247건.
    상당수는 진짜 새 사건이 아니라, 재클러스터링마다 이슈 id가 바뀌면서
    "같은 진행 중인 사건이 새 행으로 또 잡히는" 현상 때문(알려진 한계).

    last_seen_at 기준으로 지움 — 진행 중인 이슈는 사이클마다 갱신되니
    안 지워지고, 더 이상 안 잡히는 것만 지워짐. 즐겨찾기(클라이언트 로컬
    저장, user_favorites/cluster_summaries도 실측 결과 둘 다 비어있음)는
    이 DB를 안 참조해서 전혀 영향 없음.
    """
    # id 리스트를 뽑아서 IN(...)에 넣으면 첫 정리 때(누적분이 많아서)
    # SQLite의 변수 개수 제한에 걸릴 수 있어 — 서브쿼리로 한 번에 지움.
    cutoff = now() - timedelta(days=retention_days)
    stale_issue_ids = select(Issue.id).where(Issue.last_seen_at < cutoff)
    session.exec(delete(Article).where(Article.issue_id.in_(stale_issue_ids)))  # type: ignore[arg-type]
    result = session.exec(delete(Issue).where(Issue.last_seen_at < cutoff))  # type: ignore[arg-type]
    session.commit()
    return result.rowcount
