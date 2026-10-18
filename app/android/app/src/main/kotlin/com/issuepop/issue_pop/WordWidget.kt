package com.issuepop.issue_pop

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONObject
import kotlin.concurrent.thread

/**
 * 2026-10-18: 홈 화면 "오늘의 단어" 위젯 — 서버(/word-of-day)가 하루에 하나 골라두는 단어 + 뜻풀이 + 예문.
 * 9월에 만들었다가(home_widget 패키지 + 이미지 렌더링) 크래시로 걷어냈던 위젯을, 관심 종목 위젯처럼 패키지/WorkManager 없이
 * 다시 만든 것. 단어 이미지를 미리 그리는 대신 TextView 배경에 형광펜 도형을 깔아서 이미지 렌더링이 필요 없음.
 */
object WordWidgetData {
  private const val PREFS = "word_widget"

  data class Word(val date: String, val word: String, val example: String, val definition: String)

  fun fetch(): Word {
    val o = JSONObject(StockWidgetData.httpGet("/word-of-day"))
    return Word(
        date = o.optString("date", ""),
        word = o.getString("word"),
        example = o.optString("example", ""),
        definition = if (o.isNull("definition")) "" else o.optString("definition", ""),
    )
  }

  private fun saveCache(context: Context, w: Word) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        .putString("cache", JSONObject().put("date", w.date).put("word", w.word).put("example", w.example).put("definition", w.definition).toString())
        .apply()
  }

  private fun loadCache(context: Context): Word? {
    val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("cache", null) ?: return null
    return try {
      val o = JSONObject(raw)
      Word(o.optString("date", ""), o.getString("word"), o.optString("example", ""), o.optString("definition", ""))
    } catch (e: Exception) {
      null
    }
  }

  /** "2026-10-18" → "10/18" */
  private fun dateLabel(date: String): String {
    val p = date.split("-")
    return if (p.size == 3) "${p[1].trimStart('0')}/${p[2].trimStart('0')}" else date
  }

  private fun buildViews(context: Context, word: Word?, message: String?, suffix: String = ""): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.word_widget)
    if (word == null) {
      views.setTextViewText(R.id.ww_header_time, "")
      views.setTextViewText(R.id.ww_message, message ?: "")
      views.setViewVisibility(R.id.ww_message, View.VISIBLE)
      views.setViewVisibility(R.id.ww_body, View.GONE)
    } else {
      views.setTextViewText(R.id.ww_header_time, dateLabel(word.date) + suffix)
      views.setViewVisibility(R.id.ww_message, View.GONE)
      views.setViewVisibility(R.id.ww_body, View.VISIBLE)
      views.setTextViewText(R.id.ww_word, word.word)
      // 뜻풀이가 아직 없으면(서버가 못 받아온 날) 예문만.
      views.setTextViewText(R.id.ww_definition, word.definition)
      views.setViewVisibility(R.id.ww_definition, if (word.definition.isEmpty()) View.GONE else View.VISIBLE)
      views.setTextViewText(R.id.ww_example, if (word.example.isEmpty()) "" else "“${word.example}”")
      views.setViewVisibility(R.id.ww_example, if (word.example.isEmpty()) View.GONE else View.VISIBLE)
    }
    val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    views.setOnClickPendingIntent(
        R.id.ww_root,
        PendingIntent.getActivity(context, 1, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
    )
    return views
  }

  fun refresh(context: Context, manager: AppWidgetManager, appWidgetId: Int) {
    WidgetRefresh.schedulePeriodic(context)
    try {
      val w = fetch()
      saveCache(context, w)
      manager.updateAppWidget(appWidgetId, buildViews(context, w, null))
    } catch (e: Exception) {
      WidgetRefresh.scheduleRetryWhenOnline(context)
      val cached = loadCache(context)
      if (cached != null) {
        manager.updateAppWidget(appWidgetId, buildViews(context, cached, null, " · 연결 안 됨"))
      } else {
        manager.updateAppWidget(appWidgetId, buildViews(context, null, "단어를 불러오지 못했어요"))
      }
    }
  }
}

class WordWidgetProvider : AppWidgetProvider() {

  override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
    val pending = goAsync()
    thread {
      try {
        appWidgetIds.forEach { id ->
          try {
            WordWidgetData.refresh(context, appWidgetManager, id)
          } catch (e: Throwable) {
            // 위젯 하나 실패가 다른 위젯/앱에 영향 주면 안 됨.
          }
        }
      } finally {
        pending.finish()
      }
    }
  }
}
