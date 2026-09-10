import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// 2026-09-08: 실제 FCM 등록 토큰을 받아옴 — 예전엔 기기 식별용으로 그냥
/// 로컬에서 만든 랜덤 문자열(device_registry.dart의 _randomToken)을
/// 썼는데, 실제 발송이 되려면 진짜 FCM 토큰이 필요함. 웹은 VAPID 키가
/// 따로 필요해서(Firebase 콘솔 > Cloud Messaging > 웹 푸시 인증서) 아직
/// 안 받아왔으면 null을 돌려주고, 호출하는 쪽이 기존 랜덤 토큰 방식으로
/// 폴백함 — 나중에 VAPID 키만 채워 넣으면 자동으로 진짜 토큰을 쓰게 됨.
/// 권한 거부/미지원 브라우저 등 어떤 이유로든 실패하면 조용히 null(다른
/// 외부 연동들과 같은 방어 원칙 — 알림 기능 하나 실패가 앱 전체를
/// 막으면 안 됨).
const _webVapidKey = 'BBmIysMB6lZKqHoa6bk2R4E3i08n9QqCi-PQPjyDiabUlW5Fcnt3mePH3qjojLTh3HK1lpcyXmajHQFcw7T-Qj4';

Future<String?> getFcmToken() async {
  try {
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) return null;
    if (kIsWeb) {
      if (_webVapidKey.isEmpty) return null;
      return await FirebaseMessaging.instance.getToken(vapidKey: _webVapidKey);
    }
    return await FirebaseMessaging.instance.getToken();
  } catch (_) {
    return null;
  }
}
