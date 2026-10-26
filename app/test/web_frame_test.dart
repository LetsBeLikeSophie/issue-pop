import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:issue_pop/api_client.dart' show OutletStat, WordOfDay;
import 'package:issue_pop/models/promo.dart';
import 'package:issue_pop/theme.dart' show AppColors;
import 'package:issue_pop/theme_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:issue_pop/widgets/web_frame.dart';

/// 2026-10-27: 웹 넓은 화면의 폰 프레임 + 양옆 카드.
Widget _app({
  required bool enabled,
  Future<List<PromoCard>> Function()? loader,
  Future<({int issueCount, int articleCount})> Function()? stats,
  Future<WordOfDay> Function()? word,
  Future<List<OutletStat>> Function()? outlets,
}) =>
    MaterialApp(
      home: Scaffold(
        body: WebFrame(
          enabled: enabled,
          promosLoader: loader,
          statsLoader: stats,
          wordLoader: word,
          outletsLoader: outlets,
          child: const Center(child: Text('앱 화면')),
        ),
      ),
    );

/// 테마 색을 build에서 읽기만 하는 const 위젯(실제 앱의 화면들과 같은 형태).
class _ThemeProbe extends StatelessWidget {
  const _ThemeProbe();

  @override
  Widget build(BuildContext context) => Text('앱 화면', style: TextStyle(color: AppColors.ink));
}

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

  testWidgets('오늘의 숫자(왼쪽)·오늘의 단어(오른쪽) 카드가 보이고, 못 받으면 그 카드만 숨는다', (tester) async {
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
    expect(tester.getRect(find.text('비상계엄')).left, greaterThan(tester.getRect(find.text('앱 화면')).right)); // 단어 카드는 오른쪽 칸

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

  testWidgets('양옆 칸 글씨는 Material 안에서 그려져 노란 밑줄(형광펜처럼 보임) 없이 앱 기본 글자 스타일을 받는다', (tester) async {
    _size(tester, 1400, 900);
    // 실제 앱처럼 MaterialApp.builder 안(Scaffold 바깥)에 둠 — 여기서 Material이 없으면 Flutter 기본 스타일(노란 밑줄·고정폭 글꼴)이 붙음.
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => WebFrame(enabled: true, child: child!),
      home: const Scaffold(body: Center(child: Text('앱 화면'))),
    ));
    await tester.pumpAndSettle();

    final style = DefaultTextStyle.of(tester.element(find.text('Issue Pop'))).style;
    expect(style.decoration, isNot(TextDecoration.underline));
    expect(style.fontFamily, isNot('monospace'));
    expect(find.text('오늘 어떤 이슈가 많이 보도됐는지, 한눈에'), findsOneWidget);
  });

  testWidgets('버튼이 없는 안내 카드(준비 중)는 버튼 없이 글만 보인다', (tester) async {
    _size(tester, 1400, 900);
    await tester.pumpWidget(_app(
      enabled: true,
      loader: () async => const [
        PromoCard(id: 'app', title: '앱으로 더 편하게', body: '스토어에 등록되면 여기서 QR로 받을 수 있어요. (준비 중)', left: true),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('앱으로 더 편하게'), findsOneWidget);
    expect(find.textContaining('준비 중'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('후원 카드는 처음엔 버튼만 보이고, 누르면 아래로 펼쳐져 위젯이 나오고, 다시 누르면 접힌다', (tester) async {
    _size(tester, 1400, 900);
    WebFrame.debugAssumeEmbeddable = true;
    addTearDown(() => WebFrame.debugAssumeEmbeddable = false);
    await tester.pumpWidget(_app(
      enabled: true,
      loader: () async => const [
        PromoCard(
          id: 'coffee',
          title: 'Buy Me a Coffee',
          body: '응원해 주세요',
          button: '후원 페이지에서 열기',
          url: 'https://buymeacoffee.com/itssophie',
          highlight: true,
          embed: 'https://buymeacoffee.com/widget/page/itssophie',
        ),
      ],
    ));
    await tester.pumpAndSettle();

    // 처음: 접혀 있음(위젯 없음, 링크 버튼도 아직 없음)
    expect(find.text('응원하기'), findsOneWidget);
    expect(find.byKey(const ValueKey('embed-coffee')), findsNothing);
    final closedHeight = tester.getSize(find.ancestor(of: find.text('응원하기'), matching: find.byType(Container)).first).height;

    await tester.tap(find.text('응원하기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('embed-coffee')), findsOneWidget);
    expect(find.text('접기'), findsOneWidget);
    expect(find.text('후원 페이지에서 열기'), findsOneWidget); // 펼치면 작은 보조 링크
    final openHeight = tester.getSize(find.ancestor(of: find.text('접기'), matching: find.byType(Container)).first).height;
    expect(openHeight, greaterThanOrEqualTo(closedHeight)); // 카드가 아래로 길어짐

    await tester.tap(find.text('접기'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('embed-coffee')), findsNothing);
    expect(find.text('응원하기'), findsOneWidget);
  });

  testWidgets('임베드를 쓸 수 없는 곳(앱·테스트)에서는 후원 위젯 대신 링크 버튼이 나온다', (tester) async {
    _size(tester, 1400, 900);
    await tester.pumpWidget(_app(
      enabled: true,
      loader: () async => const [
        PromoCard(
          id: 'coffee',
          title: 'Buy Me a Coffee',
          button: '후원 페이지에서 열기',
          url: 'https://buymeacoffee.com/itssophie',
          highlight: true,
          embed: 'https://buymeacoffee.com/widget/page/itssophie',
        ),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('후원 페이지에서 열기'), findsOneWidget);
  });

  testWidgets('언론사별 기사 수 차트: 많은 순으로 막대 길이가 비율이고 홈페이지가 있는 언론사는 눌러서 갈 수 있다', (tester) async {
    _size(tester, 1400, 900);
    await tester.pumpWidget(_app(
      enabled: true,
      outlets: () async => const [
        OutletStat(outlet: '연합뉴스', count: 100, homepage: 'https://www.yna.co.kr'),
        OutletStat(outlet: '한겨레', count: 50, homepage: 'https://www.hani.co.kr'),
        OutletStat(outlet: '홈페이지 없음', count: 10),
        OutletStat(outlet: '이번엔 없음', count: 0, homepage: 'https://example.com'),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('언론사별 기사 수'), findsOneWidget);
    for (final name in ['연합뉴스', '한겨레', '홈페이지 없음', '이번엔 없음']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('100'), findsOneWidget);
    expect(find.text('0'), findsOneWidget);
    final top = tester.getSize(find.byKey(const ValueKey('bar-연합뉴스'))).width;
    final half = tester.getSize(find.byKey(const ValueKey('bar-한겨레'))).width;
    expect(half, closeTo(top / 2, 1.0)); // 비율대로
    expect(tester.getSize(find.byKey(const ValueKey('bar-이번엔 없음'))).width, lessThan(4)); // 0건은 아주 짧게
    // 이름이 눌리는 대상(링크 있음)과 안 눌리는 대상(링크 없음)
    expect(find.ancestor(of: find.text('연합뉴스'), matching: find.byType(InkWell)), findsOneWidget);
    expect(find.ancestor(of: find.text('홈페이지 없음'), matching: find.byType(InkWell)), findsNothing);
  });

  testWidgets('언론사 통계를 못 받으면 차트만 안 보이고 나머지는 그대로다', (tester) async {
    _size(tester, 1400, 900);
    await tester.pumpWidget(_app(enabled: true, outlets: () async => throw Exception('서버 점검 중')));
    await tester.pumpAndSettle();

    expect(find.text('언론사별 기사 수'), findsNothing);
    expect(find.text('Issue Pop'), findsOneWidget);
    expect(find.text('앱 화면'), findsOneWidget);
  });

  testWidgets('색 테마를 다크로 바꾸면 양옆 칸 글씨(로고 포함)와 폰 안의 화면이 모두 새 색으로 바뀐다', (tester) async {
    SharedPreferences.setMockInitialValues({}); // ThemeStore가 설정 저장소에 쓰므로(테스트에는 실제 저장소가 없음)
    _size(tester, 1400, 900);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => ListenableBuilder(
        listenable: ThemeStore.instance,
        builder: (context, _) => WebFrame(enabled: true, child: child!),
      ),
      // const 위젯: MaterialApp이 다시 그려져도 스스로는 안 다시 그려지는, 실제 앱 화면과 같은 처지
      home: const Scaffold(body: Center(child: _ThemeProbe())),
    ));
    await tester.pumpAndSettle();
    Color logoColor() => tester.widget<Text>(find.text('Issue Pop')).style!.color!;
    Color probeColor() => tester.widget<Text>(find.text('앱 화면')).style!.color!;
    final logoLight = logoColor();
    final probeLight = probeColor();

    await tester.tap(find.text('다크'));
    await tester.pumpAndSettle();

    expect(logoColor(), isNot(logoLight), reason: '다크로 바꿨는데 로고 색이 그대로면(옛 색 유지) 어두운 배경에서 안 보임');
    expect(probeColor(), isNot(probeLight), reason: '폰 안의 이미 열려 있던 화면도 새 색으로 다시 그려져야 함');

    await ThemeStore.instance.setPreset(ColorPreset.current);
    await tester.pumpAndSettle();
  });

  testWidgets('서버 카드를 못 받으면(오류) 기본 카드로 대체한다', (tester) async {
    _size(tester, 1400, 900);
    await tester.pumpWidget(_app(enabled: true, loader: () async => throw Exception('서버 점검 중')));
    await tester.pumpAndSettle();

    expect(find.text('Buy Me a Coffee'), findsOneWidget);
  });

  testWidgets('폰 폭을 넘는 중간 화면(1240px 미만)은 프레임만 보이고 양옆 카드는 숨긴다(넘침 없음)', (tester) async {
    _size(tester, 1200, 800);
    await tester.pumpWidget(_app(enabled: true));
    await tester.pumpAndSettle();

    expect(find.text('앱 화면'), findsOneWidget);
    expect(find.text('Buy Me a Coffee'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('양옆 칸이 처음 나타나는 폭(1240px)에서도 넘치지 않는다', (tester) async {
    _size(tester, 1240, 800);
    await tester.pumpWidget(_app(enabled: true));
    await tester.pumpAndSettle();

    expect(find.text('Buy Me a Coffee'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
