# issue_pop

Issue Pop(이슈판) 모바일 앱(Flutter).

## 빌드

서버 주소는 `--dart-define=API_BASE_URL=...`로 정함. 릴리스 빌드는 값을 안 줘도 운영 서버(`https://api.issue-pop.com`)로
나가지만, 헷갈리지 않게 아래처럼 항상 명시해서 빌드함. 개발(`flutter run`)은 값이 없으면 로컬 서버(`http://127.0.0.1:8000`).

```bash
# 테스트용 APK
flutter build apk --release --dart-define=API_BASE_URL=https://api.issue-pop.com
# Play 업로드용 AAB
flutter build appbundle --release --dart-define=API_BASE_URL=https://api.issue-pop.com
```

- 버전은 `pubspec.yaml`의 `version: 1.2.0+N` — 빌드할 때마다 `+N`만 올림(Play는 번호가 이전보다 커야 업로드됨).
- 릴리스 서명은 `android/key.properties`와 `upload-keystore.jks`(git에 없음)가 있어야 함. 없으면 빌드가 실패함.
- 서명 확인: `apksigner verify --print-certs <apk>`(SHA-256이 업로드 키와 같아야 함).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
