package com.issuepop.issue_pop

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import kotlin.concurrent.thread

/**
 * 2026-10-18: 위젯 갱신을 안드로이드의 updatePeriodMillis(30분)에만 맡기면 삼성 같은 기기에서 몇 시간씩 안 도는 문제가 실제로
 * 확인됨(서버 접속 기록: 갱신 요청이 01:33 → 03:54 → 09:45 식으로 드문드문, 그 사이 오프라인이었던 위젯은 "연결 안 됨"으로
 * 몇 시간 그대로). 그래서 세 가지를 더함:
 *  1. 앱을 켜거나 다시 돌아올 때 모든 위젯을 바로 갱신(requestAll — Dart의 refreshWidgets 채널).
 *  2. JobScheduler 주기 작업(30분 간격, 시스템이 절전 상태에 맞춰 실행) — updatePeriodMillis보다 덜 밀림. WorkManager가 아니라
 *     프레임워크 JobScheduler를 직접 씀(9월 위젯 크래시의 원인이 WorkManager 초기화였음).
 *  3. 갱신이 네트워크 때문에 실패하면 "네트워크가 다시 잡힐 때" 한 번 더 도는 일회성 작업(scheduleRetryWhenOnline).
 * 삼성 "절전 앱" 등으로 시스템이 아예 막는 경우는 앱이 어쩔 수 없음(배터리 "제한 없음"으로 바꿔야 함).
 */
object WidgetRefresh {
  private const val JOB_PERIODIC = 4101
  private const val JOB_RETRY = 4102
  private const val INTERVAL_MS = 30 * 60 * 1000L

  private val providers = listOf(
      StockWidgetProvider::class.java,
      IssueWidgetProvider::class.java,
      WordWidgetProvider::class.java,
  )

  /** 놓여 있는 모든 위젯(관심 종목/오늘의 이슈/오늘의 단어)을 바로 다시 그리게 함. 없으면 아무것도 안 함. */
  fun requestAll(context: Context) {
    val manager = AppWidgetManager.getInstance(context)
    providers.forEach { cls ->
      val ids = manager.getAppWidgetIds(ComponentName(context, cls))
      if (ids.isNotEmpty()) {
        context.sendBroadcast(
            Intent(context, cls)
                .setAction(AppWidgetManager.ACTION_APPWIDGET_UPDATE)
                .putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        )
      }
    }
  }

  /** 모든 위젯 인스턴스를 지금 이 스레드에서 갱신(JobService가 호출 — 반드시 백그라운드 스레드에서). */
  fun refreshAllNow(context: Context) {
    val manager = AppWidgetManager.getInstance(context)
    for (id in manager.getAppWidgetIds(ComponentName(context, StockWidgetProvider::class.java))) {
      try { StockWidgetData.refresh(context, manager, id) } catch (e: Throwable) {}
    }
    for (id in manager.getAppWidgetIds(ComponentName(context, IssueWidgetProvider::class.java))) {
      try { IssueWidgetData.refresh(context, manager, id) } catch (e: Throwable) {}
    }
    for (id in manager.getAppWidgetIds(ComponentName(context, WordWidgetProvider::class.java))) {
      try { WordWidgetData.refresh(context, manager, id) } catch (e: Throwable) {}
    }
  }

  /** 30분 주기 작업을 걸어둠(이미 있으면 그대로). 위젯이 갱신될 때마다 불러서 재부팅 뒤에도 곧 다시 걸리게 함. */
  fun schedulePeriodic(context: Context) {
    try {
      val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
      if (scheduler.getPendingJob(JOB_PERIODIC) != null) return
      scheduler.schedule(
          JobInfo.Builder(JOB_PERIODIC, ComponentName(context, WidgetRefreshJobService::class.java))
              .setPeriodic(INTERVAL_MS)
              .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
              .build()
      )
    } catch (e: Throwable) {
      // 작업 예약이 안 돼도 위젯은 기존 방식(updatePeriodMillis)으로 계속 동작.
    }
  }

  /** 갱신이 실패했을 때: 네트워크가 잡히면 한 번 더 갱신(이미 대기 중이면 그대로). */
  fun scheduleRetryWhenOnline(context: Context) {
    try {
      val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as JobScheduler
      if (scheduler.getPendingJob(JOB_RETRY) != null) return
      scheduler.schedule(
          JobInfo.Builder(JOB_RETRY, ComponentName(context, WidgetRefreshJobService::class.java))
              .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
              .setMinimumLatency(20_000L) // 방금 실패한 직후에 바로 또 시도하지 않게
              .setOverrideDeadline(6 * 60 * 60 * 1000L)
              .build()
      )
    } catch (e: Throwable) {
    }
  }
}

/** 위 WidgetRefresh의 주기/재시도 작업이 실제로 도는 곳. */
class WidgetRefreshJobService : JobService() {
  override fun onStartJob(params: JobParameters): Boolean {
    thread {
      try {
        WidgetRefresh.refreshAllNow(applicationContext)
      } catch (e: Throwable) {
      } finally {
        jobFinished(params, false)
      }
    }
    return true // 별도 스레드에서 계속 도는 중
  }

  override fun onStopJob(params: JobParameters): Boolean = false
}
