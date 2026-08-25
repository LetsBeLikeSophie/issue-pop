import 'package:flutter_test/flutter_test.dart';

import 'package:issue_pop/main.dart';

void main() {
  testWidgets('앱이 크래시 없이 홈 화면을 그린다', (WidgetTester tester) async {
    await tester.pumpWidget(const IssuePopApp());
    await tester.pump();

    expect(find.text('뉴스'), findsOneWidget);
    expect(find.text('키워드 또는 헤드라인 검색…'), findsOneWidget);
  });
}
