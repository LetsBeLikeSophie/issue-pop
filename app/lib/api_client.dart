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

  // 2026-09-26: 지금까지 모든 호출이 http 패키지의 top-level 함수
  // (http.get/post/put/delete)를 썼는데, 이 함수들은 호출마다 내부적으로
  // 새 Client를 만들고 요청 하나 끝나면 바로 닫아버림(패키지 공식 문서도
  // "같은 서버에 여러 요청을 보낼 거면 Client 하나를 계속 재사용하라"고
  // 안내함) — 그래서 설정 화면처럼 화면 하나에서 여러 엔드포인트를 동시에
  // 부르면(다이제스트/관심 키워드/오늘의 단어/매체 목록 등) 매번 TCP+TLS
  // 핸드셰이크를 처음부터 다시 하고 있었음(설정 화면 로딩이 느리다는
  // 피드백의 원인으로 추정). ApiClient가 앱 전체에서 인스턴스 하나만
  // 만들어져 쓰이므로(main.dart), 이 Client 하나를 계속 재사용하면
  // Keep-Alive로 커넥션을 재활용해서 두 번째 요청부터는 핸드셰이크를
  // 건너뜀.
  final http.Client _client = http.Client();

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
    final res = await _client.get(uri);
    _checkOk(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((e) => IssueDetail.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 2026-09-21: 상단바의 "N분 전 업데이트" 표시용 — 서버가 30분마다
  /// 재수집/재클러스터링하면서 기록해두는 시각(_last_refresh)을 그대로
  /// 씀. 새 엔드포인트 없이 이미 있던 /health를 재사용함.
  Future<DateTime?> getLastRefresh() async {
    final uri = Uri.parse('$baseUrl/health');
    final res = await _client.get(uri);
    _checkOk(res);
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final ts = map['last_refresh'] as num?;
    if (ts == null) return null;
    return DateTime.fromMillisecondsSinceEpoch((ts * 1000).round(), isUtc: true).toLocal();
  }

  Future<Map<String, int>> getCategories() async {
    final uri = Uri.parse('$baseUrl/categories');
    final res = await _client.get(uri);
    _checkOk(res);
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return map.map((k, v) => MapEntry(k, v as int));
  }

  /// 홈 마스트헤드 통계용 — 이슈/기사 개수만 가볍게 집계해서 받음(전체
  /// 이슈를 기사까지 통째로 받던 예전 방식보다 훨씬 가벼움).
  Future<({int issueCount, int articleCount})> getStats() async {
    final uri = Uri.parse('$baseUrl/stats');
    final res = await _client.get(uri);
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
    final res = await _client.get(uri);
    _checkOk(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((e) => IssueSummary.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 검색 결과처럼 요약만 갖고 있을 때, 펼쳐볼 때 그제서야 기사 목록까지
  /// 받아옴.
  Future<IssueDetail> getIssue(String issueId) async {
    final uri = Uri.parse('$baseUrl/issues/$issueId');
    final res = await _client.get(uri);
    _checkOk(res);
    return IssueDetail.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// 로그인 없이 기기를 서버에 등록(다이제스트 알림 설정 등에 씀).
  /// 이미 등록된 push_token이면 서버가 기존 device_id를 그대로 돌려줌.
  Future<int> registerDevice(String pushToken) async {
    final uri = Uri.parse('$baseUrl/devices');
    final res = await _client.post(
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
    final res = await _client.get(uri);
    _checkOk(res);
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return map['digest_hour'] as int?;
  }

  Future<void> setDigestHour(int deviceId, int? hour) async {
    final uri = Uri.parse('$baseUrl/devices/$deviceId/digest');
    final res = await _client.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'hour': hour}),
    );
    _checkOk(res);
  }

  /// 2026-09-10: 실제 발송(FCM)은 아직 안 붙었지만, "그럼 뭐가 발송되는데?"를
  /// 확인할 수 있게 지금 이 순간의 다이제스트 텍스트만 미리 보여줌(부수효과 없음).
  Future<String> getDigestPreview() async {
    final uri = Uri.parse('$baseUrl/digest/preview');
    final res = await _client.get(uri);
    _checkOk(res);
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return map['text'] as String;
  }

  /// 2026-09-11: 오늘의 단어(오늘 기사에서 뽑은 단어+예문, 뜻풀이는
  /// 사전 API 연동 전까지 null).
  Future<WordOfDay> getWordOfDay() async {
    final uri = Uri.parse('$baseUrl/word-of-day');
    final res = await _client.get(uri);
    _checkOk(res);
    return WordOfDay.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<bool> getWordOfDayAlert(int deviceId) async {
    final uri = Uri.parse('$baseUrl/devices/$deviceId/word-of-day-alert');
    final res = await _client.get(uri);
    _checkOk(res);
    final map = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return map['word_of_day_enabled'] as bool;
  }

  Future<void> setWordOfDayAlert(int deviceId, bool enabled) async {
    final uri = Uri.parse('$baseUrl/devices/$deviceId/word-of-day-alert');
    final res = await _client.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'enabled': enabled}),
    );
    _checkOk(res);
  }

  /// 2026-09-26: "관심 이슈 알림" — 이 기기가 등록한 관심 키워드(관심
  /// 키워드 화면에서 관리)와 매칭되는 새 이슈가 뜨면 알림. 원래
  /// "실시간 트렌드 알림"이라는 이름으로 체크주기/조용한시간대/최소매체수
  /// /하루최대알림/관심카테고리까지 옵션이 6개나 있었는데, 실제 감지·발송
  /// 로직을 끝내 안 만들어서 설정만 저장되고 아무 것도 안 오는 상태로
  /// 방치돼 있었음 — 걷어내고 이 토글 하나로 대체함(word_of_day-alert와
  /// 같은 단계 구성).
  /// 2026-09-26: 조용한 시간대(quiet_start/quiet_end)를 같이 관리하게
  /// bool 하나에서 [KeywordAlertSettings]로 확장함 — "실시간 트렌드
  /// 알림"의 6개 옵션 중 유일하게 실제로 쓸모 있던 게 이거라 다시 붙임.
  Future<KeywordAlertSettings> getKeywordAlert(int deviceId) async {
    final uri = Uri.parse('$baseUrl/devices/$deviceId/keyword-alert');
    final res = await _client.get(uri);
    _checkOk(res);
    return KeywordAlertSettings.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<KeywordAlertSettings> setKeywordAlert(int deviceId, KeywordAlertSettings settings) async {
    final uri = Uri.parse('$baseUrl/devices/$deviceId/keyword-alert');
    final res = await _client.put(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'enabled': settings.enabled,
        'quiet_start': settings.quietStart,
        'quiet_end': settings.quietEnd,
      }),
    );
    _checkOk(res);
    return KeywordAlertSettings.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  /// 2026-09-22: 설정 화면 "문의하기" — mailto: 링크 대신 인앱 폼에서
  /// 바로 서버(POST /feedback)로 보냄. contactEmail은 선택(직접 답장할
  /// 때만 씀, 자동 답장 기능은 없음).
  Future<void> submitFeedback({required int? deviceId, required String message, String? contactEmail}) async {
    final uri = Uri.parse('$baseUrl/feedback');
    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'device_id': deviceId,
        'message': message,
        if (contactEmail != null && contactEmail.isNotEmpty) 'contact_email': contactEmail,
      }),
    );
    _checkOk(res);
  }

  Future<void> addWatch(int deviceId, String keyword) async {
    final uri = Uri.parse('$baseUrl/watches');
    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId, 'keyword': keyword}),
    );
    _checkOk(res);
  }

  Future<List<KeywordWatch>> listWatches(int deviceId) async {
    final uri = Uri.parse('$baseUrl/watches/$deviceId');
    final res = await _client.get(uri);
    _checkOk(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((e) => KeywordWatch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<void> deleteWatch(int watchId) async {
    final uri = Uri.parse('$baseUrl/watches/$watchId');
    final res = await _client.delete(uri);
    _checkOk(res);
  }

  /// 2026-09-26: 설정 화면 "앱 정보"에 서비스 중인 언론사 목록을 보여주려고
  /// 추가. 정치성향 등은 서버에서부터 안 내려줌(일반 사용자 화면에 다시
  /// 노출 안 하기로 한 결정, sources.py의 GET /sources 참고).
  Future<List<SourceOutlet>> getSources() async {
    final uri = Uri.parse('$baseUrl/sources');
    final res = await _client.get(uri);
    _checkOk(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((e) => SourceOutlet.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 2026-09-06: 종목 추가 시 자동완성용 카탈로그 — "티커를 미리 알고
  /// 있어야 하는 게 불편하다"는 피드백으로 추가. /search의 전체 인덱스와
  /// 같은 패턴(한 번에 통째로 받아서 타이핑마다 로컬에서 걸러냄).
  Future<List<StockCatalogEntry>> getStockCatalog() async {
    final uri = Uri.parse('$baseUrl/stocks/catalog');
    final res = await _client.get(uri);
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
    final res = await _client.get(uri);
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
    final res = await _client.get(uri);
    _checkOk(res);
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((e) => StockWatch.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<StockWatch> addStockWatch(int deviceId, String ticker) async {
    final uri = Uri.parse('$baseUrl/stocks');
    final res = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId, 'ticker': ticker}),
    );
    _checkOk(res);
    return StockWatch.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  Future<void> deleteStockWatch(int watchId) async {
    final uri = Uri.parse('$baseUrl/stocks/$watchId');
    final res = await _client.delete(uri);
    _checkOk(res);
  }

  void _checkOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, res.body);
    }
  }
}

class KeywordWatch {
  const KeywordWatch({required this.id, required this.keyword});

  final int id;
  final String keyword;

  factory KeywordWatch.fromJson(Map<String, dynamic> json) => KeywordWatch(
        id: json['id'] as int,
        keyword: json['keyword'] as String,
      );
}

class WordOfDay {
  const WordOfDay({required this.word, required this.example, required this.definition});

  final String? word;
  final String? example;
  final String? definition;

  factory WordOfDay.fromJson(Map<String, dynamic> json) => WordOfDay(
        word: json['word'] as String?,
        example: json['example'] as String?,
        definition: json['definition'] as String?,
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

class KeywordAlertSettings {
  const KeywordAlertSettings({required this.enabled, required this.quietStart, required this.quietEnd});

  final bool enabled;

  /// 이 시각부터(quietStart)~이 시각까지(quietEnd) 알림을 안 보냄.
  /// quietStart == quietEnd면 조용한 시간대 없음(항상 허용). quietStart >
  /// quietEnd면 자정을 넘는 구간(예: 23~7)으로 취급함(백엔드 _in_quiet_hours
  /// 참고).
  final int quietStart;
  final int quietEnd;

  factory KeywordAlertSettings.fromJson(Map<String, dynamic> json) => KeywordAlertSettings(
        enabled: json['keyword_alert_enabled'] as bool,
        quietStart: json['keyword_alert_quiet_start'] as int,
        quietEnd: json['keyword_alert_quiet_end'] as int,
      );

  KeywordAlertSettings copyWith({bool? enabled, int? quietStart, int? quietEnd}) => KeywordAlertSettings(
        enabled: enabled ?? this.enabled,
        quietStart: quietStart ?? this.quietStart,
        quietEnd: quietEnd ?? this.quietEnd,
      );
}

class SourceOutlet {
  const SourceOutlet({required this.outlet, required this.category});

  final String outlet;
  final String category;

  factory SourceOutlet.fromJson(Map<String, dynamic> json) => SourceOutlet(
        outlet: json['outlet'] as String,
        category: json['category'] as String,
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
