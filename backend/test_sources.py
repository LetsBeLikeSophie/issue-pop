# -*- coding: utf-8 -*-
"""매체 목록(/sources)이 언론사 홈페이지를 같이 내려주는지 — `python3 test_sources.py`"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import sources


def test_every_outlet_has_a_homepage():
    missing = [s["outlet"] for s in sources.RSS_SOURCES if s["outlet"] not in sources.OUTLET_HOMEPAGE]
    assert not missing, f"홈페이지가 없는 매체(설정 화면 알약이 눌러도 반응 없음): {missing}"
    extra = sorted(set(sources.OUTLET_HOMEPAGE) - {s["outlet"] for s in sources.RSS_SOURCES})
    assert not extra, f"수집하지 않는 매체의 홈페이지가 남아 있음: {extra}"
    for outlet, url in sources.OUTLET_HOMEPAGE.items():
        assert url.startswith("https://") and "/rss" not in url and not url.endswith("/"), f"{outlet}: {url}"


if __name__ == "__main__":
    test_every_outlet_has_a_homepage()
    print("test_sources: ALL OK")
