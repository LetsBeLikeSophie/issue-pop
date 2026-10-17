package com.issuepop.issue_pop

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * 2026-10-17: 홈 화면 "관심 종목" 위젯의 데이터/그리기 공용 코드.
 *
 * 9월에 만들었던 "오늘의 단어" 위젯은 home_widget 패키지가 끌고 온 WorkManager 초기화 때문에
 * 앱이 반복해서 크래시해서 통째로 걷어냈음(git 63ce2a3). 이번에는 같은 일이 안 생기게:
 *  - 외부 패키지/WorkManager를 전혀 안 씀 — 안드로이드 기본 AppWidgetProvider + 이 파일의
 *    HttpURLConnection만으로 서버(/devices/{id}/stocks, /fx/usd-krw)에서 직접 받아옴.
 *  - 앱 시작 코드(main.dart)와 분리 — 이 코드가 실패해도 앱 실행에는 영향 없음.
 *  - 모든 진입점(onUpdate/채널)은 try/catch로 감싸서 예외가 프로세스를 죽이지 않게 함.
 */
object StockWidgetData {
  const val API_BASE = "https://api.issue-pop.com"
  const val MAX_PICKS = 3

  private const val PREFS = "stock_widget"
  private const val FLUTTER_PREFS = "FlutterSharedPreferences"
  private const val FLUTTER_DEVICE_ID_KEY = "flutter.device_id_v1" // lib/device_registry.dart의 _idKey

  /** [quoteTime]: 이 시세가 거래된 시각(초, 서버가 Finnhub에서 받은 값) — 모르면 null. */
  data class Watch(val ticker: String, val name: String, val price: Double?, val percent: Double?, val quoteTime: Long?)

  /** 서버에서 한 번에 받아온 결과(종목들 + 환율). 환율을 못 받았으면 usdKrw는 null → 원화는 안 보여줌. */
  data class Snapshot(val watches: List<Watch>, val usdKrw: Double?)

  /**
   * 기기 id. 앱이 MethodChannel로 넘겨준 값(saveConfig)을 먼저 쓰고, 없으면 Flutter가 저장해둔
   * SharedPreferences에서 직접 읽어봄. 둘 다 없으면(앱을 한 번도 안 열었음) null.
   */
  fun deviceId(context: Context): Long? {
    val own = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    if (own.contains("device_id")) return own.getLong("device_id", 0L)
    val value = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE).all[FLUTTER_DEVICE_ID_KEY]
    return (value as? Number)?.toLong()
  }

  /** 앱(관심 종목 화면)이 정한 기기 id와 위젯에 보일 종목을 저장. tickers가 비면 기본(앞 3개). */
  fun saveConfig(context: Context, deviceId: Long?, tickers: List<String>) {
    val edit = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
    if (deviceId != null) edit.putLong("device_id", deviceId)
    edit.putString("picks", tickers.joinToString(","))
    edit.apply()
  }

  private fun httpGet(path: String): String {
    val conn = URL("$API_BASE$path").openConnection() as HttpURLConnection
    try {
      conn.connectTimeout = 4000
      conn.readTimeout = 5000
      conn.setRequestProperty("Accept", "application/json")
      if (conn.responseCode != 200) throw IllegalStateException("HTTP ${conn.responseCode}")
      return conn.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
    } finally {
      conn.disconnect()
    }
  }

  /** 이 기기에 설정된 관심 종목 전체(가격 포함). 실패하면 예외 — 호출하는 쪽이 잡음. */
  fun fetchWatches(deviceId: Long): List<Watch> {
    val arr = JSONArray(httpGet("/devices/$deviceId/stocks"))
    return (0 until arr.length()).map { i ->
      val o = arr.getJSONObject(i)
      val q = o.optJSONObject("quote")
      Watch(
          ticker = o.getString("ticker"),
          name = o.optString("name", ""),
          price = q?.takeIf { it.has("price") && !it.isNull("price") }?.getDouble("price"),
          percent = q?.takeIf { it.has("percent") && !it.isNull("percent") }?.getDouble("percent"),
          quoteTime = q?.takeIf { it.has("time") && !it.isNull("time") }?.getLong("time"),
      )
    }
  }

  /** USD→KRW 환율. 실패하면 null(원화 표시만 빠짐). */
  private fun fetchUsdKrw(): Double? =
      try {
        JSONObject(httpGet("/fx/usd-krw")).getDouble("usd_krw")
      } catch (e: Exception) {
        null
      }

  // --- 위젯에 보일 종목(앱의 관심 종목 화면에서 정함 — 위젯이 몇 개든 모두 같은 종목) ---

  fun savedPicks(context: Context): List<String> {
    val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("picks", null)
    return raw?.split(",")?.filter { it.isNotBlank() } ?: emptyList()
  }

  fun clear(context: Context, appWidgetIds: IntArray) {
    val edit = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
    appWidgetIds.forEach { edit.remove("cache_$it") }
    edit.apply()
  }

  // --- 마지막으로 그린 내용(네트워크가 안 될 때 대신 보여줌) ---

  private fun saveCache(context: Context, appWidgetId: Int, rows: List<Watch>, usdKrw: Double?) {
    val arr = JSONArray()
    rows.forEach {
      arr.put(
          JSONObject()
              .put("ticker", it.ticker)
              .put("name", it.name)
              .put("price", it.price ?: JSONObject.NULL)
              .put("percent", it.percent ?: JSONObject.NULL)
              .put("time", it.quoteTime ?: JSONObject.NULL)
      )
    }
    context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        .putString("cache_$appWidgetId", JSONObject().put("usdKrw", usdKrw ?: JSONObject.NULL).put("rows", arr).toString())
        .apply()
  }

  private fun loadCache(context: Context, appWidgetId: Int): Pair<List<Watch>, Double?>? {
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
            if (r.isNull("time")) null else r.getLong("time"),
        )
      }
      rows to (if (o.isNull("usdKrw")) null else o.getDouble("usdKrw"))
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

  private class RowIds(val row: Int, val ticker: Int, val name: Int, val usd: Int, val krw: Int, val pct: Int)

  private val rowIds = listOf(
      RowIds(R.id.sw_r1, R.id.sw_r1_ticker, R.id.sw_r1_name, R.id.sw_r1_usd, R.id.sw_r1_krw, R.id.sw_r1_pct),
      RowIds(R.id.sw_r2, R.id.sw_r2_ticker, R.id.sw_r2_name, R.id.sw_r2_usd, R.id.sw_r2_krw, R.id.sw_r2_pct),
      RowIds(R.id.sw_r3, R.id.sw_r3_ticker, R.id.sw_r3_name, R.id.sw_r3_usd, R.id.sw_r3_krw, R.id.sw_r3_pct),
  )

  /**
   * 서버가 내려주는 이름은 "애플 Apple" 모양(한글 + 영어). 위젯은 한글이 있으면 한글만 큰 글자로 보여주고(영어는 티커 칩이
   * 이미 알려줌), 한글이 없는 종목은 영어 이름 그대로. 마지막 한글 단어까지를 한글 이름으로 봄 —
   * "S&P 글로벌 S&P Global" → "S&P 글로벌", "RTX(레이시온) RTX Raytheon" → "RTX(레이시온)".
   */
  fun shortName(name: String): String {
    val tokens = name.split(" ")
    val lastKo = tokens.indexOfLast { t -> t.any { it in '가'..'힣' } }
    return if (lastKo < 0) name else tokens.take(lastKo + 1).joinToString(" ")
  }

  private fun formatUsd(p: Double?) = if (p == null) "-" else String.format(Locale.US, "$%,.2f", p)

  private fun formatKrw(usd: Double?, rate: Double?): String =
      if (usd == null || rate == null) "" else String.format(Locale.US, "₩%,d", Math.round(usd * rate))

  private fun formatPercent(p: Double?) = if (p == null) "-" else String.format(Locale.US, "%s%.1f%%", if (p >= 0) "+" else "", p)

  /** 이 시세가 언제 데이터인지(서울 시간) — "시세 10/17 05:00". 보여줄 종목들 중 가장 최근 값. */
  private fun dataTimeLabel(rows: List<Watch>): String {
    val t = rows.mapNotNull { it.quoteTime }.maxOrNull() ?: return ""
    val fmt = SimpleDateFormat("M/d HH:mm", Locale.KOREA).apply { timeZone = TimeZone.getTimeZone("Asia/Seoul") }
    return "시세 " + fmt.format(Date(t * 1000))
  }

  private fun buildViews(context: Context, rows: List<Watch>, usdKrw: Double?, message: String?, timeSuffix: String = ""): RemoteViews {
    val views = RemoteViews(context.packageName, R.layout.stock_widget)
    views.setTextViewText(R.id.sw_header_time, dataTimeLabel(rows) + timeSuffix)
    if (message != null) {
      views.setTextViewText(R.id.sw_message, message)
      views.setViewVisibility(R.id.sw_message, View.VISIBLE)
    } else {
      views.setViewVisibility(R.id.sw_message, View.GONE)
    }
    rowIds.forEachIndexed { i, ids ->
      val w = rows.getOrNull(i)
      if (w == null) {
        views.setViewVisibility(ids.row, View.GONE)
        return@forEachIndexed
      }
      views.setViewVisibility(ids.row, View.VISIBLE)
      views.setTextViewText(ids.ticker, w.ticker)
      views.setTextViewText(ids.name, shortName(w.name))
      views.setTextViewText(ids.usd, formatUsd(w.price))
      val krw = formatKrw(w.price, usdKrw)
      views.setTextViewText(ids.krw, krw)
      views.setViewVisibility(ids.krw, if (krw.isEmpty()) View.GONE else View.VISIBLE)
      views.setTextViewText(ids.pct, formatPercent(w.percent))
      val p = w.percent
      when {
        p == null -> {
          views.setTextColor(ids.pct, context.getColor(R.color.sw_ink_soft))
          views.setInt(ids.pct, "setBackgroundResource", R.drawable.stock_widget_pill_flat)
        }
        p >= 0 -> {
          views.setTextColor(ids.pct, context.getColor(R.color.sw_up))
          views.setInt(ids.pct, "setBackgroundResource", R.drawable.stock_widget_pill_up)
        }
        else -> {
          views.setTextColor(ids.pct, context.getColor(R.color.sw_down))
          views.setInt(ids.pct, "setBackgroundResource", R.drawable.stock_widget_pill_down)
        }
      }
    }
    // 위젯 아무 데나 누르면 앱을 열고 "관심 종목" 화면으로 이동(MainActivity가 extra를 Dart에 전달).
    val launch = Intent(context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        .putExtra(MainActivity.EXTRA_ROUTE, "stocks")
    views.setOnClickPendingIntent(
        R.id.sw_root,
        PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT),
    )
    return views
  }

  /** 새로 받은 결과로 이 위젯을 그리고 마지막 내용을 저장. */
  private fun render(context: Context, manager: AppWidgetManager, appWidgetId: Int, snap: Snapshot) {
    val rows = pickRows(snap.watches, savedPicks(context))
    saveCache(context, appWidgetId, rows, snap.usdKrw)
    val message = if (rows.isEmpty()) "앱에서 관심 종목을 먼저 추가해주세요" else null
    manager.updateAppWidget(appWidgetId, buildViews(context, rows, snap.usdKrw, message))
  }

  /** 이 위젯 하나를 서버에서 새로 받아 갱신. 실패하면 마지막 내용(없으면 안내 문구)을 그림. */
  fun refresh(context: Context, manager: AppWidgetManager, appWidgetId: Int) {
    val deviceId = deviceId(context)
    if (deviceId == null) {
      manager.updateAppWidget(appWidgetId, buildViews(context, emptyList(), null, "앱을 한 번 열면 종목이 나와요"))
      return
    }
    try {
      val watches = fetchWatches(deviceId)
      // 환율은 못 받아도 달러 시세는 보여줌(이전에 받아둔 환율이 있으면 그걸로).
      val rate = fetchUsdKrw() ?: loadCache(context, appWidgetId)?.second
      render(context, manager, appWidgetId, Snapshot(watches, rate))
    } catch (e: Exception) {
      val cached = loadCache(context, appWidgetId)
      if (cached != null) {
        manager.updateAppWidget(appWidgetId, buildViews(context, cached.first, cached.second, null, " · 연결 안 됨"))
      } else {
        manager.updateAppWidget(appWidgetId, buildViews(context, emptyList(), null, "종목을 불러오지 못했어요"))
      }
    }
  }
}
