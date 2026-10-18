package com.issuepop.issue_pop

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlin.concurrent.thread

/**
 * 2026-10-18: 홈 화면 "오늘의 이슈" 위젯 — 오늘 가장 많이 보도된 이슈를 기사 수 순위로(앱 홈 기본 정렬과 같음) 최대 5개.
 * 관심 종목 위젯(StockWidget*.kt)과 같은 방식: 외부 패키지/WorkManager 없이 AppWidgetProvider + HttpURLConnection만 쓰고,
 * 모든 진입점은 try/catch, 앱 시작 코드와 분리. 줄을 누르면 앱에서 그 이슈를 엶(MainActivity가 extra를 Dart에 전달).
 */
object IssueWidgetData {
  private const val PREFS = "issue_widget"
  private const val MAX_ROWS = 5

  data class Issue(
      val id: String,
      val keyword: String,
      val sub: String,
      val title: String,
      val articleCount: Int,
  )

  data class Snapshot(val issues: List<Issue>, val atSeconds: Long)

  /** 서버 /trending(대표 40개)을 받아 기사 수 순으로 상위만. 실패하면 예외 — 호출하는 쪽이 잡음. */
  fun fetch(): Snapshot {
    val arr = JSONArray(StockWidgetData.httpGet("/trending?limit=40"))
    val all = (0 until arr.length()).map { i ->
      val o = arr.getJSONObject(i)
      val kws = o.optJSONArray("keywords")
      Triple(
          Issue(
              id = o.getString("id"),
              keyword = o.getString("keyword"),
              sub = if (kws != null && kws.length() > 1) kws.getString(1) else "",
              title = o.optString("representative_title", ""),
              articleCount = o.optInt("article_count", 0),
          ),
          o.optInt("article_count", 0),
          o.optInt("outlet_count", 0),
      )
    }
    val top = all
        .sortedWith(compareByDescending<Triple<Issue, Int, Int>> { it.second }.thenByDescending { it.third })
        .take(MAX_ROWS)
        .map { it.first }
    // 이 이슈 목록이 언제 만들어진 건지(서버가 30분마다 갱신) — /health의 last_refresh. 못 받으면 지금.
    val at = try {
      JSONObject(StockWidgetData.httpGet("/health")).getDouble("last_refresh").toLong()
    } catch (e: Exception) {
      System.currentTimeMillis() / 1000
    }
    return Snapshot(top, at)
  }

  private fun saveCache(context: Context, snap: Snapshot) {
    val arr = JSONArray()
    snap.issues.forEach {
      arr.put(
          JSONObject()
              .put("id", it.id).put("keyword", it.keyword).put("sub", it.sub)
              .put("title", it.title).put("count", it.articleCount)
      )
    }
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        .putString("cache", JSONObject().put("at", snap.atSeconds).put("issues", arr).toString()).apply()
  }

  private fun loadCache(context: Context): Snapshot? {
    val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("cache", null) ?: return null
    return try {
      val o = JSONObject(raw)
      val arr = o.getJSONArray("issues")
      Snapshot(
          (0 until arr.length()).map {
            val r = arr.getJSONObject(it)
            Issue(r.getString("id"), r.getString("keyword"), r.optString("sub", ""), r.optString("title", ""), r.optInt("count", 0))
          },
          o.getLong("at"),
      )
    } catch (e: Exception) {
      null
    }
  }

  private class RowIds(val row: Int, val rank: Int, val kw: Int, val sub: Int, val title: Int, val count: Int)

  private val rowIds = listOf(
      RowIds(R.id.iw_r1, R.id.iw_r1_rank, R.id.iw_r1_kw, R.id.iw_r1_sub, R.id.iw_r1_title, R.id.iw_r1_count),
      RowIds(R.id.iw_r2, R.id.iw_r2_rank, R.id.iw_r2_kw, R.id.iw_r2_sub, R.id.iw_r2_title, R.id.iw_r2_count),
      RowIds(R.id.iw_r3, R.id.iw_r3_rank, R.id.iw_r3_kw, R.id.iw_r3_sub, R.id.iw_r3_title, R.id.iw_r3_count),
      RowIds(R.id.iw_r4, R.id.iw_r4_rank, R.id.iw_r4_kw, R.id.iw_r4_sub, R.id.iw_r4_title, R.id.iw_r4_count),
      RowIds(R.id.iw_r5, R.id.iw_r5_rank, R.id.iw_r5_kw, R.id.iw_r5_sub, R.id.iw_r5_title, R.id.iw_r5_count),
  )
  private val dividerIds = listOf(R.id.iw_d2, R.id.iw_d3, R.id.iw_d4, R.id.iw_d5)

  /** 위젯 높이(dp)에 들어가는 줄 수 — 머리글+여백 약 46dp, 줄(+구분선) 약 38dp, 8dp 여유. 모르면 3. */
  fun visibleRows(manager: AppWidgetManager, appWidgetId: Int): Int =
      try {
        val h = manager.getAppWidgetOptions(appWidgetId).getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)
        if (h <= 0) 3 else ((h - 46 + 8) / 38).coerceIn(1, MAX_ROWS)
      } catch (e: Exception) {
        3
      }

  private fun timeLabel(atSeconds: Long): String {
    val fmt = SimpleDateFormat("M/d HH:mm", Locale.KOREA).apply { timeZone = TimeZone.getTimeZone("Asia/Seoul") }
    return fmt.format(Date(atSeconds * 1000)) + " 기준"
  }

  private fun openIntent(context: Context, requestCode: Int, route: String?): PendingIntent {
    val intent = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    if (route != null) intent.putExtra(MainActivity.EXTRA_ROUTE, route)
    return PendingIntent.getActivity(context, requestCode, intent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
  }

  private fun buildViews(
      context: Context,
      appWidgetId: Int,
      issues: List<Issue>,
      message: String?,
      timeText: String,
      visibleRows: Int,
  ): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.issue_widget)
    views.setTextViewText(R.id.iw_header_time, timeText)
    if (message != null) {
      views.setTextViewText(R.id.iw_message, message)
      views.setViewVisibility(R.id.iw_message, View.VISIBLE)
    } else {
      views.setViewVisibility(R.id.iw_message, View.GONE)
    }
    val shown = issues.size.coerceAtMost(visibleRows)
    dividerIds.forEachIndexed { i, id -> views.setViewVisibility(id, if (i + 1 < shown) View.VISIBLE else View.GONE) }
    rowIds.forEachIndexed { i, ids ->
      val issue = if (i < visibleRows) issues.getOrNull(i) else null
      if (issue == null) {
        views.setViewVisibility(ids.row, View.GONE)
        return@forEachIndexed
      }
      views.setViewVisibility(ids.row, View.VISIBLE)
      views.setTextViewText(ids.rank, (i + 1).toString())
      views.setTextViewText(ids.kw, issue.keyword)
      views.setTextViewText(ids.sub, if (issue.sub.isEmpty()) "" else "· ${issue.sub}")
      views.setTextViewText(ids.title, issue.title)
      views.setTextViewText(ids.count, "${issue.articleCount}건")
      // 줄을 누르면 그 이슈를 엶(이슈 id는 재묶음으로 바뀔 수 있어서 키워드도 같이 — 앱이 못 찾으면 키워드로 찾음).
      views.setOnClickPendingIntent(ids.row, openIntent(context, appWidgetId * 10 + i + 1, "issue:${issue.id}|${issue.keyword}"))
    }
    views.setOnClickPendingIntent(R.id.iw_root, openIntent(context, appWidgetId * 10, null))
    return views
  }

  fun refresh(context: Context, manager: AppWidgetManager, appWidgetId: Int) {
    WidgetRefresh.schedulePeriodic(context)
    val rows = visibleRows(manager, appWidgetId)
    try {
      val snap = fetch()
      saveCache(context, snap)
      val message = if (snap.issues.isEmpty()) "지금 보여줄 이슈가 없어요" else null
      manager.updateAppWidget(appWidgetId, buildViews(context, appWidgetId, snap.issues, message, timeLabel(snap.atSeconds), rows))
    } catch (e: Exception) {
      WidgetRefresh.scheduleRetryWhenOnline(context)
      val cached = loadCache(context)
      if (cached != null) {
        manager.updateAppWidget(
            appWidgetId,
            buildViews(context, appWidgetId, cached.issues, null, timeLabel(cached.atSeconds) + " · 연결 안 됨", rows),
        )
      } else {
        manager.updateAppWidget(appWidgetId, buildViews(context, appWidgetId, emptyList(), "이슈를 불러오지 못했어요", "", rows))
      }
    }
  }
}

class IssueWidgetProvider : AppWidgetProvider() {

  override fun onUpdate(context: Context, appWidgetManager: AppWidgetManager, appWidgetIds: IntArray) {
    val pending = goAsync()
    thread {
      try {
        appWidgetIds.forEach { id ->
          try {
            IssueWidgetData.refresh(context, appWidgetManager, id)
          } catch (e: Throwable) {
            // 위젯 하나 실패가 다른 위젯/앱에 영향 주면 안 됨.
          }
        }
      } finally {
        pending.finish()
      }
    }
  }

  /** 크기를 바꿨을 때(세로로 늘리면 이슈가 더 보임) 새 크기에 맞게 바로 다시 그림. */
  override fun onAppWidgetOptionsChanged(context: Context, appWidgetManager: AppWidgetManager, appWidgetId: Int, newOptions: Bundle?) {
    super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    val pending = goAsync()
    thread {
      try {
        IssueWidgetData.refresh(context, appWidgetManager, appWidgetId)
      } catch (e: Throwable) {
      } finally {
        pending.finish()
      }
    }
  }
}
