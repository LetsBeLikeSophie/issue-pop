# -*- coding: utf-8 -*-
"""한글 종목명(stocks.TICKER_KO) 점검 — python3 test_stock_names.py"""

import re

import stocks


def test_every_curated_ticker_has_korean_name():
    missing = sorted(set(stocks.TICKER_META) - set(stocks.TICKER_KO))
    extra = sorted(set(stocks.TICKER_KO) - set(stocks.TICKER_META))
    assert not missing, f"한글명이 없는 인기 종목: {missing}"
    assert not extra, f"인기 종목 목록에 없는데 한글명만 있는 티커: {extra}"
    for t, ko in stocks.TICKER_KO.items():
        assert ko.strip() == ko and ko, f"{t}: 한글명 앞뒤 공백/빈 값"


def test_display_name_format():
    assert stocks.display_name("AAPL", "Apple") == "애플 Apple"
    # 한글명과 영어가 같으면(AMD/IBM/UPS 등) 영어 하나만
    assert stocks.display_name("AMD", "AMD") == "AMD"
    # 한글명이 없는 종목(SEC 목록 등)은 영어 그대로
    assert stocks.display_name("ZZZZ", "Some Corp") == "Some Corp"
    # 소문자 티커도 같게
    assert stocks.display_name("aapl", "Apple") == "애플 Apple"


def test_ticker_meta_and_catalog_use_korean_names():
    name, sector = stocks.ticker_meta("NVDA")
    assert name == "엔비디아 Nvidia" and sector == "기술"
    # 예전엔 영어 이름에 한글이 섞여 있던 종목도 일관된 모양이어야 함
    assert stocks.ticker_meta("GOOGL")[0] == "알파벳(구글) Alphabet"
    assert stocks.ticker_meta("RTX")[0] == "RTX(레이시온) RTX Raytheon"
    # 카탈로그(종목 추가 자동완성)도 같은 이름을 내려줌 — 한글/영어 어느 쪽으로 검색해도 걸림
    cat = {e["ticker"]: e["name"] for e in stocks.catalog()}
    assert cat["AAPL"] == "애플 Apple"
    assert any("애플" in n for n in cat.values()) and any(re.search("Apple", n) for n in cat.values())


if __name__ == "__main__":
    test_every_curated_ticker_has_korean_name()
    test_display_name_format()
    test_ticker_meta_and_catalog_use_korean_names()
    print("test_stock_names: ALL OK")
