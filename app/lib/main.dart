import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'favorites_store.dart';
import 'firebase_options.dart';
import 'presence_service.dart';
import 'push_token.dart';
import 'push_router.dart';
import 'reaction_store.dart';
import 'screens/home_screen.dart';
import 'screens/stock_watch_screen.dart';
import 'stock_widget_store.dart';
import 'text_scale_store.dart';
import 'theme.dart';
import 'theme_store.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 2026-09-08: 다이제스트 알림 실제 발송용 FCM 연동 — 웹은 firebase_options.dart의
  // 설정을 명시적으로 넘겨야 하고, Android는 google-services.json(Gradle
  // 플러그인이 읽음)을 네이티브가 자동으로 찾아서 옵션 없이 호출하면 됨.
  // iOS는 아직 GoogleService-Info.plist를 안 받아와서 건너뜀(초기화하면
  // 네이티브 설정 없이 죽을 수 있음).
  if (kIsWeb) {
    await Firebase.initializeApp(options: firebaseOptionsWeb);
  } else if (Platform.isAndroid) {
    await Firebase.initializeApp();
  }
  // 2026-10-17: FCM 자동 초기화는 꺼둠(AndroidManifest) — 이미 알림을 허용한 기기만 여기서 다시 켬.
  if (kIsWeb || Platform.isAndroid) await restorePushIfAllowed();
  await FavoritesStore.instance.load();
  await TextScaleStore.instance.load();
  await ThemeStore.instance.load();
  final api = ApiClient();
  final navigatorKey = GlobalKey<NavigatorState>();
  ReactionStore.instance.init(api);
  runApp(IssuePopApp(api: api, navigatorKey: navigatorKey));
  // "최근 10분간 N명이 봤어요" 신호 시작(서버가 최소 인원 미만이면 화면엔 안 보임)
  PresenceService.instance.start(api);
  // 홈 화면 위젯에 기기 id 전달(실패해도 앱엔 영향 없음 — stock_widget_store.dart)
  StockWidgetStore.syncKnownDeviceId();
  // 홈 화면 위젯을 눌러 열었을 때 "관심 종목" 화면으로 이동(첫 프레임 뒤에 — 콜드 스타트에서도 Navigator가 붙은 뒤)
  StockWidgetStore.listenForRoute((route) {
    if (route != 'stocks') return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => StockWatchScreen(api: api)));
    });
  });
  // 푸시 알림을 눌렀을 때 해당 이슈로 이동(push_router.dart)
  await PushRouter(navigatorKey: navigatorKey, api: api).init();
}

/// 2026-10-13: 태블릿/넓은 화면(웹 포함)에서 카드가 화면 끝까지 늘어나지 않게
/// 앱 전체 콘텐츠 최대 폭. 폰(보통 360~430dp)은 이보다 좁아서 영향 없음.
const _kMaxContentWidth = 720.0;

class IssuePopApp extends StatelessWidget {
  const IssuePopApp({super.key, required this.api, required this.navigatorKey});

  final ApiClient api;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    // 2026-09-09: 색 테마 프리셋을 바꾸면 AppColors.xxx(getter)가 다른
    // 값을 돌려주게 되는데, 그걸 화면에 실제로 반영하려면 트리가 다시
    // build돼야 함 — ListenableBuilder로 MaterialApp 전체를 감싸서
    // ThemeStore가 바뀔 때마다 theme(AppTheme.light)까지 통째로 새로
    // 계산되게 함(글자 크기는 이 안쪽에서 이미 하던 대로 처리).
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'Issue Pop',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          // 설정의 "글자 크기"를 앱 전체에 적용 — 화면마다 개별 텍스트에
          // textScaler를 넣는 대신, MaterialApp 루트에서 한 번만 감쌈.
          builder: (context, child) {
            return ListenableBuilder(
              listenable: TextScaleStore.instance,
              builder: (context, _) {
                final media = MediaQuery.of(context);
                return MediaQuery(
                  data: media.copyWith(
                    textScaler: TextScaler.linear(TextScaleStore.instance.scale),
                  ),
                  // 최대 폭을 넘는 화면에선 가운데 정렬(좌우는 앱 배경색).
                  child: ColoredBox(
                    color: AppColors.bg,
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: _kMaxContentWidth),
                        child: child!,
                      ),
                    ),
                  ),
                );
              },
            );
          },
          home: HomeScreen(api: api),
        );
      },
    );
  }
}
