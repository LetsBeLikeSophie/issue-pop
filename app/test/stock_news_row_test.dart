import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:issue_pop/api_client.dart';
import 'package:issue_pop/screens/stock_watch_screen.dart';

/// 2026-10-26(출시 전 점검 IP-16): AI가 번역한 제목에는 "AI 번역" 표시가 있어야 하고, 번역이 없는 원문 제목에는 없어야 함.
Widget _host(StockNewsItem item) => MaterialApp(home: Scaffold(body: StockNewsRow(item: item)));

void main() {
  testWidgets('번역된 제목에는 "AI 번역" 표시와 원문이 함께 보인다', (tester) async {
    await tester.pumpWidget(_host(const StockNewsItem(
      title: 'Nvidia surges on AI demand',
      titleKo: '엔비디아, AI 수요에 급등',
      link: 'https://example.com/a',
      source: 'Reuters',
    )));

    expect(find.text('엔비디아, AI 수요에 급등'), findsOneWidget);
    expect(find.textContaining('AI 번역'), findsOneWidget);
    expect(find.textContaining('Nvidia surges on AI demand'), findsOneWidget);
  });

  testWidgets('번역이 없으면(원문만 보임) "AI 번역" 표시가 없다', (tester) async {
    await tester.pumpWidget(_host(const StockNewsItem(
      title: 'Apple unveils new chip',
      link: 'https://example.com/b',
      source: 'Bloomberg',
    )));

    expect(find.text('Apple unveils new chip'), findsOneWidget);
    expect(find.textContaining('AI 번역'), findsNothing);
  });
}
