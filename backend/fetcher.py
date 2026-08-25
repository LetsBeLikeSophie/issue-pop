# -*- coding: utf-8 -*-
"""
RSS 수집 모듈.

sources.py에 등록된 피드들을 돌면서 기사를 파싱해 표준 형태의
dict 리스트로 반환해요. 여기서 나온 결과가 clustering.py의 입력이 돼요.

Article 표준 스키마:
{
    "outlet": str,       # 매체명
    "title": str,        # 기사 제목
    "summary": str,       # 요약/본문 일부
    "link": str,          # 원문 링크
    "published": str,     # ISO 8601 문자열 (파싱 실패 시 None)
}
"""

from __future__ import annotations

import html
import time
from datetime import datetime, timedelta, timezone
from typing import Any

import feedparser

from sources import RSS_SOURCES

# "오늘 이슈"여야 하는데 매체 피드에 며칠 지난 기사가 섞여 들어오면
# 클러스터링 결과가 실제보다 부풀려짐(2026-08-25, 실측하며 발견 —
# 이슈 200여 개가 너무 많다는 피드백을 받고 확인해보니 날짜 필터가
# 아예 없었음). 24시간이 아니라 30시간으로 좀 여유를 둔 이유: 새벽에
# 갱신하면 전날 저녁 기사까지는 "오늘 하루치"로 봐도 자연스러움.
MAX_ARTICLE_AGE = timedelta(hours=30)


def _to_iso(entry: Any) -> str | None:
    """feedparser의 published_parsed(time.struct_time)를 ISO 문자열로 변환."""
    struct = getattr(entry, "published_parsed", None) or getattr(entry, "updated_parsed", None)
    if not struct:
        return None
    return datetime.fromtimestamp(time.mktime(struct), tz=timezone.utc).isoformat()


def fetch_outlet(source: dict) -> list[dict]:
    """피드 하나를 가져와 기사 리스트로 변환. 실패해도 예외를 던지지 않고 빈 리스트를 반환해요.

    개별 매체 하나가 죽어도 전체 파이프라인이 멈추면 안 되니까,
    여기서 에러를 흡수하고 로그만 남기는 방어적인 구조로 짰어요.
    """
    try:
        parsed = feedparser.parse(source["url"])
    except Exception as e:  # noqa: BLE001 - 수집 단계는 매체 하나 실패로 전체를 멈추면 안 됨
        print(f"[fetch] {source['outlet']} 실패: {e}")
        return []

    if getattr(parsed, "bozo", 0) and not parsed.entries:
        print(f"[fetch] {source['outlet']} 파싱 실패 또는 빈 피드: {parsed.get('bozo_exception')}")
        return []

    cutoff = datetime.now(timezone.utc) - MAX_ARTICLE_AGE
    articles = []
    skipped_old = 0
    for entry in parsed.entries:
        published = _to_iso(entry)
        # 날짜가 있는데 너무 오래됐으면 제외. 날짜 자체가 없으면(예:
        # 한겨레 RSS는 published/updated 필드가 아예 없음 — feedparser
        # 파싱 실패가 아니라 피드 자체에 없는 것, 2026-08-25 실측 확인)
        # 판단할 근거가 없으니 그냥 포함시킴 — "날짜 없으면 제외"로 했다가
        # 한겨레 기사가 전부(30건) 날아가는 걸 발견해서 이렇게 바꿈.
        if published is not None and datetime.fromisoformat(published) < cutoff:
            skipped_old += 1
            continue
        articles.append(
            {
                "outlet": source["outlet"],
                "category": source.get("category", "종합"),
                "title": html.unescape(getattr(entry, "title", "")).strip(),
                "summary": html.unescape(getattr(entry, "summary", "")).strip(),
                "link": getattr(entry, "link", ""),
                "published": published,
            }
        )
    if skipped_old:
        print(f"[fetch] {source['outlet']}: {len(articles)}건 채택, {skipped_old}건 오래됨(30시간 초과) 제외")
    return articles


def fetch_all(sources: list[dict] = RSS_SOURCES) -> list[dict]:
    """등록된 모든 매체를 순회하며 기사를 모아요.

    프로토타입이라 순차 처리인데, 매체 수가 늘어나면
    concurrent.futures.ThreadPoolExecutor로 병렬화하면 돼요
    (RSS 요청은 I/O bound라 스레드로 충분).
    """
    all_articles: list[dict] = []
    for source in sources:
        all_articles.extend(fetch_outlet(source))
    return all_articles


if __name__ == "__main__":
    # 이 샌드박스는 네트워크가 화이트리스트로 막혀 있어서 여기서 바로 실행하면
    # 대부분 [fetch] ... 실패 로그만 찍힐 거예요 (정상입니다).
    # 실제 서버 환경에서 돌리면 기사 목록이 채워집니다.
    result = fetch_all()
    print(f"총 {len(result)}건 수집")
    for a in result[:5]:
        print(f"- [{a['outlet']}] {a['title']}")
