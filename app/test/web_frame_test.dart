import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:issue_pop/api_client.dart' show WordOfDay;
import 'package:issue_pop/models/promo.dart';
import 'package:issue_pop/widgets/web_frame.dart';

/// 2026-10-27: 웹 넓은 화면의 폰 프레임 + 양옆 카드.
Widget _app({
  required bool enabled,
  Future<List<PromoCard>> Function()? loader,
  Future<({int issueCount, int articleCount})> Function()? stats,
  Future<WordOfDay> Function()? word,
}) =>
    MaterialApp(
      home: Scaffold(
        body: WebFrame(
          enabled: enabled,
          promosLoader: loader,
          statsLoader: stats,
          wordLoader: word,
          child: const Center(child: Text('앱 화면')),
        ),
      ),
    );

void _size(WidgetTester tester, double w, double h) {
  tester.view.physicalSize = Size(w, h);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('넓은 화면: 폰 프레임 안에 앱이 있고 양옆에 소개·후원·테마 카드가 보인다', (tester) async {
    _size(tester, 1400, 900);
    await tester.pumpWidget(_app(enabled: true));
    await tester.pumpAndSettle();

    expect(find.text('앱 화면'), findsOneWidget);
    final appBox = tester.getRect(find.text('앱 화면'));
    expect(appBox.center.dx, closeTo(700, 2)); // 가운데에 고정
    expect(find.text('Buy Me a Coffee'), findsOneWidget); // 서버 없이도 기본 카드
    expect(find.text('Issue Pop'), findsOneWidget); // 왼쪽 소개
    expect(find.text('화면 색상'), findsOneWidget); // 웹엔 설정이 없어서 색 테마만 바로 고름
    expect(find.text('개인정보처리방침'), findsOneWidget);
  });

  testWidgets('서버에서 받은 카드(내 앱 소개)가 좌우 칸에 나뉘어 보인다', (tester) async {
    _size(tester, 1400, 900);
    await tester.pumpWidget(_app(
      enabled: true,
      loader: () async => const [
        PromoCard(id: 'coffee', title: 'Buy Me a Coffee', body: '', button: '후원', url: 'https://buymeacoffee.com/x'),
        PromoCard(id: 'a', title: '데일리컷', body: '공공데이터 한 장', button: '받기', url: 'https://example.com/a', left: true),
      ],
    ));
    await tester.pumpAndSettle();

    final leftCard = tester.getRect(find.text('데일리컷'));
    final rightCard = tester.getRect(find.text('Buy Me a Coffee'));
    final app = tester.getRect(find.text('앱 화면'));
    expect(leftCard.right, lessThan(app.left));
    expect(rightCard.left, greaterThan(app.right));
  });

  testWidgets('오늘의 숫자·오늘의 단어 카드가 왼쪽에 보이고, 못 받으면 그 카드만 숨는다', (tester) async {
    _size(tester, 1400, 900);
    await tester.pumpWidget(_app(
      enabled: true,
      stats: () async => (issueCount: 356, articleCount: 1038),
      word: () async => const WordOfDay(word: '비상계엄', example: '예문', definition: '국가 비상사태에 군대를 동원해 내리는 조치'),
    ));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 숫자'), findsOneWidget);
    expect(find.textContaining('356', findRichText: true), findsOneWidget);
    expect(find.textContaining('1038', findRichText: true), findsOneWidget);
    expect(find.text('오늘의 단어'), findsOneWidget);
    expect(find.text('비상계엄'), findsOneWidget);
    expect(tester.getRect(find.text('비상계엄')).right, lessThan(tester.getRect(find.text('앱 화면')).left));

    // 실패하면 그 카드만 숨고 나머지는 그대로(새로 시작한 것처럼 상태를 비우고 다시 그림)
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(_app(
      enabled: true,
      stats: () async => throw Exception('서버 점검 중'),
      word: () async => const WordOfDay(word: null, example: null, definition: null),
    ));
    await tester.pumpAndSettle();
    expect(find.text('오늘의 숫자'), findsNothing);
    expect(find.text('오늘의 단어'), findsNothing);
    expect(find.text('Issue Pop'), findsOneWidget);
  });

  testWidgets('서버 카드를 못 받으면(오류) 기본 카드로 대체한다', (tester) async {
    _size(tester, 1400, 900);
    await tester.pumpWidget(_app(enabled: true, loader: () async => throw Exception('서버 점검 중')));
    await tester.pumpAndSettle();

    expect(find.text('Buy Me a Coffee'), findsOneWidget);
  });

  testWidgets('폰 폭을 넘는 중간 화면(1000px 미만)은 프레임만 보이고 양옆 카드는 숨긴다', (tester) async {
    _size(tester, 900, 800);
    await tester.pumpWidget(_app(enabled: true));
    await tester.pumpAndSettle();

    expect(find.text('앱 화면'), findsOneWidget);
    expect(find.text('Buy Me a Coffee'), findsNothing);
  });

  testWidgets('좁은 화면(폰 브라우저)이나 앱에서는 프레임 없이 그대로 보인다', (tester) async {
    _size(tester, 500, 900);
    await tester.pumpWidget(_app(enabled: true));
    await tester.pumpAndSettle();
    expect(find.text('Buy Me a Coffee'), findsNothing);
    expect(tester.getRect(find.text('앱 화면')).center.dx, closeTo(250, 2));

    _size(tester, 1400, 900);
    await tester.pumpWidget(_app(enabled: false)); // 앱(웹 아님)
    await tester.pumpAndSettle();
    expect(find.text('Buy Me a Coffee'), findsNothing);
    expect(find.text('앱 화면'), findsOneWidget);
  });
}
