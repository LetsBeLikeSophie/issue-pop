package com.issuepop.issue_pop

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import kotlin.concurrent.thread

/**
 * 2026-10-17: 홈 화면 "관심 종목" 위젯 — 고른 종목 최대 3개의 현재가/등락률.
 * 데이터/그리기는 StockWidgetData. 위젯에 보일 종목은 앱의 관심 종목 화면에서 끌어다 놓아 정함
 * (MainActivity의 "issuepop/stock_widget" 채널 → StockWidgetData.saveConfig). 위젯을 추가할 때
 * 따로 뜨는 설정 화면은 없음.
 *
 * 갱신 주기는 stock_widget_info.xml의 updatePeriodMillis(30분, 안드로이드 최소값) —
 * 서버가 종목 시세를 30분마다 갱신하니 그와 맞음. 네트워크 요청은 메인 스레드에서 못 하니까
 * goAsync()로 방송 수신을 잠깐 붙잡고 별도 스레드에서 처리함(WorkManager 안 씀).
 */
class StockWidgetProvider : AppWidgetProvider() {

  companion object {
    /** 앱에서 종목/기기 id가 바뀌었을 때 호출 — 놓여 있는 위젯들을 바로 다시 그리게 함(없으면 아무것도 안 함). */
    fun requestUpdate(context: Context) {
      val ids = AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, StockWidgetProvider::class.java))
      if (ids.isEmpty()) return
      context.sendBroadcast(
          Intent(context, StockWidgetProvider::class.java)
              .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
              .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
      )
    }
  }

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

  /** 위젯 크기를 바꿨을 때(세로로 늘리면 더 많은 종목) — 새 크기에 맞게 바로 다시 그림. */
  override fun onAppWidgetOptionsChanged(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      newOptions: android.os.Bundle?,
  ) {
    super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    val pending = goAsync()
    thread {
      try {
        StockWidgetData.refresh(context, appWidgetManager, appWidgetId)
      } catch (e: Throwable) {
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
