package com.issuepop.issue_pop

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/**
 * 2026-09-27: 홈 화면 "오늘의 단어" 위젯.
 *
 * 위젯은 플러터 엔진 밖, 앱 프로세스와 별개로 OS가 직접 그리는 거라
 * 순수 네이티브(RemoteViews)로 그려야 함 — 단어에 형광펜 효과를 주는
 * 부분(_HighlightedWord)만은 RemoteViews로 표현이 안 돼서 Dart 쪽
 * (word_of_day_widget.dart)이 미리 PNG로 렌더링해두고, 이 클래스는
 * 그 PNG를 ImageView에 얹고 뜻풀이 텍스트를 채워주는 역할만 함.
 *
 * 2026-09-27(2차): onUpdate()마다 HomeWidgetBackgroundIntent로 백그라운드
 * Dart 콜백을 깨워서 최신 단어를 다시 받아오게 했었는데, 그 경로가
 * 내부적으로 WorkManager를 쓰고(HomeWidgetBackgroundWorker), 앱이 아예
 * 안 켜지던 크래시를 고치려고 WorkManager 기본 자동 초기화를 꺼놓은
 * 상태라 이 호출이 항상 예외(WorkManager is not initialized)를 던져서
 * 앱 프로세스가 죽는 새 크래시로 이어짐(위젯을 추가/정기 갱신할 때마다
 * 반복 재현 — 위젯 지우면 이 경로 자체가 안 불려서 멀쩡해 보였던 것).
 * 그래서 이 트리거는 완전히 제거함 — 위젯은 이제 마지막으로 저장된
 * 값만 그리고(항상 안전), 실제 최신화는 앱을 열 때(main.dart의
 * updateWordOfDayWidget)만 일어남. "며칠 앱을 안 열면 위젯이 옛날
 * 단어를 보여줄 수 있다"는 트레이드오프를 감수하는 대신, 크래시를
 * 완전히 없앰 — WorkManager를 제대로(커스텀 Application으로) 초기화
 * 하는 방법은 나중에 안정화되면 다시 볼 수 있음.
 */
class WordOfDayWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    appWidgetIds.forEach { widgetId ->
      val views = RemoteViews(context.packageName, R.layout.word_of_day_widget).apply {
        val imagePath = widgetData.getString("word_of_day_image", null)
        if (imagePath != null) {
          val bitmap = BitmapFactory.decodeFile(imagePath)
          if (bitmap != null) {
            setImageViewBitmap(R.id.widget_word_image, bitmap)
            setViewVisibility(R.id.widget_word_image, View.VISIBLE)
          }
        }

        val definition = widgetData.getString("word_of_day_definition", null)
        setTextViewText(R.id.widget_definition, definition ?: "오늘의 단어를 아직 못 받아왔어요")

        val launchIntent = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
        setOnClickPendingIntent(R.id.widget_root, launchIntent)
      }
      appWidgetManager.updateAppWidget(widgetId, views)
    }
  }
}
