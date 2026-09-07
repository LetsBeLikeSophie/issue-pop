import 'package:flutter/material.dart';

import 'api_client.dart';
import 'favorites_store.dart';
import 'screens/home_screen.dart';
import 'text_scale_store.dart';
import 'theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await FavoritesStore.instance.load();
  await TextScaleStore.instance.load();
  runApp(const IssuePopApp());
}

class IssuePopApp extends StatelessWidget {
  const IssuePopApp({super.key});

  @override
  Widget build(BuildContext context) {
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
  }
}
