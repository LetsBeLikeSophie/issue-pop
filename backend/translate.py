# -*- coding: utf-8 -*-
"""
파파고(네이버 클라우드 플랫폼) 번역 — 2026-09-06 추가.

관심 종목 뉴스가 전부 영어라("이거 어느정도 번역은 해줘야겠는데" 피드백)
헤드라인만 한국어로 옮겨줌. 짧은 텍스트(헤드라인) 번역이 목적이라 무거운
LLM 대신 전용 번역 API를 씀 — 더 저렴하고, 이 작업 자체엔 LLM의 범용
추론 능력이 필요 없음.

인증키(PAPAGO_CLIENT_ID/PAPAGO_CLIENT_SECRET)는 서버의 systemd 서비스
환경변수로만 존재함(/etc/systemd/system/newstrend-api.service.d/env.conf,
git에는 안 올라감) — 로컬에서 돌리려면 같은 이름으로 환경변수를 직접
설정해야 함.

엔드포인트는 NCP APIGW 콘솔에서 발급받은 신규 도메인(papago.apigw.ntruss.com)
을 씀 — 예전에 많이 쓰이던 naveropenapi.apigw.ntruss.com 도메인은 지금
발급받은 키로 403이 남(2026-09-06 실측 확인), 신규 도메인은 정상 동작함.
"""

from __future__ import annotations

import os

import requests

_ENDPOINT = "https://papago.apigw.ntruss.com/nmt/v1/translation"


def translate_to_ko(text: str) -> str | None:
    """영어 텍스트를 한국어로 번역. 키가 없거나(로컬 개발 등) API 호출이
    실패하면 조용히 None — 호출하는 쪽에서 원문을 그대로 보여주면 됨
    (다른 외부 API 연동들과 같은 방어 원칙, api.py의 _fetch_weather 참고)."""
    client_id = os.environ.get("PAPAGO_CLIENT_ID")
    client_secret = os.environ.get("PAPAGO_CLIENT_SECRET")
    if not client_id or not client_secret or not text.strip():
        return None
    try:
        res = requests.post(
            _ENDPOINT,
            headers={
                "X-NCP-APIGW-API-KEY-ID": client_id,
                "X-NCP-APIGW-API-KEY": client_secret,
            },
            data={"source": "en", "target": "ko", "text": text},
            timeout=8,
        )
        res.raise_for_status()
        return res.json()["message"]["result"]["translatedText"]
    except Exception:  # noqa: BLE001 - 번역 실패해도 원문을 보여주면 되니 전체 갱신을 막으면 안 됨
        return None
