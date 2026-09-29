import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'favorites_store.dart';
import 'firebase_options.dart';
import 'screens/home_screen.dart';
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
  await FavoritesStore.instance.load();
  await TextScaleStore.instance.load();
  await ThemeStore.instance.load();
  runApp(const IssuePopApp());
}

class IssuePopApp extends StatelessWidget {
  const IssuePopApp({super.key});

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
                  child: child!,
                );
              },
            );
          },
          home: HomeScreen(api: ApiClient()),
        );
      },
    );
  }
}
