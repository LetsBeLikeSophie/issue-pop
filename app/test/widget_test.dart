import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:issue_pop/api_client.dart';
import 'package:issue_pop/main.dart';

void main() {
  testWidgets('앱이 크래시 없이 홈 화면을 그린다', (WidgetTester tester) async {
    // 테스트에선 실제 서버를 안 부르도록 연결이 안 되는 주소를 줌(에러 화면 경로 포함해서 안 죽는지만 확인).
    await tester.pumpWidget(
      IssuePopApp(api: ApiClient(baseUrl: 'http://127.0.0.1:9'), navigatorKey: GlobalKey<NavigatorState>()),
    );
    await tester.pump();

    expect(find.text('키워드 또는 헤드라인 검색…'), findsOneWidget);
  });
}
