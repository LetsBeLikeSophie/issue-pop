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
  companion object {
    /** 위젯 등이 앱을 열면서 "어느 화면으로 갈지" 알려주는 intent extra. */
    const val EXTRA_ROUTE = "issuepop_route"
  }

  private val settingsChannel = "issuepop/settings"
  private val stockWidgetChannel = "issuepop/stock_widget"

  // 아직 Dart가 가져가지 않은 이동 요청(앱이 꺼진 상태에서 위젯으로 켰을 때) — Dart가 시작 후 "takeLaunchRoute"로 가져감.
  private var pendingRoute: String? = null
  private var stockWidgetMethodChannel: MethodChannel? = null

  override fun onCreate(savedInstanceState: android.os.Bundle?) {
    super.onCreate(savedInstanceState)
    try {
      pendingRoute = intent?.getStringExtra(EXTRA_ROUTE)
    } catch (e: Throwable) {
    }
  }

  // 앱이 이미 떠 있을 때 위젯을 누르면(singleTop) 여기로 옴 — 바로 Dart에 이동하라고 알림.
  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    try {
      val route = intent.getStringExtra(EXTRA_ROUTE) ?: return
      val channel = stockWidgetMethodChannel
      if (channel != null) channel.invokeMethod("route", route) else pendingRoute = route
    } catch (e: Throwable) {
    }
  }

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    // 2026-10-17: 관심 종목 위젯용 — 기기 id와 위젯에 보일 종목을 받아 저장하고 위젯을 바로 갱신.
    // 전부 try/catch라 여기서 실패해도 앱은 영향 없음(StockWidgetData.kt 참고).
    stockWidgetMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, stockWidgetChannel)
    stockWidgetMethodChannel!!.setMethodCallHandler { call, result ->
      if (call.method == "takeLaunchRoute") {
        val route = pendingRoute
        pendingRoute = null
        result.success(route)
      } else if (call.method == "sync") {
        try {
          val deviceId = call.argument<Number>("deviceId")?.toLong()
          val tickers = call.argument<List<String>>("tickers") ?: emptyList()
          StockWidgetData.saveConfig(applicationContext, deviceId, tickers)
          StockWidgetProvider.requestUpdate(applicationContext)
          result.success(true)
        } catch (e: Throwable) {
          result.success(false)
        }
      } else {
        result.notImplemented()
      }
    }
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
