# -*- coding: utf-8 -*-
"""
RSS 피드 출처 목록.

실제 서비스에서는 이 리스트를 DB 테이블(outlets)로 옮기고,
매체별 신뢰도/카테고리/성향 메타데이터를 함께 관리하게 될 거예요.
지금은 프로토타입 단계라 파이썬 리스트로 하드코딩했어요.

2026-08-23: validate_sources.py를 로컬 PC(실제 인터넷 가능)에서 돌려서
20개 중 9개가 살아있는 걸 확인했어요. 죽은 11개(KBS, 한국경제, 조선일보,
중앙일보, MBC, 국민일보, 노컷뉴스, 이데일리, 헤럴드경제, 파이낸셜뉴스,
프레시안)는 목록에서 뺐고, 살아있는 9개는 confidence를 "verified"로
올렸어요. 원본 결과는 sources_status.json 참고.

  - verified   : 실제로 인터넷 되는 곳에서 살아있는 걸 확인한 URL
  - unverified : 알려진 패턴으로 추정해서 넣었지만 직접 확인은 못 한 URL
                 (매체가 도메인/경로를 바꿨으면 죽어있을 수 있음)
"""

RSS_SOURCES = [
    {"outlet": "연합뉴스", "category": "종합", "url": "https://www.yna.co.kr/rss/news.xml", "confidence": "verified"},
    {"outlet": "한겨레", "category": "종합", "url": "https://www.hani.co.kr/rss/", "confidence": "verified"},
    {"outlet": "경향신문", "category": "종합", "url": "https://www.khan.co.kr/rss/rssdata/total_news.xml", "confidence": "verified"},
    {"outlet": "매일경제", "category": "경제", "url": "https://www.mk.co.kr/rss/30000001/", "confidence": "verified"},
    {"outlet": "머니투데이", "category": "경제", "url": "https://rss.mt.co.kr/mt_news.xml", "confidence": "verified"},
    {"outlet": "SBS", "category": "종합", "url": "https://news.sbs.co.kr/news/SectionRssFeed.do?sectionId=01", "confidence": "verified"},
    {"outlet": "동아일보", "category": "종합", "url": "https://rss.donga.com/total.xml", "confidence": "verified"},
    {"outlet": "서울신문", "category": "종합", "url": "https://www.seoul.co.kr/xml/rss/rss_politics.xml", "confidence": "verified"},
    {"outlet": "오마이뉴스", "category": "종합", "url": "https://rss.ohmynews.com/rss/ohmynews.xml", "confidence": "verified"},
]
