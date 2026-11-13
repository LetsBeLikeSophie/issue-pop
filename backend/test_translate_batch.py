# -*- coding: utf-8 -*-
"""번역 묶음 호출 + 따옴표 처리 테스트(네트워크 없이 _post를 가짜로 바꿔서)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import translate


def test_unwrap_quotes():
    u = translate._unwrap_quotes
    assert u('"애플 상승"') == "애플 상승"                      # 전체를 감싼 건 벗김
    assert u("“애플 상승”") == "애플 상승"
    assert u("스콧 갤러웨이 \"대박 아니면 매도\"") == "스콧 갤러웨이 \"대박 아니면 매도\""  # 끝 따옴표 보존
    assert u("애플, 아이폰 \"예측 어렵다\"") == "애플, 아이폰 \"예측 어렵다\""
    assert u('"완전히 황당하다": IPO 카운트다운') == '"완전히 황당하다": IPO 카운트다운'  # 감싼 게 아님
    assert u("  평범한 제목  ") == "평범한 제목"


def test_translate_many_orders_and_fills_gaps():
    os.environ["ANTHROPIC_KEY_TRANSLATE"] = "k"
    calls = []

    def fake_post(payload, key):
        calls.append(payload)
        # 2번 줄을 일부러 빠뜨림 + 설명 줄 섞기
        return "1. 번역A\n알겠습니다\n3) \"번역C\"\n"

    orig = translate._post
    translate._post = fake_post
    try:
        out = translate.translate_many(["A", "B", "C"])
    finally:
        translate._post = orig
        os.environ.pop("ANTHROPIC_KEY_TRANSLATE", None)
    assert out == ["번역A", None, "번역C"]
    assert len(calls) == 1                      # 3건이 1번 호출
    assert calls[0]["temperature"] == 0


def test_translate_many_chunks_and_failure():
    os.environ["ANTHROPIC_KEY_TRANSLATE"] = "k"
    n = translate.BATCH_SIZE * 2 + 1
    seen = []

    def fake_post(payload, key):
        seen.append(1)
        if len(seen) == 2:
            raise RuntimeError("boom")        # 두 번째 묶음만 실패
        lines = payload["messages"][0]["content"].splitlines()
        return "\n".join(f"{l.split('.')[0]}. ko" for l in lines)

    orig = translate._post
    translate._post = fake_post
    try:
        out = translate.translate_many([f"h{i}" for i in range(n)])
    finally:
        translate._post = orig
        os.environ.pop("ANTHROPIC_KEY_TRANSLATE", None)
    assert len(seen) == 3
    b = translate.BATCH_SIZE
    assert out[:b] == ["ko"] * b
    assert out[b : 2 * b] == [None] * b       # 실패한 묶음은 None
    assert out[2 * b :] == ["ko"]


def test_no_key_no_call():
    os.environ.pop("ANTHROPIC_KEY_TRANSLATE", None)
    os.environ.pop("ANTHROPIC_TRANSLATE_API_KEY", None)
    assert translate.translate_many(["a", "b"]) == [None, None]


if __name__ == "__main__":
    test_unwrap_quotes()
    test_translate_many_orders_and_fills_gaps()
    test_translate_many_chunks_and_failure()
    test_no_key_no_call()
    print("test_translate_batch: ALL OK")
