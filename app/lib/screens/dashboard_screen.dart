import 'package:flutter/material.dart';

import '../api_client.dart';
import '../device_registry.dart';
import '../models/issue.dart';
import '../theme.dart';
import '../widgets/app_card.dart';
import '../widgets/expandable_issue_card.dart';
import 'keyword_watch_screen.dart';
import 'stock_watch_screen.dart';

/// 2026-09-21: "관심사 대시보드" — 관심 워치·관심 종목·오늘의 트렌드를
/// 한 화면에서 훑어보는 요약 화면. 새 데이터/인프라를 만들지 않고
/// 이미 있는 세 화면(keyword_watch_screen.dart, stock_watch_screen.dart,
/// 홈의 /trending)이 쓰는 API를 그대로 다시 불러서 압축해서 보여줌 —
/// 각 섹션은 "더보기"로 해당 전체 화면(등록/삭제 등 관리 기능이 있는
/// 원래 화면)으로 넘어감, 여기서는 관리 기능 없이 훑어보기만.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final DeviceRegistry _devices = DeviceRegistry(widget.api);

  Future<List<KeywordWatch>>? _watches;
  Future<List<StockWatch>>? _stocks;
  late final Future<List<IssueSummary>> _index;
  late final Future<List<IssueDetail>> _trending;

  @override
  void initState() {
    super.initState();
    _watches = _devices.listWatches();
    _stocks = _devices.listStockWatches();
    _index = widget.api.getIndex();
    _trending = widget.api.getTrending(limit: 5);
  }

  Future<void> _refresh() async {
    setState(() {
      _watches = _devices.listWatches();
      _stocks = _devices.listStockWatches();
    });
    await Future.wait([_watches!, _stocks!]);
  }

  /// 홈 화면 검색(_HomeScreenState._search)·관심 워치와 같은 매칭 기준.
  List<IssueSummary> _matches(List<IssueSummary> index, String keyword) {
    final q = keyword.toLowerCase();
    final matched = index
        .where((i) =>
            i.keyword.toLowerCase().contains(q) ||
            i.keywords.any((k) => k.toLowerCase().contains(q)) ||
            i.representativeTitle.toLowerCase().contains(q))
        .toList();
    matched.sort((a, b) => b.outletCount.compareTo(a.outletCount));
    return matched;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      '관심사 대시보드',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    _SectionHeader(
                      title: '관심 워치',
                      onMore: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => KeywordWatchScreen(api: widget.api)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<KeywordWatch>>(
                      future: _watches,
                      builder: (context, watchSnap) {
                        if (watchSnap.connectionState != ConnectionState.done) {
                          return const _SectionLoading();
                        }
                        final watches = watchSnap.data ?? const [];
                        if (watches.isEmpty) {
                          return _EmptySection(
                            text: '관심 있는 인물이나 키워드를 등록하면 여기 요약돼요',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => KeywordWatchScreen(api: widget.api)),
                            ),
                          );
                        }
                        return FutureBuilder<List<IssueSummary>>(
                          future: _index,
                          builder: (context, indexSnap) {
                            if (indexSnap.connectionState != ConnectionState.done) {
                              return const _SectionLoading();
                            }
                            final index = indexSnap.data ?? const [];
                            final maxOutlet =
                                index.isEmpty ? 1 : index.map((i) => i.outletCount).reduce((a, b) => a > b ? a : b);
                            return Column(
                              children: [
                                for (final w in watches) ...[
                                  _WatchSummaryRow(
                                    keyword: w.keyword,
                                    top: _matches(index, w.keyword).take(1).toList(),
                                    api: widget.api,
                                    maxOutletCount: maxOutlet,
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ],
                            );
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(
                      title: '관심 종목',
                      onMore: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => StockWatchScreen(api: widget.api)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<StockWatch>>(
                      future: _stocks,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const _SectionLoading();
                        }
                        final stocks = snapshot.data ?? const [];
                        if (stocks.isEmpty) {
                          return _EmptySection(
                            text: '관심 있는 종목을 등록하면 시세와 뉴스가 여기 요약돼요',
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => StockWatchScreen(api: widget.api)),
                            ),
                          );
                        }
                        return _StockSummaryCard(
                          stocks: stocks,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => StockWatchScreen(api: widget.api)),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(title: '오늘의 트렌드', onMore: () => Navigator.of(context).pop()),
                    const SizedBox(height: 8),
                    FutureBuilder<List<IssueDetail>>(
                      future: _trending,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const _SectionLoading();
                        }
                        final issues = snapshot.data ?? const [];
                        if (issues.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text('아직 집계된 이슈가 없어요', style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint)),
                          );
                        }
                        final maxOutlet = issues.map((i) => i.outletCount).reduce((a, b) => a > b ? a : b);
                        return Column(
                          children: [
                            for (var i = 0; i < issues.length; i++) ...[
                              ExpandableIssueCard(
                                key: ValueKey(issues[i].id),
                                rank: i + 1,
                                issue: issues[i],
                                maxOutletCount: maxOutlet,
                              ),
                              if (i != issues.length - 1) const SizedBox(height: 8),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.onMore});

  final String title;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
        const Spacer(),
        InkWell(
          onTap: onMore,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('더보기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.inkFaint)),
                Icon(Icons.chevron_right, size: 14, color: AppColors.inkFaint),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Expanded(child: Text(text, style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint, height: 1.4))),
            const SizedBox(width: 8),
            Icon(Icons.add_circle_outline, size: 18, color: AppColors.accent),
          ],
        ),
      ),
    );
  }
}

/// 관심 워치 키워드 하나의 압축 요약 — 가장 매체 커버리지가 높은 관련
/// 이슈 1건만 카드로 보여줌(전체 목록은 keyword_watch_screen.dart로).
class _WatchSummaryRow extends StatelessWidget {
  const _WatchSummaryRow({
    required this.keyword,
    required this.top,
    required this.api,
    required this.maxOutletCount,
  });

  final String keyword;
  final List<IssueSummary> top;
  final ApiClient api;
  final int maxOutletCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Container(width: 3, height: 12, decoration: BoxDecoration(color: AppColors.accent2, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 7),
              Text(keyword, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkSoft, letterSpacing: 0.3)),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (top.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text('아직 관련 이슈가 없어요', style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint)),
          )
        else
          ExpandableIssueCard(key: ValueKey(top.first.id), issue: top.first, api: api, maxOutletCount: maxOutletCount),
      ],
    );
  }
}

/// 관심 종목 압축 요약 — 티커별 등락률 칩 + 맨 위 종목의 최신 헤드라인
/// 한 줄만 보여줌(전체 뉴스 목록은 stock_watch_screen.dart로).
class _StockSummaryCard extends StatelessWidget {
  const _StockSummaryCard({required this.stocks, required this.onTap});

  final List<StockWatch> stocks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final withNews = stocks.where((s) => s.news.isNotEmpty).toList();
    final headline = withNews.isEmpty ? null : (withNews.first, withNews.first.news.first);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final s in stocks) _QuoteChip(watch: s)],
            ),
            if (headline != null) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: AppColors.divider),
              const SizedBox(height: 10),
              Text(
                '${headline.$1.ticker} · ${headline.$2.titleKo ?? headline.$2.title}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: AppColors.inkSoft, height: 1.4),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuoteChip extends StatelessWidget {
  const _QuoteChip({required this.watch});

  final StockWatch watch;

  @override
  Widget build(BuildContext context) {
    final quote = watch.quote;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(watch.ticker, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
          if (quote != null) ...[
            const SizedBox(width: 4),
            Text(
              '${quote.percent >= 0 ? '+' : ''}${quote.percent.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: quote.percent >= 0 ? AppColors.accent : AppColors.accent2,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
