import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:issue_pop/api_client.dart';
import 'package:issue_pop/device_registry.dart';
import 'package:issue_pop/notification_gate.dart';
import 'package:issue_pop/push_token.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 알림 권한 온보딩(NotificationGate) — 실제 OS 권한/네트워크는 가짜로 바꿔 끼워서 흐름만 확인.
void main() {
  late DeviceRegistry devices;
  var requested = 0;
  var openedSettings = 0;
  var requestResult = true;
  NotificationState state = NotificationState.notAsked;
  bool? result;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    devices = DeviceRegistry(ApiClient(baseUrl: 'http://fake'));
    requested = 0;
    openedSettings = 0;
    requestResult = true;
    state = NotificationState.notAsked;
    result = null;
    NotificationGate.readState = () async => state;
    NotificationGate.requestPermission = (_) async {
      requested++;
      return requestResult;
    };
    NotificationGate.openSettings = () async => openedSettings++;
  });

  Future<void> run(WidgetTester tester, {bool quiet = false}) async {
    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })),
    ));
    final f = NotificationGate.ensure(ctx, devices, title: '알림을 받아볼까요?', body: '이유 설명', quiet: quiet);
    f.then((v) => result = v);
    await tester.pumpAndSettle();
  }

  testWidgets('아직 안 물어봤으면 설명을 먼저 보여주고, 허용하기를 눌러야 OS 권한을 요청한다', (tester) async {
    await run(tester);
    expect(find.textContaining('이유 설명'), findsOneWidget);
    expect(find.textContaining("창에서 '허용'을 눌러주세요"), findsOneWidget);
    expect(requested, 0, reason: '설명 화면 단계에서는 OS 권한을 요청하면 안 됨');

    await tester.tap(find.text('알림 받기'));
    await tester.pumpAndSettle();
    expect(requested, 1);
    expect(result, isTrue);
  });

  testWidgets('"나중에"를 고르면 권한을 요청하지 않고 false, 곁다리(quiet) 질문은 3일간 다시 안 물음', (tester) async {
    await run(tester);
    await tester.tap(find.text('나중에'));
    await tester.pumpAndSettle();
    expect(requested, 0);
    expect(result, isFalse);

    await run(tester, quiet: true);
    expect(find.textContaining('이유 설명'), findsNothing, reason: '방금 거절했으니 곁다리로는 다시 안 물어야 함');
    expect(result, isFalse);
  });

  testWidgets('이미 허용됐으면 설명 없이 true', (tester) async {
    state = NotificationState.allowed;
    await run(tester);
    expect(find.textContaining('이유 설명'), findsNothing);
    expect(result, isTrue);
  });

  testWidgets('이미 거부했으면: 켜기 버튼으로 직접 시도한 경우엔 설정 안내, 곁다리(quiet)면 조용히 false', (tester) async {
    state = NotificationState.denied;
    await run(tester);
    expect(find.text('알림이 꺼져 있어요'), findsOneWidget);
    await tester.tap(find.text('설정 열기'));
    await tester.pumpAndSettle();
    expect(openedSettings, 1);
    expect(result, isFalse);

    result = null;
    await run(tester, quiet: true);
    expect(find.text('알림이 꺼져 있어요'), findsNothing);
    expect(result, isFalse);
  });
}
