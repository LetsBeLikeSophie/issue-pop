import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:issue_pop/api_client.dart';
import 'package:issue_pop/device_registry.dart';
import 'package:issue_pop/screens/settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-10-26(출시 전 점검 IP-17): 설정의 "지원" 섹션에서 오픈소스 라이선스 화면을 열 수 있어야 함.
void main() {
  testWidgets('설정 > 지원에 "오픈소스 라이선스"가 있고 누르면 라이선스 화면이 열린다', (tester) async {
    tester.view.physicalSize = const Size(1080, 4200);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    DeviceRegistry.resetForTest();
    SharedPreferences.setMockInitialValues({'device_id_v1': 1, 'device_push_token_v1': 'x' * 40, 'device_secret_v1': 's'});
    final client = MockClient((req) async {
      final body = req.url.path == '/sources' ? [] : {};
      return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
    });
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);

    await tester.pumpWidget(MaterialApp(home: SettingsScreen(api: api)));
    await tester.pump(const Duration(milliseconds: 500));

    // 모바일 앱(웹이 아님)에서는 외부 후원 링크를 보여주지 않음(Play 정책 위험).
    expect(find.text('Buy Me a Coffee'), findsNothing);

    final row = find.text('오픈소스 라이선스');
    await tester.scrollUntilVisible(row, 300, scrollable: find.byType(Scrollable).first);
    expect(row, findsOneWidget);

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
  });
}
