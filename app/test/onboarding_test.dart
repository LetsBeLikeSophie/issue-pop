import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:issue_pop/screens/onboarding_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 첫 설치 소개 화면(OnboardingScreen) — 한 번만 보이고, 이미 쓰던 기기에는 안 뜨는지.
void main() {
  test('처음 설치(기기 등록 없음, 본 적 없음)면 소개를 보여준다', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await OnboardingScreen.shouldShow(), isTrue);
  });

  test('이미 본 기기에는 다시 안 보여준다', () async {
    SharedPreferences.setMockInitialValues({'onboarding_seen_v1': true});
    expect(await OnboardingScreen.shouldShow(), isFalse);
  });

  test('이미 쓰던 기기(기기 id가 있음)는 업데이트해도 소개를 안 보이고 본 것으로 기록한다', () async {
    SharedPreferences.setMockInitialValues({'device_id_v1': 12});
    expect(await OnboardingScreen.shouldShow(), isFalse);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('onboarding_seen_v1'), isTrue);
  });

  testWidgets('3장을 다음으로 넘기고 시작하기를 누르면 닫히고 본 것으로 기록된다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OnboardingScreen())),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();

    expect(find.text('오늘의 이슈를 한눈에'), findsOneWidget);
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(find.text('관심 있는 것만 골라서'), findsOneWidget);
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(find.text('저장하고, 반응하고'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);

    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('onboarding_seen_v1'), isTrue);
  });

  testWidgets('건너뛰기도 바로 닫고 본 것으로 기록한다', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const OnboardingScreen())),
              child: const Text('열기'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();
    expect(find.byType(OnboardingScreen), findsNothing);
    expect((await SharedPreferences.getInstance()).getBool('onboarding_seen_v1'), isTrue);
  });
}
