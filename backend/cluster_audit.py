# -*- coding: utf-8 -*-
"""
2026-09-11: 클러스터링/키워드/카테고리 품질을 LLM(Haiku)으로 감사.

30분마다 도는 라이브 클러스터링(pipeline.py/clustering.py)은 전혀 안
건드림 — 이건 하루 한 번, 그날 만들어진 클러스터들을 배치로 LLM에 보내서
"키워드가 이 기사 묶음을 잘 대표하는지 / 카테고리가 맞는지 / 안 맞는
기사가 섞였는지"를 점검하고, 의심되는 것만 db.ClusterAuditFinding에
쌓아두는 용도(api.py의 run_cluster_audit 참고). 유저 화면엔 전혀 반영
안 됨 — 사람이 나중에 훑어보고 진짜 버그로 확인되면 test_pipeline.py의
회귀 테스트로 승격시키는 "발견 목록"을 만드는 게 목적.

배치로 묶어서 호출하는 이유: 이슈가 보통 200개 안팎이라 하나씩 부르면
호출이 너무 많아짐 — 한 번에 여러 클러스터를 같이 보여주고 문제 있는
것만 JSON으로 답하게 해서 호출 수를 줄임.
"""

from __future__ import annotations

import json
import re

import llm

_BATCH_SIZE = 12
_MAX_TITLES_PER_CLUSTER = 5


def _build_batch_prompt(batch: list[dict]) -> str:
    lines = []
    for c in batch:
        titles = "\n    ".join(f"- {t}" for t in c["titles"][:_MAX_TITLES_PER_CLUSTER])
        lines.append(
            f'[{c["issue_id"]}] 키워드="{c["keyword"]}" 카테고리="{c["category"]}"\n    {titles}'
        )
    return (
        "다음은 한국어 뉴스 기사들을 자동으로 클러스터링한 결과야(같은 사건/"
        "이슈로 묶인 기사 제목들, 형태소 분석기로 키워드를 뽑고 규칙 기반으로 "
        "카테고리를 붙임). 각 클러스터를 보고 아래 3가지 유형의 문제만 찾아줘 "
        "— 이 3가지 외의 사소한 아쉬움은 무시해:\n\n"
        "1. keyword_truncated: 키워드가 기사 제목에 나오는 더 긴 실제 표현의 "
        "일부만 잘려나온 경우(예: 키워드가 \"김승\"인데 제목엔 \"김승원\"이라고 "
        "나옴 — 사람 이름/기관명/신조어가 형태소 분석 경계를 잘못 잡아서 "
        "잘리는 패턴). suggested_fix에 제목에 실제로 나오는 완전한 형태를 "
        "적어줘.\n"
        "2. article_mismatch: 이 클러스터의 키워드/주제와 실제로는 무관한데 "
        "(그냥 소재나 분위기만 비슷해서) 같이 묶인 기사가 있는 경우 — 서로 "
        "다른 지역/인물/사건인데 섞인 것도 포함. detail에 어떤 제목이 안 "
        "맞는지 적어줘.\n"
        "3. category_mismatch: 카테고리(정치/경제/사회/국제/스포츠/연예/"
        "IT/과학/문화/기타)가 이 기사들 내용과 명백히 안 맞는 경우. "
        "suggested_fix에 더 적합한 카테고리를 적어줘.\n\n"
        + "\n\n".join(lines)
        + "\n\n문제 있는 클러스터만 아래 JSON 배열 형식으로 답해(문제 없으면 "
        "빈 배열 []). 확신 없으면 넣지 마(애매한 건 걸러도 됨). 다른 설명 "
        "없이 JSON만:\n"
        '[{"issue_id": "...", "problem_type": "keyword_truncated|article_mismatch|'
        'category_mismatch", "detail": "왜 문제인지 한국어로 한 문장", '
        '"suggested_fix": "고칠 값(keyword_truncated/category_mismatch만 채우고, '
        'article_mismatch는 빈 문자열)"}]'
    )


_JSON_FENCE_RE = re.compile(r"^```(?:json)?\s*|\s*```$")


def _parse_findings(text: str) -> list[dict]:
    cleaned = _JSON_FENCE_RE.sub("", text.strip())
    try:
        data = json.loads(cleaned)
    except (json.JSONDecodeError, TypeError):
        return []
    if not isinstance(data, list):
        return []
    findings = []
    for item in data:
        if not isinstance(item, dict):
            continue
        if not all(k in item for k in ("issue_id", "problem_type", "detail")):
            continue
        item.setdefault("suggested_fix", "")
        findings.append(item)
    return findings


def iter_batches(clusters: list[dict]) -> list[list[dict]]:
    """클러스터 목록을 _BATCH_SIZE 단위로 나눔 — 호출부(api.py)가 배치마다
    바로 DB에 저장할 수 있게 배치 자체를 노출함(2026-09-11: 전체를 한 번에
    처리하던 audit_batch가 200개 넘는 이슈에선 몇 분씩 걸려서, nginx/
    Cloudflare 프록시 타임아웃에 걸려 중간 결과가 통째로 날아가는 문제가
    있었음 — 배치마다 커밋하도록 api.py 쪽에서 이 함수를 씀)."""
    return [clusters[i : i + _BATCH_SIZE] for i in range(0, len(clusters), _BATCH_SIZE)]


def audit_one_batch(batch: list[dict]) -> list[dict]:
    """배치 하나를 감사해서 문제로 의심되는 것들을 반환. API 키가 없거나
    호출이 실패하면 빈 리스트(전체가 죽지 않게, 호출부가 다음 배치로
    계속 진행함)."""
    prompt = _build_batch_prompt(batch)
    text = llm.complete(prompt, max_tokens=1500)
    if text is None:
        return []
    valid_ids = {c["issue_id"] for c in batch}
    return [f for f in _parse_findings(text) if f["issue_id"] in valid_ids]


def audit_batch(clusters: list[dict]) -> list[dict]:
    """clusters: [{"issue_id", "keyword", "category", "titles"(list[str])}, ...]
    → 문제로 의심되는 것들의 리스트. 배치 수가 적을 때(테스트 등) 한 번에
    쓰기 편하라고 남겨둔 편의 함수 — api.py의 실제 감사 실행은 배치마다
    커밋해야 해서 iter_batches/audit_one_batch를 직접 씀."""
    all_findings: list[dict] = []
    for batch in iter_batches(clusters):
        all_findings.extend(audit_one_batch(batch))
    return all_findings
