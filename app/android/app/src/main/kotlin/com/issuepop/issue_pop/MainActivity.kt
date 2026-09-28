package com.issuepop.issue_pop

import android.content.Intent
import android.net.Uri
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 2026-09-28: 설정 화면의 "알림 설정 열기" 버튼용 — 기기의 앱 알림 설정
 * 화면을 직접 열어줌. permission_handler 같은 패키지를 새로 추가하는
 * 대신(오늘 home_widget 패키지 하나 때문에 며칠 크래시를 겪어서, 꼭
 * 필요한 것만 직접 짧게 네이티브로 짬) MethodChannel로 딱 이 기능만
 * 노출함. 백그라운드 작업이 전혀 없는 단순 버튼 클릭 처리라 오늘 겪은
 * WorkManager류 크래시와는 무관함.
 */
class MainActivity : FlutterActivity() {
  private val settingsChannel = "issuepop/settings"

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    MethodChannel(flutterEngine.dartExecutor.binaryMessenger, settingsChannel).setMethodCallHandler { call, result ->
      if (call.method == "openNotificationSettings") {
        try {
          startActivity(
              Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
          )
        } catch (e: Exception) {
          // ACTION_APP_NOTIFICATION_SETTINGS는 API 26+ 전용 — 그보다 낮은
          // 기기거나 어떤 이유로든 안 열리면 일반 앱 정보 화면으로라도 보냄.
          startActivity(
              Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))
          )
        }
        result.success(null)
      } else {
        result.notImplemented()
      }
    }
  }
}
