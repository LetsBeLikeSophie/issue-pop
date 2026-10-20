# -*- coding: utf-8 -*-
"""속보 배지 판정 테스트 — `python3 test_breaking.py`."""
import datetime as dt
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import api

NOW = dt.datetime(2026, 10, 20, 12, 0, tzinfo=dt.timezone.utc)


def art(title, hours_ago, tz=dt.timezone.utc):
    published = (NOW - dt.timedelta(hours=hours_ago)).astimezone(tz).isoformat()
    return {"outlet": "A", "title": title, "link": "x", "published": published}


def cl(*articles):
    return {"articles": list(articles)}


# 최근 [속보] 기사가 있으면 True
assert api._is_breaking(cl(art("[속보] 역삼동 화재", 1)), NOW)
# 다른 괄호/공백 표기도 인정
assert api._is_breaking(cl(art("(속보) 환율 급등", 2)), NOW)
assert api._is_breaking(cl(art("[ 속보 ]“방화범 검거”", 2)), NOW)
# 다른 시간대로 적힌 발행 시각도 같은 순간으로 계산
assert api._is_breaking(cl(art("[속보] A", 5, dt.timezone(dt.timedelta(hours=9)))), NOW)
# 6시간 넘은 속보는 배지 없음
assert not api._is_breaking(cl(art("[속보] 옛날 속보", 7)), NOW)
# 속보 태그가 아닌 일반 단어/제목 중간 표현은 제외
assert not api._is_breaking(cl(art("속보다 정확한 분석", 1)), NOW)
assert not api._is_breaking(cl(art("정부 발표 속보 전문", 1)), NOW)
# 발행 시각이 없거나 읽을 수 없으면 셈하지 않음, 미래 시각도 제외
assert not api._is_breaking(cl({"outlet": "A", "title": "[속보] X", "link": "x", "published": None}), NOW)
assert not api._is_breaking(cl({"outlet": "A", "title": "[속보] X", "link": "x", "published": "어제"}), NOW)
assert not api._is_breaking(cl(art("[속보] X", -3)), NOW)
# 오래된 속보 + 최근 일반 기사 → False, 오래된 일반 + 최근 속보 → True
assert not api._is_breaking(cl(art("[속보] 옛날", 20), art("후속 기사", 1)), NOW)
assert api._is_breaking(cl(art("일반 기사", 20), art("[속보] 방금", 0.5)), NOW)
assert not api._is_breaking({}, NOW)

print("test_breaking: ALL OK")
