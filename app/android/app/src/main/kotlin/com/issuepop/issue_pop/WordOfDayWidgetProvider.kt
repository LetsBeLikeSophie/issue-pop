package com.issuepop.issue_pop

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
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
 * onUpdate()는 OS가 주기적으로(word_of_day_widget_info.xml의
 * updatePeriodMillis, 6시간마다) 불러주는데, 이때 그냥 저장된 값만
 * 다시 그리면 앱을 며칠 안 켠 사이 위젯이 계속 옛날 단어를 보여주게
 * 됨 — 그래서 HomeWidgetBackgroundIntent로 백그라운드 Dart 콜백도
 * 같이 깨워서 서버에서 최신 단어를 다시 받아오게 함(클릭이 아니라
 * 이 정기 갱신 시점에 직접 보냄). 위젯을 막 추가해서 색을 고른
 * 직후(WordOfDayWidgetConfigureActivity가 RESULT_OK로 끝난 직후)에도
 * OS가 이 onUpdate()를 한 번 자동으로 불러줘서 같은 경로로 첫 렌더링이
 * 일어남.
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

    HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("issuepop://refreshWordOfDay")).send()
  }
}
