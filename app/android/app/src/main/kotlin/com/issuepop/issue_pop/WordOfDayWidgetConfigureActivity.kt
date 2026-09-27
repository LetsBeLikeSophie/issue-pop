package com.issuepop.issue_pop

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView

/**
 * 2026-09-27: 위젯을 홈 화면에 추가할 때 한 번 뜨는 설정 화면 — 형광펜
 * 색을 3가지 중 골라서 위젯이 앱 테마와 어울리게 함. 한 번 쓰고 마는
 * 가벼운 화면이라 플러터 엔진을 새로 띄우지 않고 순수 네이티브 뷰로
 * 직접 그림(레이아웃 XML도 안 만들고 코드로 바로 구성 — 원 3개 고르는
 * 정도라 그게 더 간단함).
 *
 * android:configure로 지정된 액티비티는 RESULT_OK로 끝나야 위젯이
 * 실제로 홈 화면에 배치되고, 그 직후 OS가 WordOfDayWidgetProvider의
 * onUpdate()를 자동으로 한 번 불러줌 — 거기서 방금 고른 색 인덱스를
 * 읽어 Dart 쪽에 렌더링을 맡기는 흐름으로 이어짐.
 */
class WordOfDayWidgetConfigureActivity : Activity() {
  private var appWidgetId = AppWidgetManager.INVALID_APPWIDGET_ID

  companion object {
    private val COLOR_OPTIONS = listOf("옐로우" to "#F4C94E", "민트" to "#A8D8B9", "라벤더" to "#C7D2F0")
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    super.onCreate(savedInstanceState)
    setResult(RESULT_CANCELED)

    appWidgetId =
        intent?.extras?.getInt(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID

    if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
      finish()
      return
    }

    setContentView(buildLayout())
  }

  private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

  private fun buildLayout(): View {
    val root =
        LinearLayout(this).apply {
          orientation = LinearLayout.VERTICAL
          setPadding(dp(24), dp(48), dp(24), dp(24))
          setBackgroundColor(Color.WHITE)
        }

    root.addView(
        TextView(this).apply {
          text = "오늘의 단어 위젯 — 형광펜 색을 골라주세요"
          textSize = 17f
          setTextColor(Color.parseColor("#14161C"))
          setPadding(0, 0, 0, dp(32))
        },
    )

    val row = LinearLayout(this).apply { orientation = LinearLayout.HORIZONTAL; gravity = Gravity.CENTER }
    COLOR_OPTIONS.forEachIndexed { index, (label, hex) ->
      val column =
          LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setPadding(dp(20), 0, dp(20), 0)
          }
      column.addView(
          View(this).apply {
            layoutParams = LinearLayout.LayoutParams(dp(56), dp(56))
            background =
                GradientDrawable().apply {
                  shape = GradientDrawable.OVAL
                  setColor(Color.parseColor(hex))
                }
            setOnClickListener { selectColor(index) }
          },
      )
      column.addView(
          TextView(this).apply {
            text = label
            textSize = 13f
            setTextColor(Color.parseColor("#4B4D55"))
            gravity = Gravity.CENTER
            setPadding(0, dp(8), 0, 0)
          },
      )
      row.addView(column)
    }
    root.addView(row)
    return root
  }

  private fun selectColor(index: Int) {
    getSharedPreferences("HomeWidgetPreferences", Context.MODE_PRIVATE)
        .edit()
        .putInt("word_of_day_highlight_color_index", index)
        .apply()

    val resultValue = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
    setResult(RESULT_OK, resultValue)
    finish()
  }
}
