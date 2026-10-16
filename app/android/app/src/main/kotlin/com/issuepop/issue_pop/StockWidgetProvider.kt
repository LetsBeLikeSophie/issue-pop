package com.issuepop.issue_pop

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import kotlin.concurrent.thread

/**
 * 2026-10-17: 홈 화면 "관심 종목" 위젯 — 고른 종목 최대 3개의 현재가/등락률.
 * 데이터/그리기는 StockWidgetData, 종목 고르는 화면은 StockWidgetConfigureActivity.
 *
 * 갱신 주기는 stock_widget_info.xml의 updatePeriodMillis(30분, 안드로이드 최소값) —
 * 서버가 종목 시세를 30분마다 갱신하니 그와 맞음. 네트워크 요청은 메인 스레드에서 못 하니까
 * goAsync()로 방송 수신을 잠깐 붙잡고 별도 스레드에서 처리함(WorkManager 안 씀).
 */
class StockWidgetProvider : AppWidgetProvider() {

  override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
    val pending = goAsync()
    thread {
      try {
        appWidgetIds.forEach { id ->
          try {
            StockWidgetData.refresh(context, appWidgetManager, id)
          } catch (e: Throwable) {
            // 위젯 하나 실패가 다른 위젯/앱에 영향 주면 안 됨.
          }
        }
      } finally {
        pending.finish()
      }
    }
  }

  override fun onDeleted(context: Context, appWidgetIds: IntArray) {
    try {
      StockWidgetData.clear(context, appWidgetIds)
    } catch (e: Throwable) {
    }
  }
}
