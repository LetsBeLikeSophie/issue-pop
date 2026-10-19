# -*- coding: utf-8 -*-
"""기능별 Anthropic 키 선택 규칙 — `python3 test_llm_keys.py` (네트워크/실제 키 없이)."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import llm
import translate

NAMES = ["ANTHROPIC_API_KEY", "ANTHROPIC_KEY_CATEGORY", "ANTHROPIC_KEY_AUDIT", "ANTHROPIC_KEY_WORDOFDAY",
         "ANTHROPIC_KEY_TRANSLATE", "ANTHROPIC_TRANSLATE_API_KEY"]


def _clear():
    for n in NAMES:
        os.environ.pop(n, None)


def test_feature_key_wins_and_falls_back_to_shared_key():
    _clear()
    assert llm.api_key_for("category") is None  # 아무 키도 없으면 None(호출부가 폴백 처리)

    os.environ["ANTHROPIC_API_KEY"] = "shared"
    assert llm.api_key_for("category") == "shared"  # 기능별 키가 아직 없으면 공용 키(옛 방식 호환)
    assert llm.api_key_for(None) == "shared"

    os.environ["ANTHROPIC_KEY_CATEGORY"] = "cat-key"
    assert llm.api_key_for("category") == "cat-key"
    assert llm.api_key_for("CATEGORY") == "cat-key"  # 대소문자 무관
    assert llm.api_key_for("audit") == "shared"  # 다른 기능은 영향 없음
    _clear()


def test_translate_key_names():
    _clear()
    assert translate._api_key() is None
    os.environ["ANTHROPIC_TRANSLATE_API_KEY"] = "old"
    assert translate._api_key() == "old"  # 예전 이름도 계속 읽음
    os.environ["ANTHROPIC_KEY_TRANSLATE"] = "new"
    assert translate._api_key() == "new"  # 새 규칙 이름이 우선
    _clear()


def test_no_key_means_no_network_call():
    _clear()
    # 키가 없으면 requests까지 가지 않고 바로 None
    assert llm.complete("hi", purpose="category") is None
    assert translate.translate_to_ko("hello") is None


if __name__ == "__main__":
    test_feature_key_wins_and_falls_back_to_shared_key()
    test_translate_key_names()
    test_no_key_means_no_network_call()
    print("test_llm_keys: ALL OK")
