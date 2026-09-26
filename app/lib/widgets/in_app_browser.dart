import 'package:flutter/material.dart';
import 'package:flutter_custom_tabs/flutter_custom_tabs.dart';

/// 2026-09-26: 기사 링크를 url_launcher의 LaunchMode.inAppBrowserView로
/// 열었더니, 앱으로 돌아오는 닫기/뒤로가기 버튼이 OS 기본 스타일(옅은
/// 색)이라 잘 안 보인다는 피드백 — url_launcher 자체는 툴바 색을
/// 커스터마이즈하는 옵션이 아예 없어서(BrowserConfiguration엔 showTitle
/// 뿐), flutter_custom_tabs로 바꿔서 툴바를 앱 아이콘과 같은 어두운
/// 색(#1F1F1F)으로, 버튼은 흰색으로 확실히 대비되게 함.
///
/// 닫기 버튼 위치 자체(좌측 상단)는 Android Custom Tabs/iOS
/// SFSafariViewController 둘 다 OS가 정한 표준 위치라 앱에서 옮길 수
/// 없음 — 대신 안드로이드 하드웨어/제스처 뒤로가기는 이 화면에서도
/// 그대로 동작해서(OS 기본 동작, 별도 구현 불필요) 스와이프/뒤로가기로
/// 돌아오는 것도 이미 됨.
Future<void> openInAppBrowser(Uri url) async {
  await launchUrl(
    url,
    customTabsOptions: CustomTabsOptions(
      colorSchemes: CustomTabsColorSchemes.defaults(toolbarColor: Color(0xFF1F1F1F)),
      shareState: CustomTabsShareState.on,
      urlBarHidingEnabled: true,
      showTitle: true,
      closeButton: CustomTabsCloseButton(icon: CustomTabsCloseButtonIcons.back),
    ),
    safariVCOptions: const SafariViewControllerOptions(
      preferredBarTintColor: Color(0xFF1F1F1F),
      preferredControlTintColor: Colors.white,
      barCollapsingEnabled: true,
      dismissButtonStyle: SafariViewControllerDismissButtonStyle.close,
    ),
  );
}
