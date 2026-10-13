import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:issue_pop/api_client.dart';
import 'package:issue_pop/main.dart';
import 'package:issue_pop/widgets/launch_loading.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('앱이 크래시 없이 홈 화면을 그린다 (처음엔 로딩 화면 → 응답이 오면 걷힘)', (WidgetTester tester) async {
    // 실제 서버 대신 빈 목록을 돌려주는 가짜 서버(요청이 즉시 끝나서, 로딩 화면의 최소 노출 시간만 기다리면 됨).
    final client = MockClient((req) async {
      final body = req.url.path == '/health' ? {'last_refresh': null} : [];
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
    });
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);

    await tester.pumpWidget(IssuePopApp(api: api, navigatorKey: GlobalKey<NavigatorState>()));
    await tester.pump();

    expect(find.byType(LaunchLoading), findsOneWidget, reason: '첫 응답 전엔 로딩 화면이 덮여 있어야 함');

    // 최소 노출 시간(0.5초) + 페이드아웃(0.28초)이 지나면 로딩 화면이 사라지고 홈이 보임.
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(LaunchLoading), findsNothing);
    expect(find.text('키워드 또는 헤드라인 검색…'), findsOneWidget);
  });
}
