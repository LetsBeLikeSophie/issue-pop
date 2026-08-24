# -*- coding: utf-8 -*-
"""
sources.py에 등록된 RSS 목록이 지금 시점에 실제로 살아있는지 확인하는 스크립트.

이 저장소를 만든 세션(클라우드 샌드박스)은 뉴스 사이트로 나가는 요청이
막혀 있어서 여기선 못 돌려요. 인터넷이 열려 있는 PC(지금 --live를
실행하신 그 환경)에서 이걸 돌리면 각 매체가 살아있는지, 몇 건이나
들어오는지 바로 알 수 있어요.

실행:
    python3 validate_sources.py

출력 예시:
    [OK]   연합뉴스     기사 32건   샘플: "..."
    [FAIL] 조선일보     응답 없음 / 파싱 실패

전체 결과는 sources_status.json으로도 저장돼서, 나중에 나(Claude)한테
그 파일 내용을 붙여주면 sources.py를 죽은 URL 빼고 정리해줄 수 있어요.
"""

from __future__ import annotations

import json
import time

from fetcher import fetch_outlet
from sources import RSS_SOURCES


def main() -> None:
    results = []
    print(f"{len(RSS_SOURCES)}개 매체 확인 중...\n")

    for source in RSS_SOURCES:
        start = time.time()
        articles = fetch_outlet(source)
        elapsed = time.time() - start

        ok = len(articles) > 0
        status = "OK" if ok else "FAIL"
        sample = articles[0]["title"] if ok else None

        print(f"[{status:4}] {source['outlet']:8}  기사 {len(articles):3}건  ({elapsed:.1f}s)"
              + (f"  샘플: {sample}" if sample else "  → 응답 없음/빈 피드/파싱 실패"))

        results.append(
            {
                "outlet": source["outlet"],
                "url": source["url"],
                "ok": ok,
                "article_count": len(articles),
                "elapsed_sec": round(elapsed, 2),
                "sample_title": sample,
            }
        )

    ok_count = sum(1 for r in results if r["ok"])
    print(f"\n총 {len(results)}개 중 {ok_count}개 살아있음")

    with open("sources_status.json", "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print("상세 결과 → sources_status.json 에 저장됨")


if __name__ == "__main__":
    main()
