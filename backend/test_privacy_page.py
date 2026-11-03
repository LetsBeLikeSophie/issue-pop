# -*- coding: utf-8 -*-
"""개인정보처리방침 페이지 — `python3 test_privacy_page.py`. 시행일·이름 통일·콘텐츠 제외 요청 창구가 들어 있는지."""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from fastapi.testclient import TestClient

import api

client = TestClient(api.app)
r = client.get("/privacy")
assert r.status_code == 200
html = r.text

assert "시행일자: 2026년 10월 26일" in html
assert "이슈판" not in html, "방침 본문에 옛 이름(이슈판)이 남음"
assert 'Issue Pop(이하 "이슈팝")' in html
# 콘텐츠 제외 요청 창구와 연락 이메일(Cloudflare 난독화를 피하려고 &#64; 사용)
assert "콘텐츠 이용 안내 및 삭제 요청" in html and "콘텐츠 제외 요청: contact&#64;issue-pop.com" in html
# 실제 수집·전달과 맞는 항목들
for needle in ("기기 번호", "Firebase 설치 ID", "Google Fonts", "Google Gmail", "Google Firebase Cloud Messaging", "후원 위젯(Buy Me a Coffee)"):
    assert needle in html, needle
assert "8. 방침 변경" in html
# 앱 기본(화이트) 테마 색 — 옛 연녹색(#EEF1EA)이 남지 않았는지
assert "background: #FAFAF9" in html and "color: #17356B" in html
assert "#EEF1EA" not in html and "#35503F" not in html

print("test_privacy_page: ALL OK")
