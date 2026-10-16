package com.issuepop.issue_pop

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 2026-10-17: 홈 화면 "관심 종목" 위젯의 데이터/그리기 공용 코드.
 *
 * 9월에 만들었던 "오늘의 단어" 위젯은 home_widget 패키지가 끌고 온 WorkManager 초기화 때문에
 * 앱이 반복해서 크래시해서 통째로 걷어냈음(git 63ce2a3). 이번에는 같은 일이 안 생기게:
 *  - 외부 패키지/WorkManager를 전혀 안 씀 — 안드로이드 기본 AppWidgetProvider + 이 파일의
 *    HttpURLConnection만으로 서버(/devices/{id}/stocks)에서 직접 받아옴.
 *  - 앱 시작 코드(main.dart/MainActivity)와 완전히 분리 — 이 코드가 실패해도 앱 실행에는 영향 없음.
 *  - 모든 진입점(onUpdate/설정 화면)은 try/catch로 감싸서 예외가 프로세스를 죽이지 않게 함.
 */
object StockWidgetData {
  const val API_BASE = "https://api.issue-pop.com"
  const val MAX_PICKS = 3

  private const val PREFS = "stock_widget"
  private const val FLUTTER_PREFS = "FlutterSharedPreferences"
  private const val FLUTTER_DEVICE_ID_KEY = "flutter.device_id_v1" // lib/device_registry.dart의 _idKey

  data class Watch(val ticker: String, val name: String, val price: Double?, val percent: Double?)

  /** 앱이 등록해둔 기기 id. 앱을 한 번도 안 열었으면 null. */
  fun deviceId(context: Context): Long? {
    val value = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE).all[FLUTTER_DEVICE_ID_KEY]
    return (value as? Number)?.toLong()
  }

  /** 이 기기에 설정된 관심 종목 전체(가격 포함). 실패하면 예외 — 호출하는 쪽이 잡음. */
  fun fetchWatches(deviceId: Long): List<Watch> {
    val conn = URL("$API_BASE/devices/$deviceId/stocks").openConnection() as HttpURLConnection
    try {
      conn.connectTimeout = 4000
      conn.readTimeout = 5000
      conn.setRequestProperty("Accept", "application/json")
      if (conn.responseCode != 200) throw IllegalStateException("HTTP ${conn.responseCode}")
      val body = conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
      val arr = JSONArray(body)
      return (0 until arr.length()).map { i ->
        val o = arr.getJSONObject(i)
        val q = o.optJSONObject("quote")
        Watch(
            ticker = o.getString("ticker"),
            name = o.optString("name", ""),
            price = q?.takeIf { it.has("price") && !it.isNull("price") }?.getDouble("price"),
            percent = q?.takeIf { it.has("percent") && !it.isNull("percent") }?.getDouble("percent"),
        )
      }
    } finally {
      conn.disconnect()
    }
  }

  // --- 위젯별로 고른 종목(위젯 인스턴스마다 따로) ---

  fun savedPicks(context: Context, appWidgetId: Int): List<String> {
    val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("picks_$appWidgetId", null)
    return raw?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
  }

  fun savePicks(context: Context, appWidgetId: Int, tickers: List<String>) {
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        .putString("picks_$appWidgetId", tickers.joinToString(","))
        .apply()
  }

  fun clear(context: Context, appWidgetIds: IntArray) {
    val edit = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
    appWidgetIds.forEach {
      edit.remove("picks_$it")
      edit.remove("cache_$it")
    }
    edit.apply()
  }

  // --- 마지막으로 그린 내용(네트워크가 안 될 때 대신 보여줌) ---

  private fun saveCache(context: Context, appWidgetId: Int, rows: List<Watch>, at: Long) {
    val arr = JSONArray()
    rows.forEach {
      arr.put(
          JSONObject()
              .put("ticker", it.ticker)
              .put("name", it.name)
              .put("price", it.price ?: JSONObject.NULL)
              .put("percent", it.percent ?: JSONObject.NULL)
      )
    }
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        .putString("cache_$appWidgetId", JSONObject().put("at", at).put("rows", arr).toString())
        .apply()
  }

  private fun loadCache(context: Context, appWidgetId: Int): Pair<List<Watch>, Long>? {
    val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("cache_$appWidgetId", null) ?: return null
    return try {
      val o = JSONObject(raw)
      val arr = o.getJSONArray("rows")
      val rows = (0 until arr.length()).map {
        val r = arr.getJSONObject(it)
        Watch(
            r.getString("ticker"),
            r.optString("name", ""),
            if (r.isNull("price")) null else r.getDouble("price"),
            if (r.isNull("percent")) null else r.getDouble("percent"),
        )
      }
      rows to o.getLong("at")
    } catch (e: Exception) {
      null
    }
  }

  // --- 그리기 ---

  /** 고른 종목(없거나 지워졌으면 앞에서부터 MAX_PICKS개)을 watches에서 골라냄. */
  fun pickRows(watches: List<Watch>, picks: List<String>): List<Watch> {
    val chosen = picks.mapNotNull { t -> watches.firstOrNull { it.ticker == t } }
    return (if (chosen.isNotEmpty()) chosen else watches).take(MAX_PICKS)
  }

  private val rowIds = listOf(
      intArrayOf(R.id.sw_r1, R.id.sw_r1_ticker, R.id.sw_r1_name, R.id.sw_r1_price, R.id.sw_r1_pct),
      intArrayOf(R.id.sw_r2, R.id.sw_r2_ticker, R.id.sw_r2_name, R.id.sw_r2_price, R.id.sw_r2_pct),
      intArrayOf(R.id.sw_r3, R.id.sw_r3_ticker, R.id.sw_r3_name, R.id.sw_r3_price, R.id.sw_r3_pct),
  )

  private fun formatPrice(p: Double?) = if (p == null) "-" else String.format(Locale.US, "$%,.2f", p)

  private fun formatPercent(p: Double?) = if (p == null) "-" else String.format(Locale.US, "%s%.1f%%", if (p >= 0) "+" else "", p)

  private fun buildViews(context: Context, rows: List<Watch>, message: String?, time: String?): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.stock_widget)
    views.setTextViewText(R.id.sw_header_time, time ?: "")
    if (message != null) {
      views.setTextViewText(R.id.sw_message, message)
      views.setViewVisibility(R.id.sw_message, android.view.View.VISIBLE)
    } else {
      views.setViewVisibility(R.id.sw_message, android.view.View.GONE)
    }
    rowIds.forEachIndexed { i, ids ->
      val w = rows.getOrNull(i)
      if (w == null) {
        views.setViewVisibility(ids[0], android.view.View.GONE)
        return@forEachIndexed
      }
      views.setViewVisibility(ids[0], android.view.View.VISIBLE)
      views.setTextViewText(ids[1], w.ticker)
      views.setTextViewText(ids[2], w.name)
      views.setTextViewText(ids[3], formatPrice(w.price))
      views.setTextViewText(ids[4], formatPercent(w.percent))
      val color = when {
        w.percent == null -> context.getColor(R.color.sw_ink_soft)
        w.percent >= 0 -> context.getColor(R.color.sw_up)
        else -> context.getColor(R.color.sw_down)
      }
      views.setTextColor(ids[4], color)
    }
    // 위젯 아무 데나 누르면 앱 열기.
    val launch = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
    views.setOnClickPendingIntent(
        R.id.sw_root,
        PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
    )
    return views
  }

  /** 새로 받은 watches로 이 위젯을 그리고 마지막 내용을 저장. */
  fun render(context: Context, manager: AppWidgetManager, appWidgetId: Int, watches: List<Watch>) {
    val rows = pickRows(watches, savedPicks(context, appWidgetId))
    val now = System.currentTimeMillis()
    saveCache(context, appWidgetId, rows, now)
    val message = if (rows.isEmpty()) "앱에서 관심 종목을 먼저 추가해주세요" else null
    manager.updateAppWidget(appWidgetId, buildViews(context, rows, message, timeLabel(now)))
  }

  /** 이 위젯 하나를 서버에서 새로 받아 갱신. 실패하면 마지막 내용(없으면 안내 문구)을 그림. */
  fun refresh(context: Context, manager: AppWidgetManager, appWidgetId: Int) {
    val deviceId = deviceId(context)
    if (deviceId == null) {
      manager.updateAppWidget(appWidgetId, buildViews(context, emptyList(), "앱을 한 번 열면 종목이 나와요", null))
      return
    }
    try {
      render(context, manager, appWidgetId, fetchWatches(deviceId))
    } catch (e: Exception) {
      val cached = loadCache(context, appWidgetId)
      if (cached != null) {
        manager.updateAppWidget(appWidgetId, buildViews(context, cached.first, null, timeLabel(cached.second) + " (이전)"))
      } else {
        manager.updateAppWidget(appWidgetId, buildViews(context, emptyList(), "종목을 불러오지 못했어요", null))
      }
    }
  }

  private fun timeLabel(at: Long) = SimpleDateFormat("HH:mm", Locale.KOREA).format(Date(at))
}
