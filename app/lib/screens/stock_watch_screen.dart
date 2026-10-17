import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../device_registry.dart';
import '../theme.dart';
import '../theme_store.dart';
import '../widgets/app_badge.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_retry.dart';
import '../widgets/in_app_browser.dart';
import '../widgets/removable_chip.dart';
import '../widgets/screen_header.dart';
import '../widgets/scroll_spotlight.dart';
import '../stock_widget_store.dart';

/// 2026-09-06: 관심 종목(브랜드) 뉴스. 저장한 이슈(Archive)와 같은 패턴 —
/// 홈 화면 피드에는 아무것도 안 섞고, 상단바 아이콘 하나로만 진입함(홈
/// 화면 코드에 남아있는 "큐레이션성 콘텐츠는 이 화면에 안 섞는다"는
/// 결론과 같은 이유).
class StockWatchScreen extends StatefulWidget {
  const StockWatchScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<StockWatchScreen> createState() => _StockWatchScreenState();
}

class _StockWatchScreenState extends State<StockWatchScreen> {
  late final DeviceRegistry _devices = DeviceRegistry(widget.api);
  Future<List<StockWatch>>? _watches;
  final _spotlight = ScrollSpotlightController();

  /// 2026-09-07: 가격을 탭하면 달러/원화가 화면 전체에서 한 번에 바뀌는
  /// 토글("환율 계산까지는 힘든가... 원으로 보고 싶다"는 피드백으로 추가,
  /// 설정 화면까지 가는 대신 숫자 자체를 눌러서 바꾸는 쪽을 택함 — 러닝
  /// 앱에서 거리 탭하면 km/mile 바뀌는 것과 같은 패턴). 환율은 서버가
  /// 하루 단위로 캐싱해둔 걸 한 번만 받아옴(Frankfurter.app 기반).
  double? _usdKrwRate;
  bool _showKrw = false;

  /// 2026-10-17: 홈 화면 위젯에 보일 종목(StockWidgetStore). null이면 한 번도 안 정한 상태 —
  /// 관심 종목 앞 3개가 기본.
  List<String>? _savedPicks;
  String _lastSynced = '';

  /// 2026-10-18: 방금 추가한 종목은 서버가 시세/뉴스를 뒤에서 가져오는 중(StockWatch.loading) — 끝날 때까지 3초마다 조용히 다시 받아옴.
  Timer? _pollTimer;
  int _pollTries = 0;

  void _schedulePoll(List<StockWatch> watches) {
    if (!watches.any((w) => w.loading) || _pollTries >= 12 || (_pollTimer?.isActive ?? false)) return;
    _pollTimer = Timer(const Duration(seconds: 3), () async {
      _pollTries++;
      try {
        final list = await _devices.listStockWatches();
        if (!mounted) return;
        setState(() => _watches = Future.value(list));
      } catch (_) {
        // 다음 주기에 다시.
      }
    });
  }

  void _toggleCurrency() {
    if (_usdKrwRate == null) return; // 환율을 아직 못 받아왔으면 토글해도 의미 없음
    setState(() => _showKrw = !_showKrw);
  }

  @override
  void initState() {
    super.initState();
    _watches = _devices.listStockWatches();
    StockWidgetStore.loadPicks().then((p) {
      if (mounted) setState(() => _savedPicks = p);
    });
    widget.api.getUsdKrwRate().then((rate) {
      if (mounted && rate != null) setState(() => _usdKrwRate = rate);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _spotlight.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _watches = _devices.listStockWatches();
    });
    await _watches;
  }

  /// 위젯에 보일 종목을 위젯에 알림(바로 갱신). 같은 내용이면 다시 안 보냄.
  Future<void> _syncWidget(List<String> picks) async {
    final key = picks.join(',');
    if (key == _lastSynced) return;
    _lastSynced = key;
    try {
      await StockWidgetStore.syncToWidget(deviceId: await _devices.currentDeviceId(), tickers: picks);
    } catch (_) {}
  }

  Future<void> _setPicks(List<String> picks) async {
    setState(() => _savedPicks = picks);
    await StockWidgetStore.savePicks(picks);
    await _syncWidget(picks);
  }

  void _dropOnTray(String ticker, List<String> current) {
    if (current.contains(ticker)) return;
    if (current.length >= StockWidgetStore.maxPicks) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('위젯에는 최대 ${StockWidgetStore.maxPicks}개까지 보여요. 하나를 빼고 넣어주세요'),
            duration: const Duration(milliseconds: 2200),
            behavior: SnackBarBehavior.floating,
          ),
        );
      return;
    }
    _setPicks([...current, ticker]);
  }

  Future<void> _removeTicker(int watchId) async {
    await _devices.deleteStockWatch(watchId);
    await _refresh();
  }

  Future<void> _showAddSheet() async {
    // 이미 추가한 티커는 미리보기/검색 결과에서 빼기 위해 넘겨줌 —
    // _watches는 이미 완료됐거나 진행 중인 Future라 다시 await해도
    // 새 네트워크 요청은 안 일어남.
    final currentTickers = (await _watches)?.map((w) => w.ticker).toSet() ?? <String>{};
    if (!mounted) return;
    final ticker = await showAppBottomSheet<String>(
      context,
      isScrollControlled: true,
      builder: (_) => _TickerSearchSheet(api: widget.api, currentTickers: currentTickers),
    );
    if (ticker == null) return;
    // 2026-10-18: 서버가 시세/뉴스를 가져오는 동안(수 초) 아무 표시가 없어서 되고 있는지 몰랐다는 피드백 — 등록하자마자 알려줌.
    if (mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('$ticker 추가했어요. 시세와 뉴스를 불러오는 중이에요'),
            duration: const Duration(milliseconds: 2400),
            behavior: SnackBarBehavior.floating,
          ),
        );
    }
    await _devices.addStockWatch(ticker);
    _pollTries = 0;
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    // 2026-09-26: AppColors.xxx는 static getter라(Theme.of(context) 같은
    // InheritedWidget이 아님) 색 테마를 바꿔도 이미 push돼서 화면에 떠
    // 있는 화면(설정 등)은 자동으로 다시 안 그려지던 버그 — 화면
    // 최상단에서 직접 구독해서 고침(archive_screen.dart와 같은 패턴).
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    return Scaffold(
      floatingActionButton: ScrollJumpFab(controller: _spotlight),
      body: SafeArea(
        child: Column(
          children: [
            ScreenHeader(title: '관심 종목', trailingLabel: '종목 추가', onTrailingTap: _showAddSheet),
            Expanded(
              child: FutureBuilder<List<StockWatch>>(
                future: _watches,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                  }
                  if (snapshot.hasError) {
                    return ErrorRetry(error: '${snapshot.error}', onRetry: _refresh);
                  }

                  final watches = snapshot.data ?? [];
                  final widgetPicks = StockWidgetStore.effective(_savedPicks, watches.map((w) => w.ticker).toList());
                  if (watches.isNotEmpty) {
                    // 종목을 추가/삭제했거나 기본값이 바뀌었을 때도 위젯에 알려줌(같은 내용이면 무시됨).
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        _syncWidget(widgetPicks);
                        _schedulePoll(watches);
                      }
                    });
                  }
                  if (watches.isEmpty) {
                    return const EmptyState(
                      icon: Icons.show_chart,
                      title: '아직 등록된 종목이 없어요',
                      subtitle: '위 "종목 추가"로 관심 있는 티커를 등록해보세요',
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: _refresh,
                    child: SingleChildScrollView(
                      // 티커 칩 클릭 → 스크롤 이동 기능 때문에 ListView 대신 이걸 씀.
                      // ListView는 children을 통째로 넘겨도 화면 밖으로 멀어진
                      // 항목은 내부적으로 언마운트함(가상화가 .builder 전용이
                      // 아니라 SliverList 계열 전체에 적용됨) — 그래서
                      // GlobalKey.currentContext가 null이 돼서 스크롤 이동이
                      // 조용히 실패했었음(2026-09-06 발견). 이 화면은 종목이
                      // 많아야 수십 개 수준이라 전부 마운트해둬도 성능에
                      // 문제없어서, 가상화 없는 이 위젯으로 바꿔서 해결함.
                      controller: _spotlight.scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _StockSummaryBar(watches: watches),
                          const SizedBox(height: 16),
                          _WidgetTray(
                            picks: widgetPicks,
                            customized: _savedPicks != null,
                            onDrop: (t) => _dropOnTray(t, widgetPicks),
                            onRemove: (t) => _setPicks(widgetPicks.where((x) => x != t).toList()),
                          ),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final w in watches)
                                // 2026-10-17: 길게 눌러서 위의 "위젯에 표시" 칸으로 끌어다 놓으면 위젯에 보임.
                                LongPressDraggable<String>(
                                  data: w.ticker,
                                  maxSimultaneousDrags: 1,
                                  feedback: Material(
                                    color: Colors.transparent,
                                    child: _DragPill(label: w.ticker),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.35,
                                    child: RemovableChip(label: w.ticker, onRemove: () {}),
                                  ),
                                  child: RemovableChip(
                                    label: w.ticker,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (w.quote != null)
                                          Text(
                                            _formatPercent(w.quote!.percent),
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color: w.quote!.percent >= 0 ? AppColors.stockUp : AppColors.stockDown,
                                            ),
                                          ),
                                        if (widgetPicks.contains(w.ticker)) ...[
                                          const SizedBox(width: 3),
                                          Icon(Icons.widgets_outlined, size: 11, color: AppColors.accent),
                                        ],
                                      ],
                                    ),
                                    onTap: () => _spotlight.scrollTo(w.ticker),
                                    onRemove: () => _removeTicker(w.id),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          for (final w in watches) ...[
                            _StockCard(
                              key: _spotlight.keyFor(w.ticker),
                              watch: w,
                              showKrw: _showKrw,
                              usdKrwRate: _usdKrwRate,
                              onTapPrice: _toggleCurrency,
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2026-10-17: 홈 화면 위젯에 보일 종목을 담는 칸 — 아래 티커 칩을 길게 눌러 끌어다 놓으면 들어가고,
/// 칸 안의 칩의 X로 뺌. 한 번도 안 정했을 땐 기본(맨 앞 3개)이 채워져 있음.
class _WidgetTray extends StatelessWidget {
  const _WidgetTray({required this.picks, required this.customized, required this.onDrop, required this.onRemove});

  final List<String> picks;

  /// 사용자가 한 번이라도 직접 정했는지(아니면 기본값이 채워진 상태).
  final bool customized;
  final void Function(String ticker) onDrop;
  final void Function(String ticker) onRemove;

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) {
        final hovering = candidates.isNotEmpty;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: hovering ? AppColors.accentSoft : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: hovering ? AppColors.accent : AppColors.line, width: hovering ? 1.5 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.widgets_outlined, size: 15, color: AppColors.inkSoft),
                  const SizedBox(width: 6),
                  Text(
                    '홈 화면 위젯에 표시 (최대 ${StockWidgetStore.maxPicks}개)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.inkSoft),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (picks.isEmpty)
                Text(
                  '아래 종목을 길게 눌러 여기로 끌어다 놓으세요. 비워두면 맨 앞 ${StockWidgetStore.maxPicks}개가 보여요.',
                  style: TextStyle(fontSize: 12, color: AppColors.inkFaint, height: 1.4),
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [for (final t in picks) RemovableChip(label: t, onRemove: () => onRemove(t))],
                ),
              if (picks.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  customized
                      ? '위젯을 세로로 늘리면 더 많은 종목이 보여요(최대 ${StockWidgetStore.maxPicks}개).'
                      : '기본으로 맨 앞 ${StockWidgetStore.maxPicks}개가 위젯에 보여요. 아래 종목을 길게 눌러 끌어다 놓으면 바꿀 수 있고, 위젯을 세로로 늘리면 더 많이 보여요.',
                  style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint, height: 1.4),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 2026-10-18: 종목 이름을 홈 이슈 카드의 제목과 같은 세리프(17 굵게)로 — 관심 종목만 본문 글꼴 13.5라 따로 놀았음. 서버가 주는
/// "애플 Apple"에서 한글 이름을 크게, 영어는 그 아래 작게(한 줄에 이어 붙이면 가격/등락률과 함께 줄바꿈되고 잘려서 번잡했음).
/// 한글이 없는 종목은 전체를 큰 글자로.
class _StockName extends StatelessWidget {
  const _StockName({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = name.split(' ');
    final lastKo = tokens.lastIndexWhere((t) => t.runes.any((r) => r >= 0xAC00 && r <= 0xD7A3));
    final ko = lastKo < 0 ? name : tokens.take(lastKo + 1).join(' ');
    final en = lastKo < 0 ? '' : tokens.skip(lastKo + 1).join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          ko,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.serif(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        if (en.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              en,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            ),
          ),
      ],
    );
  }
}

/// 끌고 다니는 동안 손가락 아래에 따라오는 알약.
class _DragPill extends StatelessWidget {
  const _DragPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(999),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 2))],
      ),
      child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
    );
  }
}

String _formatPercent(double percent) => '${percent >= 0 ? '+' : ''}${percent.toStringAsFixed(1)}%';

/// 소수점 둘째 자리까지의 달러 표시("$234.12").
String _formatUsd(double price) => '\$${price.toStringAsFixed(2)}';

/// 환율 곱해서 반올림 후 3자리마다 콤마 찍은 원화 표시("419,999원").
String _formatKrw(double usdPrice, double rate) {
  final won = (usdPrice * rate).round();
  final digits = won.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '$buffer원';
}

/// 2026-09-26: 뉴스 목록을 항상 다 펼쳐서 보여주던 걸 홈 화면 이슈
/// 카드(ExpandableIssueCard)처럼 헤더를 눌러야 펼쳐지게 바꿈. 처음엔
/// 최신 기사 1건을 미리보기로 항상 보여줬는데, 그게 실제로는 외부
/// 링크라서 "펼치려고 눌렀는데 기사로 나가버린다"는 피드백으로
/// 없앰 — 접혀있을 땐 건수 텍스트만(누를 게 없음), 펼쳐야만 실제
/// 링크 목록이 나옴. 가격도 헤더 좌측 종목명과 나란히 두지 않고
/// 우측으로 옮겨서(등락률과 가로로 나란히) 한눈에 훑기 쉽게 함.
class _StockCard extends StatefulWidget {
  const _StockCard({
    super.key,
    required this.watch,
    required this.showKrw,
    required this.usdKrwRate,
    required this.onTapPrice,
  });

  final StockWatch watch;

  /// 2026-09-07: 가격 탭하면 화면 전체가 달러/원화로 한 번에 바뀌는
  /// 토글 상태 — StockWatchScreen이 들고 있고 여기선 그대로 받아서
  /// 보여주기만 함(상태를 카드마다 따로 두면 "이 카드는 원인데 저
  /// 카드는 달러" 같은 혼란이 생겨서 화면 단위로 통일).
  final bool showKrw;
  final double? usdKrwRate;
  final VoidCallback onTapPrice;

  @override
  State<_StockCard> createState() => _StockCardState();
}

class _StockCardState extends State<_StockCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final watch = widget.watch;
    final quote = watch.quote;
    final news = watch.news;
    final hasNews = news.isNotEmpty;

    return AppCard(
      radius: 12,
      padding: EdgeInsets.zero,
      // 2026-09-26: 홈 화면 이슈 카드(ExpandableIssueCard)는 펼치면 테두리가
      // accent로 진해지는데, 이 카드는 AppCard를 그냥 써서 그 표시가
      // 빠져 있었음 — 같은 컴포넌트를 쓰게 맞춤.
      highlighted: _expanded,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: hasNews ? () => setState(() => _expanded = !_expanded) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 2026-09-26: accent2(경고/하락 톤)를 쓰고 있어서 위
                      // 티커 칩(RemovableChip, accent 톤)과 같은 티커인데
                      // 색이 달라 보였음 — accent로 맞춤.
                      AppBadge.filled(label: watch.ticker, background: AppColors.accentSoft, foreground: AppColors.accent),
                      const SizedBox(width: 10),
                      Expanded(child: _StockName(name: watch.name)),
                      if (watch.loading && quote == null) ...[
                        // 2026-10-18: 방금 추가해서 서버가 시세/뉴스를 가져오는 중 — 아무 표시가 없으면 되고 있는지 알 수 없다는 피드백.
                        const SizedBox(width: 8),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
                            ),
                            const SizedBox(height: 4),
                            Text('불러오는 중', style: TextStyle(fontSize: 10.5, color: AppColors.inkFaint)),
                          ],
                        ),
                      ] else if (quote != null) ...[
                        const SizedBox(width: 8),
                        // 2026-10-18: 이름·가격·등락률이 한 줄에 다 있어 번잡하고 이름이 줄바꿈/잘리던 문제 — 가격 위, 등락률 아래로
                        // 쌓아서 이름이 가운데 폭을 넉넉히 씀. 가격 탭은 통화 토글(카드 펼치기와는 별개 동작)이라 안쪽에 따로 InkWell을
                        // 둬서 바깥 헤더 탭(펼치기)과 안 겹치게 함.
                        InkWell(
                          onTap: widget.usdKrwRate == null ? null : widget.onTapPrice,
                          borderRadius: BorderRadius.circular(6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                widget.showKrw && widget.usdKrwRate != null
                                    ? _formatKrw(quote.price, widget.usdKrwRate!)
                                    : _formatUsd(quote.price),
                                style: AppTypography.mono(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink),
                              ),
                              const SizedBox(height: 3),
                              AppBadge.filled(
                                label: _formatPercent(quote.percent),
                                background: quote.percent >= 0 ? AppColors.stockUpSoft : AppColors.stockDownSoft,
                                foreground: quote.percent >= 0 ? AppColors.stockUp : AppColors.stockDown,
                                mono: true,
                              ),
                            ],
                          ),
                        ),
                      ],
                      if (hasNews) ...[
                        const SizedBox(width: 4),
                        AnimatedRotation(
                          turns: _expanded ? 0.25 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Icon(Icons.chevron_right, size: 16, color: AppColors.inkFaint),
                        ),
                      ],
                    ],
                  ),
                  // 2026-09-26: 접혀있을 때 "관련 뉴스 N건"만 보이니 카드가
                  // 휑하다는 피드백 — 최신 기사 제목을 미리 보여주되, 이번엔
                  // 헤더 탭 영역 "안"에 그냥 텍스트로 넣어서(별도 링크
                  // InkWell 아님) 눌러도 펼치기만 되고 실수로 기사 링크로
                  // 나가는 일은 없게 함. 실제 링크는 펼쳤을 때만 나옴.
                  if (hasNews && !_expanded) ...[
                    const SizedBox(height: 6),
                    Text(
                      news.first.titleKo ?? news.first.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.45),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (!hasNews)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
              child: Text('아직 받아온 뉴스가 없어요', style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint)),
            )
          else
            AnimatedSize(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: !_expanded
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                      child: Column(
                        // 2026-09-26: 이 Column에 정렬을 안 정해줘서 기본값인
                        // center가 적용돼 있었음 — 기사마다 제목 길이(=이
                        // InkWell의 고유 너비)가 달라서 각 줄이 서로 다르게
                        // 가운데 정렬되며 왼쪽이 들쭉날쭉해 보이던 버그.
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Divider(height: 1, color: AppColors.line),
                          // 도트 대신 얇은 구분선으로 목록처럼 보이게 함(아이콘은
                          // 넣지 말아달라던 예전 결정과 안 부딪히면서, 신문
                          // 지면에서 기사 사이를 가르는 느낌 —
                          // expandable_issue_card.dart와 같은 처리).
                          for (var i = 0; i < news.length; i++) ...[
                            if (i != 0) Divider(height: 1, color: AppColors.divider),
                            _NewsRow(item: news[i]),
                          ],
                        ],
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// 2026-09-25: "관심 종목 전체적으로 오늘 어때?"를 카드 하나하나 안
/// 훑어봐도 바로 알 수 있게 추가한 요약 바 — 상승/하락 개수와 평균
/// 등락률 전부 이미 받아온 quote만으로 클라이언트에서 계산함(새 API
/// 없음). quote가 없는 종목(시세 실패)은 계산에서 제외.
class _StockSummaryBar extends StatelessWidget {
  const _StockSummaryBar({required this.watches});

  final List<StockWatch> watches;

  @override
  Widget build(BuildContext context) {
    final quoted = watches.where((w) => w.quote != null).toList();
    final rising = quoted.where((w) => w.quote!.percent >= 0).length;
    final falling = quoted.length - rising;
    final avg = quoted.isEmpty ? null : quoted.map((w) => w.quote!.percent).reduce((a, b) => a + b) / quoted.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(child: _SummaryStat(value: '$rising개', label: '상승', color: AppColors.stockUp)),
          Container(width: 1, height: 26, color: AppColors.line),
          Expanded(child: _SummaryStat(value: '$falling개', label: '하락', color: AppColors.stockDown)),
          Container(width: 1, height: 26, color: AppColors.line),
          Expanded(
            child: _SummaryStat(
              value: avg == null ? '—' : _formatPercent(avg),
              label: '평균 등락',
              color: avg == null ? AppColors.inkFaint : (avg >= 0 ? AppColors.stockUp : AppColors.stockDown),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: AppTypography.mono(fontSize: 17, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10.5, color: AppColors.inkFaint, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _NewsRow extends StatelessWidget {
  const _NewsRow({required this.item});

  final StockNewsItem item;

  @override
  Widget build(BuildContext context) {
    final translated = item.titleKo;
    return InkWell(
      // 2026-09-26: 인앱 브라우저로 열어서 닫기 버튼으로 바로 앱에
      // 돌아오게 함(expandable_issue_card.dart의 _ArticleLine과 같은
      // 이유 — flutter_custom_tabs로 닫기 버튼을 눈에 띄게 함, in_app_
      // browser.dart 참고).
      onTap: item.link.isEmpty ? null : () => openInAppBrowser(Uri.parse(item.link)),
      child: Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              translated ?? item.title,
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.accent,
                height: 1.5,
                decoration: TextDecoration.underline,
                decorationColor: AppColors.accent.withValues(alpha: 0.35),
                decorationThickness: 1,
              ),
            ),
            // 번역 성공하면 원문(영어)을 옅은 글씨로 아래에 같이 보여줌 —
            // 번역 실패(키 없음/API 오류)하면 이 줄 없이 원문만 위에 나옴.
            if (translated != null) ...[
              const SizedBox(height: 2),
              Text(item.title, style: TextStyle(fontSize: 10, color: AppColors.inkFaint, height: 1.3)),
            ],
            const SizedBox(height: 1),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: item.source),
                  if (_formatPubDate(item.published) case final date?) TextSpan(text: ' · $date'),
                ],
              ),
              style: TextStyle(fontSize: 10, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// 야후 파이낸스 RSS의 pubDate(RFC 822, 예: "Sun, 06 Sep 2026 12:06:22
/// +0000")를 파싱해서 "오늘 기준인지 모르겠다"는 피드백에 맞게 보여줌 —
/// 오늘이면 시:분만, 아니면 날짜만(연도는 대개 올해라 생략). 웹에서도
/// 쓰는 화면이라 dart:io의 HttpDate 대신 직접 파싱함(RFC822 형식이
/// 고정적이라 간단한 파싱으로 충분).
String? _formatPubDate(String? raw) {
  if (raw == null) return null;
  final parts = raw.split(' ');
  if (parts.length < 5) return null;
  const months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };
  final month = months[parts[2]];
  final day = int.tryParse(parts[1]);
  final year = int.tryParse(parts[3]);
  final timeParts = parts[4].split(':').map(int.tryParse).toList();
  if (month == null || day == null || year == null || timeParts.length != 3 || timeParts.contains(null)) {
    return null;
  }
  final utc = DateTime.utc(year, month, day, timeParts[0]!, timeParts[1]!, timeParts[2]!);
  final local = utc.toLocal();
  final now = DateTime.now();
  final isToday = local.year == now.year && local.month == now.month && local.day == now.day;
  if (isToday) {
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
  return '${local.month}월 ${local.day}일';
}

/// 종목 추가 바텀시트 — 2026-09-06: "티커를 미리 알고 있어야 하는 게
/// 불편하다"는 피드백으로, 티커를 직접 아는 사람만 위한 빈 입력창 대신
/// 회사 이름으로도 검색되는 자동완성을 추가함. 카탈로그(GET
/// /stocks/catalog)를 한 번만 받아서 타이핑마다 로컬에서 걸러냄(검색
/// 화면과 같은 패턴) — 그래도 목록에 없는 티커를 직접 입력해서
/// 추가하는 것도 여전히 가능함(직접 입력 후 완료 버튼).
class _TickerSearchSheet extends StatefulWidget {
  const _TickerSearchSheet({required this.api, required this.currentTickers});

  final ApiClient api;

  /// 이미 등록한 티커 — 미리보기/검색 결과에서 빼서 중복 추가를 막음.
  final Set<String> currentTickers;

  @override
  State<_TickerSearchSheet> createState() => _TickerSearchSheetState();
}

class _TickerSearchSheetState extends State<_TickerSearchSheet> {
  final _controller = TextEditingController();
  late final Future<List<StockCatalogEntry>> _catalog;
  String _query = '';

  /// 이미 추가한 티커를 또 추가하려고 하면 보여주는 안내 문구
  /// ("있는 건 추가 안 되어야 할 것 같다"는 피드백으로 추가).
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _catalog = widget.api.getStockCatalog();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? ticker]) {
    final value = (ticker ?? _controller.text).trim().toUpperCase();
    if (value.isEmpty) return;
    if (widget.currentTickers.contains(value)) {
      setState(() => _errorText = '이미 추가된 종목이에요');
      return;
    }
    Navigator.of(context).pop(value);
  }

  /// 2026-09-06: "티커 순위별로 미리보기가 아래 있으면 좋겠다"는 피드백으로
  /// — 검색어가 없을 때도 카탈로그 앞부분(백엔드가 잘 알려진 순서로 정렬해
  /// 내려줌, stocks.py의 catalog() 참고)을 그대로 보여줌. 검색어가 있으면
  /// 기존처럼 티커/이름 매칭으로 걸러냄. 둘 다 이미 등록한 티커는 뺌.
  List<StockCatalogEntry> _visible(List<StockCatalogEntry> all) {
    final pool = all.where((e) => !widget.currentTickers.contains(e.ticker));
    final q = _query.trim().toUpperCase();
    if (q.isEmpty) return pool.take(8).toList();
    return pool.where((e) => e.ticker.contains(q) || e.name.toUpperCase().contains(q)).take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetBody(
      title: '종목 추가',
      subtitle: '회사 이름이나 티커로 검색하세요 (예: 애플, AAPL)',
      children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (v) => setState(() {
                    _query = v;
                    _errorText = null;
                  }),
                  onSubmitted: (_) => _submit(),
                  style: TextStyle(fontSize: 14, color: AppColors.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'AAPL 또는 애플',
                    hintStyle: TextStyle(fontSize: 14, color: AppColors.inkFaint),
                    filled: true,
                    fillColor: AppColors.chipBg,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(onPressed: () => _submit(), icon: Icon(Icons.add_circle, color: AppColors.accent)),
            ],
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 6),
            Text(_errorText!, style: TextStyle(fontSize: 12, color: AppColors.accent2)),
          ],
          FutureBuilder<List<StockCatalogEntry>>(
            future: _catalog,
            builder: (context, snapshot) {
              final matches = _visible(snapshot.data ?? const []);
              if (matches.isEmpty) {
                // 카탈로그에 없는 티커를 입력 중일 때 — "추가가 안 된다"고
                // 오해하지 않게, + 버튼으로 직접 추가할 수 있다는 걸 알려줌
                // ("Spce 추가하려니 안 되네" 피드백으로 추가).
                if (_query.trim().isNotEmpty && _errorText == null) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '목록에 없는 티커예요 — 오른쪽 + 버튼으로 직접 추가할 수 있어요',
                      style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    _query.trim().isEmpty ? '인기 종목' : '검색 결과',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkFaint, letterSpacing: 0.3),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 240),
                    decoration: BoxDecoration(
                      color: AppColors.chipBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.divider),
                      itemBuilder: (context, i) {
                        final m = matches[i];
                        return InkWell(
                          onTap: () => _submit(m.ticker),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            child: Row(
                              children: [
                                AppBadge.filled(
                                  label: m.ticker,
                                  background: AppColors.accentSoft,
                                  foreground: AppColors.accent,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(m.name, style: TextStyle(fontSize: 13, color: AppColors.ink)),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}
