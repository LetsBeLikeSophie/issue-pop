import 'dart:convert';
import 'package:http/http.dart' as http;

import 'models/issue.dart';

/// backend/api.py 클라이언트. 지금은 로컬 개발 서버(uvicorn api:app
/// --port 8000)를 가리킴 — 인프라 배포 전까지는 이 baseUrl만 나중에
/// 바꾸면 됨(CLAUDE.md: "FastAPI 코드 자체는 인프라 선택과 무관하게
/// 그대로 씀").
///
/// 2026-08-25: 'localhost' 대신 '127.0.0.1'을 씀 — 이 개발 환경(Windows)
/// 에서 'localhost' 호스트명 해석 자체가 요청마다 약 2초씩 걸리는 걸
/// 실측으로 발견함(127.0.0.1로 직접 IP를 주면 90ms 수준). 그동안
/// "검색이 느리다"는 피드백의 진짜 원인이 이거였을 가능성이 큼 —
/// 클라이언트/서버 구조를 아무리 가볍게 고쳐도 이 지연 앞에서는 체감이
/// 안 됐을 것.
class ApiClient {
  ApiClient({this.baseUrl = 'http://127.0.0.1:8000'});

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

  void _checkOk(http.Response res) {
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(res.statusCode, res.body);
    }
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}
