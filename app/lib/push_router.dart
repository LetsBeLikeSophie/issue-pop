import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'api_client.dart';
import 'screens/issue_screen.dart';

/// 2026-10-13: 푸시 알림을 눌렀을 때 앱 첫 화면만 열리던 걸, 알림이 가리키는
/// 이슈로 바로 이동하게 함. 서버(backend/api.py의 _issue_push_data)가 알림에
/// data payload({type: issue, issue_id, keyword})를 같이 실어 보냄.
///
/// - 앱이 완전히 꺼진 상태에서 알림을 눌러 켠 경우: getInitialMessage()
/// - 앱이 백그라운드에 있다가 알림을 누른 경우: onMessageOpenedApp
/// 앱이 화면에 떠 있는 동안 온 알림(포그라운드)은 안드로이드가 알림창에 안 띄우니
/// 따로 처리하지 않음. Firebase를 Android에서만 초기화하므로(main.dart) 그 외
/// 플랫폼에서는 아무것도 안 함.
class PushRouter {
  PushRouter({required this.navigatorKey, required this.api});

  final GlobalKey<NavigatorState> navigatorKey;
  final ApiClient api;

  Future<void> init() async {
    if (kIsWeb || !Platform.isAndroid) return;
    FirebaseMessaging.onMessageOpenedApp.listen(_open);
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      // 콜드 스타트에선 Navigator가 아직 안 붙어있을 수 있어서 첫 프레임 뒤에 엶.
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(initial));
    }
  }

  void _open(RemoteMessage message) {
    final data = message.data;
    if (data['type'] != 'issue') return;
    final issueId = data['issue_id'];
    if (issueId == null || issueId.isEmpty) return;
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (_) => IssueScreen(api: api, issueId: issueId, keyword: data['keyword']),
      ),
    );
  }
}
