package com.issuepop.issue_pop

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.CheckBox
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import android.widget.Toast
import kotlin.concurrent.thread

/**
 * 2026-10-17: 위젯을 홈 화면에 추가할 때(또는 위젯을 길게 눌러 설정할 때) 뜨는, 위젯에 보일
 * 종목을 고르는 화면. 앱에서 설정해둔 관심 종목 목록을 서버에서 받아 최대 3개까지 체크.
 * 화면은 XML 없이 코드로 그림 — 단순한 목록이라 리소스를 줄이고 실패 지점을 줄이려고.
 */
class StockWidgetConfigureActivity : Activity() {
  private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID
  private lateinit var list: LinearLayout
  private lateinit var status: TextView
  private lateinit var done: Button
  private val checks = mutableListOf<Pair<CheckBox, StockWidgetData.Watch>>()
  private var watches: List<StockWidgetData.Watch> = emptyList()

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    // 뒤로가기/취소로 나가면 위젯이 추가되지 않아야 해서 기본값은 CANCELED.
    setResult(RESULT_CANCELED)
    appWidgetId = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        ?: AppWidgetManager.INVALID_APPWIDGET_ID
    if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
      finish()
      return
    }

    val pad = (20 * resources.displayMetrics.density).toInt()
    val root = LinearLayout(this).apply {
      orientation = LinearLayout.VERTICAL
      setPadding(pad, pad, pad, pad)
    }
    root.addView(TextView(this).apply {
      text = "위젯에 보일 종목"
      textSize = 18f
      setTypeface(typeface, android.graphics.Typeface.BOLD)
    })
    root.addView(TextView(this).apply {
      text = "앱에 설정한 관심 종목 중 최대 ${StockWidgetData.MAX_PICKS}개를 고르세요."
      textSize = 13f
      setPadding(0, pad / 4, 0, pad / 2)
    })
    status = TextView(this).apply { textSize = 14f; text = "불러오는 중…" }
    root.addView(status)
    list = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
    root.addView(
        ScrollView(this).apply { addView(list) },
        LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, 0, 1f),
    )
    done = Button(this).apply {
      text = "완료"
      isEnabled = false
      setOnClickListener { finishWithPicks() }
    }
    root.addView(done, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT).apply {
      gravity = Gravity.END
    })
    setContentView(root)

    loadWatches()
  }

  private fun loadWatches() {
    val deviceId = try {
      StockWidgetData.deviceId(this)
    } catch (e: Throwable) {
      null
    }
    if (deviceId == null) {
      status.text = "앱을 한 번 열어서 관심 종목을 설정한 뒤 다시 추가해주세요."
      return
    }
    thread {
      val result = try {
        StockWidgetData.fetchWatches(deviceId)
      } catch (e: Throwable) {
        null
      }
      runOnUiThread {
        if (isFinishing) return@runOnUiThread
        if (result == null) {
          status.text = "종목을 불러오지 못했어요. 네트워크를 확인하고 다시 시도해주세요."
        } else if (result.isEmpty()) {
          status.text = "앱에 설정한 관심 종목이 없어요. 앱에서 종목을 추가해주세요."
        } else {
          showList(result)
        }
      }
    }
  }

  private fun showList(items: List<StockWidgetData.Watch>) {
    watches = items
    status.text = ""
    val saved = StockWidgetData.savedPicks(this, appWidgetId)
    // 처음 추가할 땐 앞에서부터 3개를 미리 체크, 다시 설정할 땐 지금 고른 걸 체크.
    val preChecked = if (saved.isNotEmpty()) saved else items.take(StockWidgetData.MAX_PICKS).map { it.ticker }
    items.forEach { w ->
      val box = CheckBox(this).apply {
        text = if (w.name.isNotBlank()) "${w.ticker}  ·  ${w.name}" else w.ticker
        textSize = 15f
        isChecked = w.ticker in preChecked
        setOnCheckedChangeListener { button, isChecked ->
          if (isChecked && checks.count { it.first.isChecked } > StockWidgetData.MAX_PICKS) {
            button.isChecked = false
            Toast.makeText(this@StockWidgetConfigureActivity, "최대 ${StockWidgetData.MAX_PICKS}개까지 고를 수 있어요", Toast.LENGTH_SHORT).show()
          }
        }
      }
      checks.add(box to w)
      list.addView(box)
    }
    done.isEnabled = true
  }

  private fun finishWithPicks() {
    try {
      val picks = checks.filter { it.first.isChecked }.map { it.second.ticker }
      StockWidgetData.savePicks(this, appWidgetId, picks)
      // 방금 받아둔 데이터로 바로 그림(한 번 더 네트워크를 타지 않음).
      StockWidgetData.render(this, AppWidgetManager.getInstance(this), appWidgetId, watches)
    } catch (e: Throwable) {
      // 그리기에 실패해도 위젯 추가 자체는 완료시킴 — 곧 정기 갱신이 다시 그림.
    }
    setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId))
    finish()
  }
}
