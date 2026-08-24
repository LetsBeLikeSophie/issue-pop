# -*- coding: utf-8 -*-
"""
전체 파이프라인: 수집 → 클러스터링 → 트렌드 랭킹 출력.

와이어프레임(Main.dc.html의 "오늘 많이 언급된 키워드",
IssueDetail.dc.html의 "매체별 보도 분포")에 필요한 데이터 형태를
그대로 만들어내는 게 목표예요. 여기서 나오는 JSON을 나중에
FastAPI 같은 걸로 감싸서 API 엔드포인트로 노출하면 플러터 클라이언트가
바로 붙을 수 있어요.

실행:
    python pipeline.py --live     # 실제 RSS 수집 (이 샌드박스에선 네트워크 제한으로 대부분 실패)
    python pipeline.py            # 기본값: sample_data 픽스처로 실행 (클러스터링 로직 검증용)
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from clustering import cluster_articles
from fetcher import fetch_all
from meta_cluster import group_into_super_clusters

SAMPLE_PATH = Path(__file__).parent / "sample_data" / "sample_articles.json"


def load_sample_articles() -> list[dict]:
    with open(SAMPLE_PATH, encoding="utf-8") as f:
        return json.load(f)


def run(live: bool = False, threshold: float = 0.45) -> list[dict]:
    articles = fetch_all() if live else load_sample_articles()
    return cluster_articles(articles, threshold=threshold)


def run_grouped(
    live: bool = False, threshold: float = 0.45, meta_threshold: float = 0.30
) -> list[dict]:
    """이슈 클러스터링 + 2단계(슈퍼그룹) 메타클러스터링까지 한 번에."""
    clusters = run(live=live, threshold=threshold)
    return group_into_super_clusters(clusters, threshold=meta_threshold)


def print_report(clusters: list[dict]) -> None:
    total_articles = sum(c["article_count"] for c in clusters)
    print(f"오늘 총 {total_articles}건 · {len(clusters)}개 이슈로 클러스터링\n")

    for rank, c in enumerate(clusters, start=1):
        print(f"{rank}. {c['keyword']}  (예시 헤드라인: {c['representative_title']})")
        print(f"   기사 {c['article_count']}건 · {c['outlet_count']}개 매체")
        outlets_str = ", ".join(f"{o}({n})" for o, n in list(c["outlets"].items())[:5])
        print(f"   매체별 분포: {outlets_str}")
        print()


def print_grouped_report(super_clusters: list[dict]) -> None:
    total_articles = sum(g["article_count"] for g in super_clusters)
    total_issues = sum(len(g["clusters"]) for g in super_clusters)
    print(f"오늘 총 {total_articles}건 · {total_issues}개 이슈 · {len(super_clusters)}개 슈퍼그룹\n")

    for rank, g in enumerate(super_clusters, start=1):
        print(f"{rank}. [{g['category']}] {g['label']}  ({len(g['clusters'])}개 이슈 묶임)")
        print(f"   기사 {g['article_count']}건 · {g['outlet_count']}개 매체")
        for c in g["clusters"]:
            print(f"     - {c['keyword']} ({c['article_count']}건, {c['outlet_count']}매체)")
        print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="뉴스 트렌드 클러스터링 파이프라인")
    parser.add_argument("--live", action="store_true", help="샘플 데이터 대신 실제 RSS를 수집")
    parser.add_argument("--threshold", type=float, default=0.45, help="클러스터링 유사도 임계값")
    parser.add_argument(
        "--group", action="store_true", help="이슈를 슈퍼그룹으로 한 번 더 묶어서 출력"
    )
    parser.add_argument(
        "--meta-threshold", type=float, default=0.30, help="슈퍼그룹 유사도 임계값(--group 사용 시)"
    )
    parser.add_argument("--json", action="store_true", help="결과를 JSON으로 출력")
    args = parser.parse_args()

    if args.group:
        grouped_result = run_grouped(
            live=args.live, threshold=args.threshold, meta_threshold=args.meta_threshold
        )
        if args.json:
            print(json.dumps(grouped_result, ensure_ascii=False, indent=2))
        else:
            print_grouped_report(grouped_result)
    else:
        result = run(live=args.live, threshold=args.threshold)
        if args.json:
            # articles 안의 published 등은 그대로 두되, 리포트용으로는 요약만 출력
            print(json.dumps(result, ensure_ascii=False, indent=2))
        else:
            print_report(result)
