import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:shared_preferences/shared_preferences.dart';

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

/// 2026-09-28: getFcmToken()이 실패해도 예외를 조용히 삼켜버려서(원래
/// catch(_)), 실제 알림이 하루종일 안 가던 기기(77번)가 왜 계속 임시
/// 랜덤 토큰에 머무는지 전혀 알 방법이 없었음 — adb 없이도 실기기에서
/// 원인을 볼 수 있게, 마지막 시도 결과를 여기 남겨두고 설정 화면
/// "지원" 섹션에서 보여줌(settings_screen.dart의 진단 정보 참고).
class FcmDiagnostics {
  FcmDiagnostics._();
  static String? lastStatus;
  static String? lastError;
}

const _settingsChannel = MethodChannel('issuepop/settings');

/// 2026-09-28: "알림 설정 열기" 버튼용 — MainActivity.kt에 만들어둔
/// 네이티브 채널을 호출해서 기기의 앱 알림 설정 화면으로 바로 이동함.
Future<void> openNotificationSettings() async {
  if (kIsWeb) return;
  try {
    await _settingsChannel.invokeMethod('openNotificationSettings');
  } catch (e) {
    debugPrint('[Settings] openNotificationSettings 실패: $e');
  }
}

/// 2026-10-17: 알림 권한 온보딩 — 예전엔 기기 등록(설정/관심 키워드/관심 종목 화면에 들어가기만 해도
/// 일어남) 체인 안에서 getFcmToken()이 곧바로 OS 권한 팝업을 띄워서, 이유 설명도 없이 팝업이 떠 거부율이
/// 높았음. 이제 팝업은 사용자가 알림이 필요한 동작(알림 켜기/키워드 등록)을 할 때 한 번 설명을 보여주고
/// 동의한 뒤에만 뜸(notification_gate.dart). 아래 두 함수는 그 흐름용 — 상태 조회는 팝업을 안 띄움.
Future<AuthorizationStatus> notificationAuthorizationStatus() async {
  try {
    return (await FirebaseMessaging.instance.getNotificationSettings()).authorizationStatus;
  } catch (_) {
    return AuthorizationStatus.notDetermined;
  }
}

bool isNotificationAllowed(AuthorizationStatus s) =>
    s == AuthorizationStatus.authorized || s == AuthorizationStatus.provisional;

/// 알림 권한의 세 가지 상태. Android의 getNotificationSettings()는 "허용"(authorized)과 "허용 안 됨"(denied)
/// 두 가지만 돌려주고 "아직 안 물어봄"을 구분 못 함(플러그인 소스 확인) — 그래서 우리가 OS 권한 요청을 한 적이
/// 있는지를 직접 기록해서(_askedKey) 구분함. 허용 안 됨 + 아직 안 물어봄 = [notAsked](설명 화면을 보여줄 차례),
/// 허용 안 됨 + 이미 물어봄 = [denied](기기 설정으로 안내).
enum NotificationState { allowed, notAsked, denied }

const _askedKey = 'notification_permission_asked_v1';

Future<NotificationState> notificationState() async {
  if (isNotificationAllowed(await notificationAuthorizationStatus())) return NotificationState.allowed;
  try {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getBool(_askedKey) ?? false) ? NotificationState.denied : NotificationState.notAsked;
  } catch (_) {
    return NotificationState.notAsked;
  }
}

Future<void> markNotificationAsked() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_askedKey, true);
  } catch (_) {}
}

/// 웹 등 자동 초기화 설정을 지원하지 않는 곳에서는 조용히 무시.
Future<void> _enableAutoInit() async {
  try {
    await FirebaseMessaging.instance.setAutoInitEnabled(true);
  } catch (_) {}
}

/// 이미 권한이 있을 때만(팝업 없이) 토큰을 받아옴. 권한이 없으면 null.
/// FCM 자동 초기화를 꺼뒀기 때문에(AndroidManifest의 firebase_messaging_auto_init_enabled=false — 동의 전에는
/// FCM 등록 자체를 안 하려고) 권한이 있는 기기에서는 여기서 다시 켬.
Future<String?> getFcmTokenIfAllowed() async {
  try {
    if (!isNotificationAllowed(await notificationAuthorizationStatus())) return null;
    await _enableAutoInit();
    return kIsWeb
        ? (_webVapidKey.isEmpty ? null : await FirebaseMessaging.instance.getToken(vapidKey: _webVapidKey))
        : await FirebaseMessaging.instance.getToken();
  } catch (e) {
    debugPrint('[FCM] getFcmTokenIfAllowed 실패: $e');
    return null;
  }
}

/// 앱을 켤 때: 이미 알림을 허용한 기기는 FCM 자동 초기화를 다시 켜서(토큰 갱신이 끊기지 않게) 둠.
/// 권한이 없는 기기는 아무것도 안 함(= 팝업 없음, FCM 등록도 안 함).
Future<void> restorePushIfAllowed() async {
  try {
    if (isNotificationAllowed(await notificationAuthorizationStatus())) await _enableAutoInit();
  } catch (_) {}
}

Future<String?> getFcmToken() async {
  try {
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      FcmDiagnostics.lastStatus = '권한 거부됨(${settings.authorizationStatus.name})';
      FcmDiagnostics.lastError = null;
      return null;
    }
    await _enableAutoInit();
    final token = kIsWeb
        ? (_webVapidKey.isEmpty ? null : await FirebaseMessaging.instance.getToken(vapidKey: _webVapidKey))
        : await FirebaseMessaging.instance.getToken();
    FcmDiagnostics.lastStatus = '권한 ${settings.authorizationStatus.name}, 토큰 '
        '${token == null ? '못 받음(null)' : '받음(${token.length}자)'}';
    FcmDiagnostics.lastError = token == null ? 'FirebaseMessaging.getToken()이 null을 돌려줌' : null;
    return token;
  } catch (e) {
    debugPrint('[FCM] getFcmToken 실패: $e');
    FcmDiagnostics.lastStatus = '예외 발생';
    FcmDiagnostics.lastError = e.toString();
    return null;
  }
}
