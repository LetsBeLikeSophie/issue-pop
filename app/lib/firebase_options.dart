import 'package:firebase_core/firebase_core.dart';

/// 2026-09-08: FCM 다이제스트 알림 실제 발송 연동 시작 — Firebase 콘솔에서
/// 발급받은 웹 앱 설정. 이 apiKey는 서버 API 키와 달리 비밀값이 아니라
/// 클라이언트 코드에 그대로 박아도 되는 값임(Firebase 보안 규칙이 실제
/// 접근 제어를 담당, Firebase 공식 문서에도 안전하다고 명시돼 있음).
///
/// Android/iOS는 아직 등록 안 함 — google-services.json/
/// GoogleService-Info.plist 받아오면 flutterfire configure로 이 파일을
/// 통째로 다시 생성하거나, 여기에 currentPlatform 분기를 추가하면 됨.
/// 지금은 웹에서만 테스트 중이라 웹 옵션만 있음.
const firebaseOptionsWeb = FirebaseOptions(
  apiKey: 'AIzaSyA4Az4lGUp7C08syb7Nvu-GYeKS450S0JE',
  authDomain: 'issue-pop.firebaseapp.com',
  projectId: 'issue-pop',
  storageBucket: 'issue-pop.firebasestorage.app',
  messagingSenderId: '410098193711',
  appId: '1:410098193711:web:82442c2dad96836b8a7dda',
);
