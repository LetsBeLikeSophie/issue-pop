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

  /// 2026-09-21: 정치성향 필터 — 원래 홈 화면 상단바에 있었는데, "홈
  /// 화면엔 필터 UI 자체가 안 보여야 한다, 다른 데 있어야 한다"는
  /// 피드백으로 여기(대시보드)로 옮김. 관심사를 모아보는 화면이 필터
  /// 상태를 들고 있는 자리로 더 맞다고 판단함.
  String? _leaningFilter;

  @override
  void initState() {
    super.initState();
    _watches = _devices.listWatches();
    _stocks = _devices.listStockWatches();
    _index = widget.api.getIndex();
    // 40건을 받아서 성향으로 거른 다음 상위 5건만 보여줌 — 처음부터
    // 5건만 받으면 필터링 후 5건이 안 남을 수 있어서(홈 화면과 같은 이유).
    _trending = widget.api.getTrending(limit: 40);
  }

  List<T> _filterByLeaning<T extends IssueSummary>(List<T> issues) {
    final f = _leaningFilter;
    if (f == null) return issues;
    return issues.where((i) => i.leanings.contains(f)).toList();
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
                  // 2026-09-21: 정치성향 필터 컨트롤 — 홈 화면에서 옮겨온
                  // 자리. 여기서 바꾸면 "관심 워치"·"오늘의 트렌드" 둘 다
                  // 바로 그 성향 매체 기준으로 다시 걸러짐.
                  _LeaningCycler(
                    active: _leaningFilter,
                    onChanged: (l) => setState(() => _leaningFilter = l),
                    api: widget.api,
                  ),
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
                                    top: _filterByLeaning(_matches(index, w.keyword)).take(1).toList(),
                                    api: widget.api,
                                    maxOutletCount: maxOutlet,
                                    activeLeaning: _leaningFilter,
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
                        final issues = _filterByLeaning(snapshot.data ?? const <IssueDetail>[]).take(5).toList();
                        if (issues.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              _leaningFilter == null ? '아직 집계된 이슈가 없어요' : '$_leaningFilter 매체의 이슈가 없어요',
                              style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint),
                            ),
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
                                activeLeaning: _leaningFilter,
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
    this.activeLeaning,
  });

  final String keyword;
  final List<IssueSummary> top;
  final ApiClient api;
  final int maxOutletCount;
  final String? activeLeaning;

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
            child: Text(
              activeLeaning == null ? '아직 관련 이슈가 없어요' : '$activeLeaning 매체의 관련 이슈가 없어요',
              style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint),
            ),
          )
        else
          ExpandableIssueCard(
            key: ValueKey(top.first.id),
            issue: top.first,
            api: api,
            maxOutletCount: maxOutletCount,
            activeLeaning: activeLeaning,
          ),
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

/// 2026-09-21: 정치성향 필터 — 화살표로 kLeaningOptions를 순환 선택.
/// 원래 home_screen.dart 상단바에 있었는데 "홈 화면엔 필터 UI 자체가
/// 안 보여야 한다"는 피드백으로 여기로 옮김. 라벨 색은 실제 진영 색
/// (빨강=보수/파랑=진보, 중도는 검정에 가까운 ink)을 스펙트럼 위치에
/// 따라 섞어서 보여줌(theme.dart의 leaningTint). 라벨을 누르면 지금
/// 확보한 매체 현황 + 분류 근거를 모달로 보여줌.
class _LeaningCycler extends StatelessWidget {
  const _LeaningCycler({required this.active, required this.onChanged, required this.api});

  final String? active;
  final ValueChanged<String?> onChanged;
  final ApiClient api;

  void _step(int delta) {
    final i = kLeaningOptions.indexOf(active);
    final next = (i + delta) % kLeaningOptions.length;
    onChanged(kLeaningOptions[next < 0 ? next + kLeaningOptions.length : next]);
  }

  void _showInfo(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (_) => _LeaningInfoSheet(api: api),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.chevron_left, size: 18, color: AppColors.inkFaint),
          onPressed: () => _step(-1),
          tooltip: '이전 성향',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        InkWell(
          onTap: () => _showInfo(context),
          child: SizedBox(
            width: 52,
            height: 36,
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: leaningTint(active)),
                child: Text(active ?? '전체', textAlign: TextAlign.center),
              ),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.chevron_right, size: 18, color: AppColors.inkFaint),
          onPressed: () => _step(1),
          tooltip: '다음 성향',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
      ],
    );
  }
}

/// 정치성향 필터 라벨을 누르면 뜨는 안내 모달 — "지금 우리가 실제로
/// 수집 중인 매체가 어디까지고, 성향은 어떻게 분류했는지" 설명함.
/// 데이터는 새로 안 만들고 backend sources.py를 그대로 노출하는
/// /outlets/leanings를 호출함(단일 소스 유지).
class _LeaningInfoSheet extends StatelessWidget {
  const _LeaningInfoSheet({required this.api});

  final ApiClient api;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '지금 우리가 보는 매체',
              style: AppTypography.serif(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const SizedBox(height: 8),
            Text(
              '조중동=보수, 한겨레·경향=진보처럼 학계·언론에서 통상적으로 '
              '쓰이는 분류와 최근 소유구조 변화 등 사실관계를 참고했어요. '
              '국가 공인 통계가 아닌 참고용이라, 한국언론진흥재단의 '
              '〈언론수용자 조사〉가 새로 나올 때마다 다시 검토해요.',
              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.5),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: FutureBuilder<List<OutletLeaningInfo>>(
                future: api.getOutletLeanings(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    );
                  }
                  if (snapshot.hasError || snapshot.data == null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text('불러오지 못했어요', style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint)),
                    );
                  }
                  final outlets = [...snapshot.data!]..sort(
                      (a, b) => kLeaningOptions.indexOf(a.politicalLeaning).compareTo(
                            kLeaningOptions.indexOf(b.politicalLeaning),
                          ),
                    );
                  return ListView.separated(
                    shrinkWrap: true,
                    itemCount: outlets.length,
                    separatorBuilder: (_, _) => Divider(height: 16, color: AppColors.line),
                    itemBuilder: (context, i) {
                      final o = outlets[i];
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(
                              o.outlet,
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
                            ),
                          ),
                          SizedBox(
                            width: 52,
                            child: Text(
                              o.politicalLeaning ?? '미분류',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: leaningTint(o.politicalLeaning),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              o.leaningSource ?? '',
                              style: TextStyle(fontSize: 11, color: AppColors.inkFaint, height: 1.4),
                            ),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '한국언론진흥재단 〈언론수용자 조사〉 · 매체 소유구조 등 공개 정보 종합',
              style: TextStyle(fontSize: 10.5, color: AppColors.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}
