import 'dart:convert';
import 'package:http/http.dart' as http;

import 'models/issue.dart';

/// backend/api.py 클라이언트.
///
/// 2026-08-25: 'localhost' 대신 '127.0.0.1'을 씀 — 이 개발 환경(Windows)
/// 에서 'localhost' 호스트명 해석 자체가 요청마다 약 2초씩 걸리는 걸
/// 실측으로 발견함(127.0.0.1로 직접 IP를 주면 90ms 수준). 그동안
/// "검색이 느리다"는 피드백의 진짜 원인이 이거였을 가능성이 큼 —
/// 클라이언트/서버 구조를 아무리 가볍게 고쳐도 이 지연 앞에서는 체감이
/// 안 됐을 것.
///
/// 2026-08-29: Oracle Cloud(도쿄, Always Free)에 실제 배포하면서, 평소
/// 개발(핫 리로드로 빠르게 반복)은 로컬 서버로 하고 원격 테스트가 필요할
/// 때만 배포된 서버를 가리키게 함 — 코드를 매번 고쳤다 되돌리지 않도록
/// 빌드타임 환경변수로 전환:
///   flutter run                                                        // 로컬(기본값)
///   flutter run --dart-define=API_BASE_URL=https://api.issue-pop.com    // 원격
///
/// 원격 서버는 nginx가 80/443을 8000(uvicorn)으로 리버스 프록시하고,
/// Cloudflare가 그 앞단에서 HTTPS를 처리함(서버 자체엔 인증서 설치
/// 안 함 — Cloudflare "Flexible" SSL 모드).
class ApiClient {
  ApiClient({String? baseUrl}) : baseUrl = baseUrl ?? _defaultBaseUrl;

  static const _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000',
  );

  /// 2026-09-07: 기사 썸네일 이미지 프록시 URL 생성용 — 항상
  /// ApiClient() 인스턴스를 통해서만 쓰이고 baseUrl 오버라이드도 안
  /// 하므로(main.dart 참고), ExpandableIssueCard처럼 api 인스턴스가
  /// 없을 수도 있는 곳(archive_screen.dart는 api를 안 넘김)에서도 이
  /// 정적 기본값으로 프록시 URL을 만들 수 있음.
  static String proxyImageUrl(String imageUrl) =>
      '$_defaultBaseUrl/image-proxy?url=${Uri.encodeQueryComponent(imageUrl)}';

  final String baseUrl;

  /// 2026-08-24: 요약이 아니라 기사 목록까지 포함한 상세를 통째로 받음 —
  /// 카드를 펼칠 때마다 다시 호출하지 않고 이미 받아둔 데이터로 즉시
  /// 펼쳐지게 하려고(이슈판 프로토타입만큼 빠른 반응 속도를 위해).
  Future<List<IssueDetail>> getTrending({int limit = 40, String? category}) async {
    final qp = {'limit': '$limit', 'category': ?category};
    final uri = Uri.parse('$baseUrl/trending').replace(queryParameters: qp);
    final res = await http.get(uri);
    _checkOk(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((e) => IssueDetail.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Map<String, int>> getCategories() async {
    final uri = Uri.parse('$baseUrl/categories');
    final res = await http.get(uri);
    _checkOk(res);
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, v as int));
  }

  /// 홈 마스트헤드 통계용 — 이슈/기사 개수만 가볍게 집계해서 받음(전체
  /// 이슈를 기사까지 통째로 받던 예전 방식보다 훨씬 가벼움).
  Future<({int issueCount, int articleCount})> getStats() async {
    final uri = Uri.parse('$baseUrl/stats');
    final res = await http.get(uri);
    _checkOk(res);
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (issueCount: map['issue_count'] as int, articleCount: map['article_count'] as int);
  }

  /// 검색용 가벼운 전체 목록(요약만, 기사 목록 제외) — 한 번만 받아서
  /// 타이핑마다 로컬에서 걸러내려고. /search를 q=""(전체 매칭)로 부르는
  /// 것뿐임. 2026-08-25: 처음엔 타이핑마다 서버에 물어보는 구조였는데,
  /// 그러면 로컬 필터보다 느릴 수밖에 없다는 피드백을 받고 "이슈판"
  /// 프로토타입처럼 클라이언트가 들고 있다가 즉시 거르는 방식으로 되돌림
  /// — 대신 기사 목록은 빼서 가볍게 만듦(그게 처음에 무거웠던 원인).
  Future<List<IssueSummary>> getIndex() async {
    final uri = Uri.parse('$baseUrl/search').replace(queryParameters: {'q': '', 'limit': '1000'});
    final res = await http.get(uri);
    _checkOk(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((e) => IssueSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 검색 결과처럼 요약만 갖고 있을 때, 펼쳐볼 때 그제서야 기사 목록까지
  /// 받아옴.
  Future<IssueDetail> getIssue(String issueId) async {
    final uri = Uri.parse('$baseUrl/issues/$issueId');
    final res = await http.get(uri);
    _checkOk(res);
    return IssueDetail.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// 로그인 없이 기기를 서버에 등록(다이제스트 알림 설정 등에 씀).
  /// 이미 등록된 push_token이면 서버가 기존 device_id를 그대로 돌려줌.
  Future<int> registerDevice(String pushToken) async {
    final uri = Uri.parse('$baseUrl/devices');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'push_token': pushToken}),
    );
    _checkOk(res);
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return map['device_id'] as int;
  }

  Future<int?> getDigestHour(int deviceId) async {
    final uri = Uri.parse('$baseUrl/devices/$deviceId/digest');
    final res = await http.get(uri);
    _checkOk(res);
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return map['digest_hour'] as int?;
  }

  Future<void> setDigestHour(int deviceId, int? hour) async {
    final uri = Uri.parse('$baseUrl/devices/$deviceId/digest');
    final res = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'hour': hour}),
    );
    _checkOk(res);
  }

  /// 2026-09-05: 다이제스트(하루 한 번)와 별개로 새로 뜨거나 급상승한
  /// 이슈를 재계산 주기마다 체크해서 알려주는 "주기적 알림" 설정 —
  /// 설정 저장까지만 됨(실제 감지/발송은 다음 단계).
  Future<AlertSettings> getAlertSettings(int deviceId) async {
    final uri = Uri.parse('$baseUrl/devices/$deviceId/alert-settings');
    final res = await http.get(uri);
    _checkOk(res);
    return AlertSettings.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<AlertSettings> setAlertSettings(int deviceId, AlertSettings settings) async {
    final uri = Uri.parse('$baseUrl/devices/$deviceId/alert-settings');
    final res = await http.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(settings.toJson()),
    );
    _checkOk(res);
    return AlertSettings.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<void> addWatch(int deviceId, String keyword) async {
    final uri = Uri.parse('$baseUrl/watches');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId, 'keyword': keyword}),
    );
    _checkOk(res);
  }

  Future<List<KeywordWatch>> listWatches(int deviceId) async {
    final uri = Uri.parse('$baseUrl/watches/$deviceId');
    final res = await http.get(uri);
    _checkOk(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((e) => KeywordWatch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteWatch(int watchId) async {
    final uri = Uri.parse('$baseUrl/watches/$watchId');
    final res = await http.delete(uri);
    _checkOk(res);
  }

  /// 2026-09-06: 종목 추가 시 자동완성용 카탈로그 — "티커를 미리 알고
  /// 있어야 하는 게 불편하다"는 피드백으로 추가. /search의 전체 인덱스와
  /// 같은 패턴(한 번에 통째로 받아서 타이핑마다 로컬에서 걸러냄).
  Future<List<StockCatalogEntry>> getStockCatalog() async {
    final uri = Uri.parse('$baseUrl/stocks/catalog');
    final res = await http.get(uri);
    _checkOk(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((e) => StockCatalogEntry.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 2026-09-07: 관심 종목 가격을 "탭하면 원화로" 토글하는 기능용 환율.
  /// 서버가 하루 단위로 캐싱해서 갱신함(Frankfurter.app) — 아직 한 번도
  /// 못 가져왔으면(막 시작 직후 등) 503, 그때는 null을 돌려줘서 호출하는
  /// 쪽이 그냥 달러만 보여주면 됨.
  Future<double?> getUsdKrwRate() async {
    final uri = Uri.parse('$baseUrl/fx/usd-krw');
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return (map['usd_krw'] as num).toDouble();
  }

  /// 2026-09-06: 관심 종목(브랜드) 뉴스. 기기가 한 번도 등록한 적 없으면
  /// 서버가 기본 10개로 자동 시드해서 돌려줌 — 클라이언트는 그냥 받아서
  /// 보여주면 됨. 뉴스 목록도 항목마다 통째로 포함돼 있어서(/trending과
  /// 같은 이유) 펼칠 때 추가 호출이 필요 없음.
  Future<List<StockWatch>> listStockWatches(int deviceId) async {
    final uri = Uri.parse('$baseUrl/devices/$deviceId/stocks');
    final res = await http.get(uri);
    _checkOk(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((e) => StockWatch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<StockWatch> addStockWatch(int deviceId, String ticker) async {
    final uri = Uri.parse('$baseUrl/stocks');
    final res = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId, 'ticker': ticker}),
    );
    _checkOk(res);
    return StockWatch.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<void> deleteStockWatch(int watchId) async {
    final uri = Uri.parse('$baseUrl/stocks/$watchId');
    final res = await http.delete(uri);
    _checkOk(res);
  }

  void _checkOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, res.body);
    }
  }
}

class AlertSettings {
  const AlertSettings({
    required this.enabled,
    required this.intervalMinutes,
    required this.quietHoursStart,
    required this.quietHoursEnd,
    required this.minOutletCount,
    required this.categories,
    required this.maxDailyAlerts,
  });

  final bool enabled;
  final int intervalMinutes;
  final int quietHoursStart;
  final int quietHoursEnd;
  final int minOutletCount;

  /// null이면 전체 카테고리.
  final List<String>? categories;
  final int maxDailyAlerts;

  factory AlertSettings.fromJson(Map<String, dynamic> json) => AlertSettings(
        enabled: json['periodic_alert_enabled'] as bool,
        intervalMinutes: json['periodic_interval_minutes'] as int,
        quietHoursStart: json['quiet_hours_start'] as int,
        quietHoursEnd: json['quiet_hours_end'] as int,
        minOutletCount: json['min_outlet_count'] as int,
        categories: (json['alert_categories'] as List?)?.cast<String>(),
        maxDailyAlerts: json['max_daily_alerts'] as int,
      );

  Map<String, dynamic> toJson() => {
        'periodic_alert_enabled': enabled,
        'periodic_interval_minutes': intervalMinutes,
        'quiet_hours_start': quietHoursStart,
        'quiet_hours_end': quietHoursEnd,
        'min_outlet_count': minOutletCount,
        'alert_categories': categories,
        'max_daily_alerts': maxDailyAlerts,
      };

  AlertSettings copyWith({
    bool? enabled,
    int? intervalMinutes,
    int? quietHoursStart,
    int? quietHoursEnd,
    int? minOutletCount,
    Object? categories = _unset,
    int? maxDailyAlerts,
  }) =>
      AlertSettings(
        enabled: enabled ?? this.enabled,
        intervalMinutes: intervalMinutes ?? this.intervalMinutes,
        quietHoursStart: quietHoursStart ?? this.quietHoursStart,
        quietHoursEnd: quietHoursEnd ?? this.quietHoursEnd,
        minOutletCount: minOutletCount ?? this.minOutletCount,
        categories: identical(categories, _unset) ? this.categories : categories as List<String>?,
        maxDailyAlerts: maxDailyAlerts ?? this.maxDailyAlerts,
      );
}

const _unset = Object();

class KeywordWatch {
  const KeywordWatch({required this.id, required this.keyword});

  final int id;
  final String keyword;

  factory KeywordWatch.fromJson(Map<String, dynamic> json) => KeywordWatch(
        id: json['id'] as int,
        keyword: json['keyword'] as String,
      );
}

class StockNewsItem {
  const StockNewsItem({required this.title, required this.link, required this.source, this.titleKo, this.published});

  final String title;
  final String link;

  /// 2026-09-06: 야후 파이낸스 RSS는 여러 매체를 모아 보여주는
  /// 애그리게이터라("Yahoo Finance"로 뭉뚱그리면 신뢰도를 알 수 없다는
  /// 피드백으로) 기사 링크 도메인에서 뽑은 실제 매체명(backend/stocks.py
  /// 참고).
  final String source;

  /// 파파고로 번역한 한국어 제목(backend/translate.py) — 번역 실패(키
  /// 없음/API 오류) 시 null, 그때는 원문(title)만 보여주면 됨.
  final String? titleKo;
  final String? published;

  factory StockNewsItem.fromJson(Map<String, dynamic> json) => StockNewsItem(
        title: json['title'] as String,
        link: json['link'] as String,
        source: json['source'] as String? ?? 'Yahoo Finance',
        titleKo: json['title_ko'] as String?,
        published: json['published'] as String?,
      );
}

class StockCatalogEntry {
  const StockCatalogEntry({required this.ticker, required this.name, required this.sector});

  final String ticker;
  final String name;
  final String sector;

  factory StockCatalogEntry.fromJson(Map<String, dynamic> json) => StockCatalogEntry(
        ticker: json['ticker'] as String,
        name: json['name'] as String,
        sector: json['sector'] as String,
      );
}

class StockQuote {
  const StockQuote({required this.price, required this.change, required this.percent});

  final double price;
  final double change;
  final double percent;

  factory StockQuote.fromJson(Map<String, dynamic> json) => StockQuote(
        price: (json['price'] as num).toDouble(),
        change: (json['change'] as num).toDouble(),
        percent: (json['percent'] as num).toDouble(),
      );
}

class StockWatch {
  const StockWatch({
    required this.id,
    required this.ticker,
    required this.name,
    required this.sector,
    required this.news,
    this.quote,
  });

  final int id;
  final String ticker;
  final String name;
  final String sector;
  final List<StockNewsItem> news;

  /// 2026-09-07: Finnhub 현재가/변동(quotes.py) — 키 없거나 API 실패
  /// 시 null, 그때는 가격 없이 뉴스만 보여주면 됨.
  final StockQuote? quote;

  /// POST /stocks 응답에는 news/quote 필드가 없음(막 추가한 티커라 아직
  /// 캐시된 데이터가 없어서) — 그때는 빈 목록/null로 처리.
  factory StockWatch.fromJson(Map<String, dynamic> json) => StockWatch(
        id: json['id'] as int,
        ticker: json['ticker'] as String,
        name: json['name'] as String,
        sector: json['sector'] as String,
        news: (json['news'] as List?)
                ?.map((e) => StockNewsItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
        quote: json['quote'] != null ? StockQuote.fromJson(json['quote'] as Map<String, dynamic>) : null,
      );
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}
