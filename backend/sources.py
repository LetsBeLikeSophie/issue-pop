# -*- coding: utf-8 -*-
"""
매체 출처 코드테이블 — RSS 피드 + 신뢰도/카테고리/정치성향 메타데이터.

2026-09-20: "기사는 결국 outlet에 종속되는데, 성향 필터를 만들든 안
만들든 이 메타데이터 자체는 구조화된 테이블로 관리돼야 한다"는 피드백으로
정리함. sources.py 원래 docstring에도 "언젠가 DB 테이블(outlets)로
옮긴다"는 계획이 있었는데, 지금 규모(9~20건)와 갱신 방식(사람이 가끔
손으로 고치는 참고 자료)을 보면 SQLite 테이블보다 이렇게 파이썬
리스트로 버전관리(git)되는 게 오히려 나음 — 누가 언제 왜 바꿨는지
커밋 히스토리에 그대로 남음. 유저 데이터가 아니라 "코드 취급하는
참고 데이터"라 이 파일 자체가 "코드테이블"인 셈.

**갱신 주기(사람이 직접 해야 함, 자동화 없음)**:
  - `last_verified` (RSS 생존 여부): 월 1회 정도, `validate_sources.py`
    다시 돌려서 갱신. URL이 바뀌거나 서비스가 죽으면 이 값으로 알아챔.
  - `leaning_updated` (정치성향 라벨): 연 1회, 한국언론진흥재단이
    〈언론수용자 조사〉를 새로 낼 때마다 그 기준으로 재검증.
    (자세한 배경/스펙트럼 위치는 2026-09-20 작성한 "이슈판 매체
    지형도" 문서 참고 — 이 파일이 그 문서의 실제 데이터 소스가 됨.)

**필드 설명**:
  - outlet         : 매체명
  - category       : RSS 피드 자체의 카테고리(종합/경제 등) — category.py의
                      9분류(정치/경제/사회/...)와는 다른 축, 혼동 주의.
  - url            : RSS 피드 주소
  - confidence     : "verified"(생존 확인) | "unverified"(추정만 함)
  - last_verified  : confidence를 마지막으로 확인한 날짜(YYYY-MM-DD)
  - political_leaning : "진보" | "중도진보" | "중도" | "중도보수" | "보수" | None(미분류)
                      학술·보도에서 통상적으로 언급되는 분류 참고용 — 국가
                      승인통계 아님, 논쟁 있을 수 있음. 실제 유저 대상
                      필터 기능에 쓰기 전엔 반드시 KPF 최신 자료로 재검증.
  - leaning_source : 위 분류의 근거를 한 줄로(출처가 약할수록 신중하게 취급).
  - leaning_updated: leaning 필드를 마지막으로 검토한 날짜.
"""

RSS_SOURCES = [
    {
        "outlet": "연합뉴스", "category": "종합",
        "url": "https://www.yna.co.kr/rss/news.xml",
        "confidence": "verified", "last_verified": "2026-08-23",
        "political_leaning": "중도",
        "leaning_source": "국가기간뉴스통신사, 정부 지분 — 정권별 논조 변동 논란 있음",
        "leaning_updated": "2026-09-20",
    },
    {
        "outlet": "한겨레", "category": "종합",
        "url": "https://www.hani.co.kr/rss/",
        "confidence": "verified", "last_verified": "2026-08-23",
        "political_leaning": "진보",
        "leaning_source": "국민주 창간, 대표적 진보지 — 이견 거의 없음",
        "leaning_updated": "2026-09-20",
    },
    {
        "outlet": "경향신문", "category": "종합",
        "url": "https://www.khan.co.kr/rss/rssdata/total_news.xml",
        "confidence": "verified", "last_verified": "2026-08-23",
        "political_leaning": "중도진보",
        "leaning_source": "진보 성향, 한겨레보다 소폭 온건하다는 평가",
        "leaning_updated": "2026-09-20",
    },
    {
        "outlet": "매일경제", "category": "경제",
        "url": "https://www.mk.co.kr/rss/30000001/",
        "confidence": "verified", "last_verified": "2026-08-23",
        "political_leaning": "중도보수",
        "leaning_source": "경제지 — 친시장/친기업 논조(정치 좌우보다 이 축이 더 강함)",
        "leaning_updated": "2026-09-20",
    },
    {
        "outlet": "머니투데이", "category": "경제",
        "url": "https://rss.mt.co.kr/mt_news.xml",
        "confidence": "verified", "last_verified": "2026-08-23",
        "political_leaning": "중도",
        "leaning_source": "경제 전문지, 정치성향보다 경제 실용 논조",
        "leaning_updated": "2026-09-20",
    },
    {
        "outlet": "SBS", "category": "종합",
        "url": "https://news.sbs.co.kr/news/SectionRssFeed.do?sectionId=01",
        "confidence": "verified", "last_verified": "2026-08-23",
        "political_leaning": "중도",
        "leaning_source": "민영방송, 중도~중도진보로 평가되는 경우가 많음",
        "leaning_updated": "2026-09-20",
    },
    {
        "outlet": "동아일보", "category": "종합",
        "url": "https://rss.donga.com/total.xml",
        "confidence": "verified", "last_verified": "2026-08-23",
        "political_leaning": "보수",
        "leaning_source": "'조중동' 중 하나, 종편 채널A 계열",
        "leaning_updated": "2026-09-20",
    },
    {
        "outlet": "서울신문", "category": "종합",
        "url": "https://www.seoul.co.kr/xml/rss/rss_politics.xml",
        "confidence": "verified", "last_verified": "2026-08-23",
        "political_leaning": "보수",
        "leaning_source": "2021년 호반건설 편입 이후 보수 논조로 전환(과거엔 준공영·중도)",
        "leaning_updated": "2026-09-20",
    },
    {
        "outlet": "오마이뉴스", "category": "종합",
        "url": "https://rss.ohmynews.com/rss/ohmynews.xml",
        "confidence": "verified", "last_verified": "2026-08-23",
        "political_leaning": "진보",
        "leaning_source": "시민기자 모델, 진보 성향 뚜렷",
        "leaning_updated": "2026-09-20",
    },
    {
        # 2026-09-20: CANDIDATE_SOURCES에서 승격 — 홈페이지
        # <link rel="alternate" rss+xml>로 새 주소 발견, fetch_outlet()으로
        # 실제 검증(250건 채택, 요약문도 500자씩 정상 포함). 한국경제 때와
        # 달리 첫 시도부터 에러 없이 깔끔하게 붙어서 신뢰도 높다고 판단함.
        "outlet": "헤럴드경제", "category": "경제",
        "url": "https://biz.heraldcorp.com/rss/google/newsAll",
        "confidence": "verified", "last_verified": "2026-09-20",
        "political_leaning": "중도",
        "leaning_source": "경제 전문지",
        "leaning_updated": "2026-09-20",
    },
]

# 2026-08-23에 죽은 걸로 확인됐거나(dead) 아예 시도를 안 해본(untried)
# 후보들. fetch_all()이 안 도는 목록이라 실제 수집엔 영향 없음 — RSS
# URL을 다시 찾아서 살리거나(dead), 처음 검증하면(untried) RSS_SOURCES로
# 승격시키면 됨. "이슈판 매체 지형도" 문서의 커버리지 갭 분석이 이
# 목록을 그대로 씀.
CANDIDATE_SOURCES = [
    {
        # 2026-09-20: 홈페이지 <link rel="alternate" rss+xml>로 새 주소를
        # 찾아서 한 번은 RSS_SOURCES로 승격시켜봤는데(정상 fetch 1회 확인,
        # 50건), 그 뒤로는 개발 PC에서도 오라클 서버(전혀 다른 IP)에서도
        # 매번 "line 2:1326 not well-formed" 파싱 에러로 실패함 — User-Agent
        # 문제는 fetcher.py에서 고쳤는데도 안 됨. 최초 성공이 우연이었고,
        # 실제로는 (아마 데이터센터 IP 대역을 걸러내는 안티봇 정책으로)
        # 거의 항상 깨진 XML을 내려주는 것으로 보임 — "확보됨"으로
        # 표시했다가 실제론 매번 0건이면 오히려 더 나쁨. 다시 후보로
        # 내림. URL 자체는 유효하니, 만약 클라우드 IP 우회(주거용 프록시
        # 등)나 다른 접근 방식을 시도한다면 이 URL부터 다시 써보면 됨.
        "outlet": "한국경제", "category": "경제",
        "url": "https://www.hankyung.com/feed/all-news",
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "보수",
        "leaning_source": "친기업·시장주의 논조, 정치면도 보수 성향 평가",
    },
    {
        # 2026-09-20 재확인: 홈페이지에 <link rel="alternate" rss+xml>
        # 자체가 없고, 예전에 쓰이던 site/data/rss/*.xml, myhome.chosun.com
        # 경로도 전부 404 — 공개 RSS를 아예 접은 것으로 보임.
        "outlet": "조선일보", "category": "종합", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "보수",
        "leaning_source": "'조중동' 중 하나, 대표적 보수지 — 이견 거의 없음",
    },
    {
        # 2026-09-20 재확인: 홈페이지에 RSS 링크 태그 없음, 예전 도메인
        # rss.joins.com은 완전히 다른(무관한) 서비스로 넘어감 — 공개 RSS
        # 접은 것으로 보임.
        "outlet": "중앙일보", "category": "종합", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "보수",
        "leaning_source": "전통적 보수, 최근 논조 다소 중도화 평가도 있음",
    },
    {
        "outlet": "KBS", "category": "방송", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "중도",
        "leaning_source": "공영방송, 정권 교체마다 논조 변동 비판이 양쪽에서 나옴",
    },
    {
        "outlet": "MBC", "category": "방송", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "중도진보",
        "leaning_source": "공영방송, 중도진보로 평가되는 경우가 많음(보수 진영에선 비판)",
    },
    {
        # 2026-09-20 재확인: 홈페이지에 RSS 링크 태그 없음.
        "outlet": "국민일보", "category": "종합", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "중도보수",
        "leaning_source": "개신교(여의도순복음교회) 배경",
    },
    {
        # 2026-09-20 재확인: 홈페이지에 RSS 링크 태그 없음. /RSS/economy.xml,
        # /rss/economy.xml 등 흔한 패턴도 전부 실제로는 그냥 HTML 페이지였음
        # (200이지만 text/html, RSS 아님).
        "outlet": "노컷뉴스", "category": "종합", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "중도진보",
        "leaning_source": "CBS(기독교방송) 계열",
    },
    {
        # 2026-09-20 재확인: 홈페이지에 RSS 링크 태그 없음, /rss/rss.xml도
        # 실제론 HTML 페이지(가짜 200).
        "outlet": "이데일리", "category": "경제", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "중도",
        "leaning_source": "경제 전문지",
    },
    {
        # 2026-09-20 재확인: 홈페이지에 RSS 링크 태그 없음, 흔한 패턴도
        # 전부 HTML 페이지(가짜 200).
        "outlet": "파이낸셜뉴스", "category": "경제", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "중도",
        "leaning_source": "경제 전문지",
    },
    {
        # 2026-09-20 재확인: 홈페이지에 RSS 링크 태그 없음, /api/rss/,
        # /rss/allArticle.xml 다 404.
        "outlet": "프레시안", "category": "종합", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "진보",
        "leaning_source": "진보 성향 인터넷신문",
    },
    # 2026-09-20 추가: 20개 후보에 아예 없었던 방송사들 — "매체 지형도"
    # 문서를 만들며 전체 그림을 위해 참고로 넣음. 오늘 홈페이지 RSS
    # 링크 태그 확인해봤는데 전부 없었음(untried → dead로 갱신).
    {
        "outlet": "TV조선", "category": "방송", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "보수",
        "leaning_source": "조선일보 계열 종편, 보수 성향 뚜렷",
    },
    {
        "outlet": "채널A", "category": "방송", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "보수",
        "leaning_source": "동아일보 계열 종편, TV조선보다 다소 온건",
    },
    {
        "outlet": "MBN", "category": "방송", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "중도보수",
        "leaning_source": "매일경제 계열 종편",
    },
    {
        "outlet": "YTN", "category": "방송", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "중도",
        "leaning_source": "2024년 민영화로 지형 변화 진행 중",
    },
    {
        "outlet": "JTBC", "category": "방송", "url": None,
        "status": "dead", "last_checked": "2026-09-20",
        "political_leaning": "중도진보",
        "leaning_source": "중앙일보 계열이지만 방송은 중도진보 평가(손석희 앵커 시절 영향)",
    },
]
