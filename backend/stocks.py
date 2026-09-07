# -*- coding: utf-8 -*-
"""
관심 종목(브랜드) 뉴스 — 2026-09-06 추가.

S&P500 전체(500개)를 미리 다 가져오는 건 매 갱신마다 요청이 너무 많아져서
(서버가 약한 1vCPU라 특히) 아예 처음부터 빼고, "기기가 등록한 티커만
가져오는" 구조로 함(db.py의 device_stock_watches, api.py의 관심 키워드
기능과 같은 패턴). 기본 10개는 STARTER_TICKERS로 화면이 비어있지 않게
자동으로 깔아두고, 그 다음부턴 사용자가 완전히 편집(기본값도 지울 수
있음).

뉴스 소스는 야후 파이낸스의 티커별 전용 RSS 피드 — 키 발급 없이 무료로
쓸 수 있고(2026-09-05 실측 확인), 회사별로 이미 걸러진 뉴스라 우리
클러스터링 파이프라인처럼 따로 묶을 필요도 없음. 한국 종합지 RSS로는
개별 미국 기업 뉴스가 거의 안 실려서 이 방식으로 감(backend/README.md
참고).
"""

from __future__ import annotations

import hashlib
import xml.etree.ElementTree as ET
from urllib.parse import urlparse

import requests

import db
import translate

# 2026-09-06: 야후 파이낸스 RSS는 자체 기사가 아니라 여러 매체를 모아
# 보여주는 애그리게이터라("믿을만한 출처냐"는 질문을 받고 실제 피드를
# 열어보니 Motley Fool/Barchart 같은 "주식 픽" 스타일 콘텐츠도 섞여
# 있었음), "Yahoo Finance"로 뭉뚱그리지 않고 기사 링크의 도메인에서
# 실제 매체명을 뽑아서 보여줌 — 목록에 없는 도메인은 그 도메인 문자열을
# 그대로 표시(정직하게, 안 아는 척 안 함).
_SOURCE_NAMES: dict[str, str] = {
    "finance.yahoo.com": "Yahoo Finance",
    "fool.com": "The Motley Fool",
    "barchart.com": "Barchart",
    "investors.com": "Investor's Business Daily",
    "zacks.com": "Zacks",
    "simplywall.st": "Simply Wall St",
    "benzinga.com": "Benzinga",
    "gurufocus.com": "GuruFocus",
    "247wallst.com": "24/7 Wall St.",
    "insidermonkey.com": "Insider Monkey",
    "reuters.com": "Reuters",
    "bloomberg.com": "Bloomberg",
    "marketwatch.com": "MarketWatch",
    "cnbc.com": "CNBC",
    "forbes.com": "Forbes",
    "businessinsider.com": "Business Insider",
    "seekingalpha.com": "Seeking Alpha",
    "tipranks.com": "TipRanks",
}


def _source_name(link: str) -> str:
    host = urlparse(link).netloc.removeprefix("www.")
    return _SOURCE_NAMES.get(host, host or "출처 불명")

# 화면이 비어있지 않게 기본으로 깔아두는 10개 — 브랜드 인지도 + 섹터
# 다양성 기준으로 고름. name은 화면 표시용 한글 브랜드명.
STARTER_TICKERS = [
    "AAPL", "MSFT", "NVDA", "GOOGL", "META",
    "AMZN", "TSLA", "KO", "JPM", "JNJ",
]

# 2026-09-06: "티커를 미리 알고 있어야 추가할 수 있는 게 불편하다"는
# 피드백으로 대폭 확장 — 이제 이 딕셔너리가 두 가지 역할을 겸함:
# (1) STARTER_TICKERS 10개의 표시명/섹터, (2) 종목 추가 시 자동완성
# 검색용 카탈로그(GET /stocks/catalog, api.py 참고). S&P500 전체를
# 정확히 담은 건 아니고(지수 구성은 수시로 바뀜), 자동완성 편의용으로
# 널리 알려진 미국 대형주 위주로 고른 목록 — 목록에 없는 티커를 직접
# 입력해도 여전히 추가는 가능함(표시명은 티커 그대로, 섹터는 "기타").
TICKER_META: dict[str, tuple[str, str]] = {
    # 기술
    "AAPL": ("Apple", "기술"),
    "MSFT": ("Microsoft", "기술"),
    "NVDA": ("Nvidia", "기술"),
    "GOOGL": ("Alphabet 구글", "기술"),
    "GOOG": ("Alphabet 구글 Class C", "기술"),
    "META": ("Meta", "기술"),
    "AVGO": ("Broadcom", "기술"),
    "ORCL": ("Oracle", "기술"),
    "CRM": ("Salesforce", "기술"),
    "ADBE": ("Adobe", "기술"),
    "AMD": ("AMD", "기술"),
    "INTC": ("Intel", "기술"),
    "CSCO": ("Cisco", "기술"),
    "QCOM": ("Qualcomm", "기술"),
    "TXN": ("Texas Instruments", "기술"),
    "IBM": ("IBM", "기술"),
    "NOW": ("ServiceNow", "기술"),
    "INTU": ("Intuit", "기술"),
    "UBER": ("Uber", "기술"),
    "SHOP": ("Shopify", "기술"),
    "SNOW": ("Snowflake", "기술"),
    "PLTR": ("Palantir", "기술"),
    "PYPL": ("PayPal", "기술"),
    "SQ": ("Block Square", "기술"),
    "NFLX": ("Netflix", "기술"),
    "SPOT": ("Spotify", "기술"),
    "ABNB": ("Airbnb", "기술"),
    "MU": ("Micron", "기술"),
    "AMAT": ("Applied Materials", "기술"),
    "ASML": ("ASML", "기술"),
    "TSM": ("TSMC", "기술"),
    "SAP": ("SAP", "기술"),
    "NET": ("Cloudflare", "기술"),
    "PANW": ("Palo Alto Networks", "기술"),
    "CRWD": ("CrowdStrike", "기술"),
    "DDOG": ("Datadog", "기술"),
    # 소비재
    "AMZN": ("Amazon", "소비재"),
    "KO": ("Coca-Cola", "소비재"),
    "PEP": ("PepsiCo", "소비재"),
    "WMT": ("Walmart", "소비재"),
    "COST": ("Costco", "소비재"),
    "PG": ("Procter & Gamble", "소비재"),
    "HD": ("Home Depot", "소비재"),
    "MCD": ("McDonald's", "소비재"),
    "NKE": ("Nike", "소비재"),
    "SBUX": ("Starbucks", "소비재"),
    "DIS": ("Disney", "소비재"),
    "CL": ("Colgate-Palmolive", "소비재"),
    "TGT": ("Target", "소비재"),
    "LOW": ("Lowe's", "소비재"),
    "EL": ("Estée Lauder", "소비재"),
    "MDLZ": ("Mondelez", "소비재"),
    "MNST": ("Monster Beverage", "소비재"),
    "YUM": ("Yum! Brands", "소비재"),
    "CMG": ("Chipotle", "소비재"),
    "BKNG": ("Booking Holdings", "소비재"),
    "MAR": ("Marriott", "소비재"),
    "LULU": ("Lululemon", "소비재"),
    "TJX": ("TJX Companies", "소비재"),
    # 자동차
    "TSLA": ("Tesla", "자동차"),
    "F": ("Ford", "자동차"),
    "GM": ("General Motors", "자동차"),
    "RIVN": ("Rivian", "자동차"),
    "LCID": ("Lucid Motors", "자동차"),
    "TM": ("Toyota", "자동차"),
    "HMC": ("Honda", "자동차"),
    # 금융
    "JPM": ("JPMorgan", "금융"),
    "BAC": ("Bank of America", "금융"),
    "WFC": ("Wells Fargo", "금융"),
    "C": ("Citigroup", "금융"),
    "GS": ("Goldman Sachs", "금융"),
    "MS": ("Morgan Stanley", "금융"),
    "V": ("Visa", "금융"),
    "MA": ("Mastercard", "금융"),
    "AXP": ("American Express", "금융"),
    "BLK": ("BlackRock", "금융"),
    "SCHW": ("Charles Schwab", "금융"),
    "SPGI": ("S&P Global", "금융"),
    "COIN": ("Coinbase", "금융"),
    "BRK-B": ("Berkshire Hathaway", "금융"),
    # 헬스케어
    "JNJ": ("Johnson & Johnson", "헬스케어"),
    "UNH": ("UnitedHealth", "헬스케어"),
    "PFE": ("Pfizer", "헬스케어"),
    "MRK": ("Merck", "헬스케어"),
    "ABBV": ("AbbVie", "헬스케어"),
    "LLY": ("Eli Lilly", "헬스케어"),
    "TMO": ("Thermo Fisher", "헬스케어"),
    "ABT": ("Abbott", "헬스케어"),
    "DHR": ("Danaher", "헬스케어"),
    "BMY": ("Bristol Myers Squibb", "헬스케어"),
    "AMGN": ("Amgen", "헬스케어"),
    "GILD": ("Gilead Sciences", "헬스케어"),
    "ISRG": ("Intuitive Surgical", "헬스케어"),
    "MRNA": ("Moderna", "헬스케어"),
    "CVS": ("CVS Health", "헬스케어"),
    # 에너지
    "XOM": ("ExxonMobil", "에너지"),
    "CVX": ("Chevron", "에너지"),
    "COP": ("ConocoPhillips", "에너지"),
    "SLB": ("SLB Schlumberger", "에너지"),
    "OXY": ("Occidental Petroleum", "에너지"),
    "NEE": ("NextEra Energy", "에너지"),
    # 산업재
    "BA": ("Boeing", "산업재"),
    "CAT": ("Caterpillar", "산업재"),
    "GE": ("General Electric", "산업재"),
    "HON": ("Honeywell", "산업재"),
    "UPS": ("UPS", "산업재"),
    "LMT": ("Lockheed Martin", "산업재"),
    "RTX": ("RTX 레이시온", "산업재"),
    "DE": ("Deere & Company", "산업재"),
    "UNP": ("Union Pacific", "산업재"),
    "MMM": ("3M", "산업재"),
    # 통신
    "VZ": ("Verizon", "통신"),
    "T": ("AT&T", "통신"),
    "TMUS": ("T-Mobile", "통신"),
    "CMCSA": ("Comcast", "통신"),
    # 소재
    "LIN": ("Linde", "소재"),
    "SHW": ("Sherwin-Williams", "소재"),
    "NEM": ("Newmont", "소재"),
    # 부동산
    "PLD": ("Prologis", "부동산"),
    "AMT": ("American Tower", "부동산"),
    # 유틸리티
    "DUK": ("Duke Energy", "유틸리티"),
    "SO": ("Southern Company", "유틸리티"),
}


def ticker_meta(ticker: str) -> tuple[str, str]:
    """티커 하나의 (표시명, 섹터) — POST /stocks·자동 시드에서 씀.
    2026-09-07: TICKER_META(수동 큐레이션)에 없으면 티커 그대로를
    표시명으로 쓰던 것을, catalog()처럼 SEC 목록도 확인하도록 고침 —
    안 그러면 카탈로그 검색에서는 "Virgin Galactic Holdings, Inc"로
    찾아서 추가했는데 정작 목록엔 "SPCE"로만 뜨는 불일치가 생김."""
    t = ticker.upper()
    if t in TICKER_META:
        return TICKER_META[t]
    sec_names = {e["ticker"]: e["name"] for e in _fetch_sec_catalog()}
    return (sec_names.get(t, t), "기타")


# 2026-09-07: TICKER_META 수동 목록(~120개)이 너무 좁다는 피드백으로
# ("SPCE 추가하려니 카탈로그에 없어서 안 되는 줄 알았다") SEC(미국
# 증권거래위원회)가 공개하는 미국 상장기업 티커 전체 목록으로 카탈로그를
# 확장함 — 키 발급 없이 무료(실측 확인, 2026-09-07), 약 10,400개.
# User-Agent에 식별 정보를 넣어야 함(SEC 정책, 없으면 차단될 수 있음).
# 회사 이름 표기가 파일 안에서도 일관되지 않아서(어떤 건 "Apple Inc.",
# 어떤 건 "NVIDIA CORP"처럼 전부 대문자) title()로 정규화함 — AT&T처럼
# 일부 이름이 살짝 어색해지는 경우가 있지만(전부 대문자보다는 나음),
# 자동완성 검색 편의용이라 완벽할 필요는 없음. TICKER_META에 이미 있는
# 티커는 수동으로 다듬은 이름/섹터를 그대로 우선함.
_SEC_HEADERS = {"User-Agent": "IssuePop research contact@issue-pop.com"}
_sec_catalog_cache: list[dict] | None = None


def _fetch_sec_catalog() -> list[dict]:
    """서버 프로세스당 한 번만 받아서 캐싱함(회사 이름은 하루 안에 안
    바뀌니까) — 실패하면(네트워크 문제 등) 빈 리스트, catalog()가 그때는
    TICKER_META만으로 동작함(서버가 안 죽으면 됨, 다른 외부 API 연동과
    같은 방어 원칙)."""
    global _sec_catalog_cache
    if _sec_catalog_cache is not None:
        return _sec_catalog_cache
    try:
        res = requests.get("https://www.sec.gov/files/company_tickers.json", headers=_SEC_HEADERS, timeout=10)
        res.raise_for_status()
        data = res.json()
        _sec_catalog_cache = [{"ticker": v["ticker"], "name": v["title"].title()} for v in data.values()]
    except Exception:  # noqa: BLE001
        _sec_catalog_cache = []
    return _sec_catalog_cache


def catalog() -> list[dict]:
    """종목 추가 시 자동완성 검색용 전체 카탈로그 — /search와 같은 패턴으로
    한 번에 통째로 내려주고 클라이언트가 타이핑마다 로컬에서 걸러내게 함
    (api.py의 GET /stocks/catalog).

    순서: STARTER_TICKERS(잘 알려진 10개) 먼저, 그 다음 TICKER_META의
    나머지(알파벳 순), 그 다음 SEC 목록 나머지(파일 자체가 대략 시가총액
    순이라 그 순서를 그대로 씀) — 프론트가 검색어 없을 때 앞부분 몇 개만
    잘라서 "인기 종목" 미리보기로 그대로 씀(stock_watch_screen.dart 참고)."""
    starter_set = set(STARTER_TICKERS)
    ordered = list(STARTER_TICKERS) + sorted(t for t in TICKER_META if t not in starter_set)
    seen = set(ordered)

    sec_list = _fetch_sec_catalog()
    sec_names = {e["ticker"]: e["name"] for e in sec_list}
    for e in sec_list:
        if e["ticker"] not in seen:
            ordered.append(e["ticker"])
            seen.add(e["ticker"])

    result = []
    for t in ordered:
        if t in TICKER_META:
            name, sector = TICKER_META[t]
        else:
            name, sector = sec_names.get(t, t), "기타"
        result.append({"ticker": t, "name": name, "sector": sector})
    return result


def fetch_ticker_news(ticker: str, limit: int = 5) -> list[dict]:
    """야후 파이낸스 RSS에서 이 티커의 최신 뉴스를 가져옴. 실패하면(없는
    티커, 네트워크 오류 등) 조용히 빈 리스트 — 한 티커 실패가 전체
    갱신을 막으면 안 됨(다른 소스들과 같은 방어 원칙)."""
    url = f"https://feeds.finance.yahoo.com/rss/2.0/headline?s={ticker}&region=US&lang=en-US"
    try:
        res = requests.get(url, headers={"User-Agent": "Mozilla/5.0"}, timeout=8)
        res.raise_for_status()
        root = ET.fromstring(res.content)
        items = []
        for item in root.findall(".//item")[:limit]:
            title = item.findtext("title", "").strip()
            link = item.findtext("link", "").strip()
            pub_date = item.findtext("pubDate", "").strip()
            if title:
                items.append({"title": title, "link": link, "published": pub_date, "source": _source_name(link)})
        return items
    except Exception:  # noqa: BLE001 - 티커 하나 실패해도 나머지는 계속
        return []


def _translate_cached(session, text: str) -> str | None:
    """번역 결과를 원문 해시로 캐싱함(db.TranslatedHeadline) — 파파고
    무료 할당량이 하루 단위라, 같은 헤드라인을 30분 갱신마다 매번 다시
    번역하면 금방 소진됨. 새로 보는 헤드라인만 실제로 API를 호출함.
    번역 실패(키 없음/API 오류)하면 None — 호출하는 쪽에서 원문을
    그대로 보여주면 됨."""
    text_hash = hashlib.sha1(text.encode("utf-8")).hexdigest()
    cached = session.get(db.TranslatedHeadline, text_hash)
    if cached is not None:
        return cached.translated_text
    translated = translate.translate_to_ko(text)
    if translated is None:
        return None
    session.add(db.TranslatedHeadline(text_hash=text_hash, original_text=text, translated_text=translated))
    session.commit()
    return translated


def _attach_translations(items: list[dict], session) -> None:
    for item in items:
        item["title_ko"] = _translate_cached(session, item["title"])


def fetch_all(tickers: list[str]) -> dict[str, list[dict]]:
    """여러 티커의 뉴스를 한 번에 가져옴 — api.py의 갱신 루프에서 씀.
    2026-09-06: 헤드라인이 전부 영어라("이거 어느정도 번역은 해줘야겠는데"
    피드백) 파파고로 번역한 title_ko도 같이 붙임(_translate_cached로
    캐싱, 실패하면 title_ko는 None — 프론트가 원문만 보여주면 됨)."""
    result = {t: fetch_ticker_news(t) for t in tickers}
    with db.get_session() as session:
        for items in result.values():
            _attach_translations(items, session)
    return result


def fetch_one_with_translation(ticker: str, limit: int = 5) -> list[dict]:
    """새로 등록한 티커 하나만 즉시 가져옴(번역 포함) — 안 그러면 다음
    30분 갱신 주기까지 "아직 받아온 뉴스가 없어요"만 보여서("추가하면
    바로 안 받아와지냐"는 피드백으로 추가) api.py의 POST /stocks에서 씀."""
    items = fetch_ticker_news(ticker, limit=limit)
    with db.get_session() as session:
        _attach_translations(items, session)
    return items
