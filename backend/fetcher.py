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

import time
from datetime import datetime, timezone
from typing import Any

import feedparser

from sources import RSS_SOURCES


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

    articles = []
    for entry in parsed.entries:
        articles.append(
            {
                "outlet": source["outlet"],
                "category": source.get("category", "종합"),
                "title": getattr(entry, "title", "").strip(),
                "summary": getattr(entry, "summary", "").strip(),
                "link": getattr(entry, "link", ""),
                "published": _to_iso(entry),
            }
        )
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
