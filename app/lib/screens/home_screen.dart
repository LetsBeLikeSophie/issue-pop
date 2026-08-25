import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/issue.dart';
import '../theme.dart';
import '../widgets/app_card.dart';
import '../widgets/expandable_issue_card.dart';
import 'archive_screen.dart';
import 'settings_screen.dart';

enum _SortMode { outlet, count }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<IssueDetail>> _trending;

  /// 검색·통계·카테고리 칩 개수용 — 이슈 전체를 요약(기사 목록 제외)만
  /// 한 번 받아서 클라이언트가 들고 있음. 2026-08-25: 처음엔 타이핑마다
  /// 서버에 물어보는 구조였는데, "이슈판" 프로토타입만큼 즉각적이지
  /// 않다는 피드백을 받음 — 네트워크 왕복이 있는 한 로컬 필터보다 빠를
  /// 수 없어서, 가벼운 데이터를 클라이언트가 들고 있다가 즉시 거르는
  /// 방식으로 되돌림(대신 기사 목록은 빼서 무거워지지 않게 함).
  late Future<List<IssueSummary>> _index;

  _SortMode _sort = _SortMode.outlet;
  String? _activeCategory;
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _trending = widget.api.getTrending(limit: 40);
    _index = widget.api.getIndex();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _trending = widget.api.getTrending(limit: 40, category: _activeCategory);
      _index = widget.api.getIndex();
    });
    await _trending;
  }

  void _setCategory(String? category) {
    setState(() {
      _activeCategory = category;
      _trending = widget.api.getTrending(limit: 40, category: category);
    });
  }

  List<IssueSummary> _search(List<IssueSummary> pool) {
    final q = _query.toLowerCase();
    return pool
        .where((i) =>
            (_activeCategory == null || i.category == _activeCategory) &&
            (i.keyword.toLowerCase().contains(q) ||
                i.keywords.any((k) => k.toLowerCase().contains(q)) ||
                i.representativeTitle.toLowerCase().contains(q)))
        .toList();
  }

  List<T> _sorted<T extends IssueSummary>(List<T> issues) {
    final list = [...issues];
    if (_sort == _SortMode.count) {
      list.sort((a, b) => b.articleCount.compareTo(a.articleCount));
    } else {
      list.sort((a, b) {
        final c = b.outletCount.compareTo(a.outletCount);
        return c != 0 ? c : b.articleCount.compareTo(a.articleCount);
      });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isSearching = _query.isNotEmpty;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            FutureBuilder<List<IssueSummary>>(
              future: _index,
              builder: (context, indexSnap) {
                final index = indexSnap.data;
                return _TopBar(
                  index: index,
                  onArchive: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ArchiveScreen()),
                  ),
                  onSettings: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  ),
                );
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  children: [
                    const _OngoingInterestSection(),
                    const SizedBox(height: 20),
                    _Toolbar(
                      controller: _searchController,
                      sort: _sort,
                      onSortChanged: (m) => setState(() => _sort = m),
                      onQueryChanged: (q) => setState(() => _query = q),
                    ),
                    const SizedBox(height: 10),
                    FutureBuilder<List<IssueSummary>>(
                      future: _index,
                      builder: (context, indexSnap) {
                        final index = indexSnap.data;
                        if (index == null) return const SizedBox.shrink();
                        final counts = <String, int>{};
                        for (final i in index) {
                          counts[i.category] = (counts[i.category] ?? 0) + 1;
                        }
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CategoryBar(
                            counts: counts,
                            active: _activeCategory,
                            onSelected: _setCategory,
                          ),
                        );
                      },
                    ),
                    if (isSearching)
                      FutureBuilder<List<IssueSummary>>(
                        future: _index,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return _ErrorRetry(error: snapshot.error.toString(), onRetry: _refresh);
                          }
                          final issues = _sorted(_search(snapshot.data ?? []));
                          return _IssueList(
                            issues: issues,
                            api: widget.api,
                            showRank: false,
                            emptyText: '검색 결과가 없어요',
                          );
                        },
                      )
                    else
                      FutureBuilder<List<IssueDetail>>(
                        future: _trending,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          if (snapshot.hasError) {
                            return _ErrorRetry(error: snapshot.error.toString(), onRetry: _refresh);
                          }
                          final issues = _sorted<IssueDetail>(snapshot.data ?? []);
                          return _IssueList(
                            issues: issues,
                            api: null,
                            showRank: true,
                            emptyText: '아직 집계된 이슈가 없어요',
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

/// 홈 기본 목록(항상 IssueDetail, 즉시 펼침)이든 검색 결과(IssueSummary,
/// 펼칠 때 [api]로 상세를 받아옴)든 같은 방식으로 렌더링.
class _IssueList extends StatelessWidget {
  const _IssueList({
    required this.issues,
    required this.api,
    required this.showRank,
    required this.emptyText,
  });

  final List<IssueSummary> issues;
  final ApiClient? api;
  final bool showRank;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (issues.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(child: Text(emptyText)),
      );
    }
    final maxOutlet = issues.map((i) => i.outletCount).reduce((a, b) => a > b ? a : b);
    return Column(
      children: [
        for (var i = 0; i < issues.length; i++) ...[
          ExpandableIssueCard(
            key: ValueKey(issues[i].id),
            rank: showRank ? i + 1 : null,
            issue: issues[i],
            api: api,
            maxOutletCount: maxOutlet,
          ),
          if (i != issues.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.index,
    required this.onArchive,
    required this.onSettings,
  });

  final List<IssueSummary>? index;
  final VoidCallback onArchive;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final totalArticles = index?.fold<int>(0, (a, i) => a + i.articleCount);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.ink, width: 2.5))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('뉴스', style: AppTypography.serif(fontSize: 30, fontWeight: FontWeight.w700, color: AppColors.ink)),
                const SizedBox(height: 3),
                Text(
                  '오늘 많이 언급된 이슈 · 매체 커버리지 순',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Stat(n: totalArticles, label: '전체기사'),
              const SizedBox(width: 14),
              _Stat(n: index?.length, label: '전체이슈'),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_border, color: AppColors.ink),
            onPressed: onArchive,
            tooltip: '저장한 이슈',
          ),
          IconButton(
            icon: const Icon(Icons.person_outline, color: AppColors.ink),
            onPressed: onSettings,
            tooltip: '설정',
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.n, required this.label});

  final int? n;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          n == null ? '–' : '$n',
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: AppColors.accent,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.inkFaint,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

/// 검색창 — "이슈판"과 동일하게 페이지 이동 없이 입력하는 즉시 목록을
/// 걸러냄(별도 검색 화면으로 넘어가는 방식이 느리게 느껴진다는 피드백).
class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.sort,
    required this.onSortChanged,
    required this.onQueryChanged,
  });

  final TextEditingController controller;
  final _SortMode sort;
  final ValueChanged<_SortMode> onSortChanged;
  final ValueChanged<String> onQueryChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.line),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 16, color: AppColors.inkFaint),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onQueryChanged,
                    style: const TextStyle(fontSize: 13, color: AppColors.ink),
                    decoration: InputDecoration(
                      isDense: true,
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: '키워드 또는 헤드라인 검색…',
                      hintStyle: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                    ),
                  ),
                ),
                if (controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      controller.clear();
                      onQueryChanged('');
                    },
                    child: Icon(Icons.close, size: 15, color: AppColors.inkFaint),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _SortButton(label: '매체수', selected: sort == _SortMode.outlet, onTap: () => onSortChanged(_SortMode.outlet)),
              _SortButton(label: '기사수', selected: sort == _SortMode.count, onTap: () => onSortChanged(_SortMode.count)),
            ],
          ),
        ),
      ],
    );
  }
}

class _SortButton extends StatelessWidget {
  const _SortButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? AppColors.bg : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _CategoryBar extends StatelessWidget {
  const _CategoryBar({required this.counts, required this.active, required this.onSelected});

  final Map<String, int> counts;
  final String? active;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final total = counts.values.fold(0, (a, b) => a + b);
    final cats = kCategoryOrder.where((c) => counts.containsKey(c)).toList();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _CategoryChip(label: '전체', count: total, color: AppColors.accent, selected: active == null, onTap: () => onSelected(null)),
        for (final c in cats)
          _CategoryChip(
            label: c,
            count: counts[c]!,
            color: CategoryColors.of(c),
            selected: active == c,
            onTap: () => onSelected(c),
          ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 5, 11, 5),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : AppColors.surface,
          border: Border.all(color: selected ? color : AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? AppColors.ink : AppColors.inkSoft,
              ),
            ),
            const SizedBox(width: 5),
            Text('$count', style: TextStyle(fontSize: 11, color: selected ? color : AppColors.inkFaint)),
          ],
        ),
      ),
    );
  }
}

/// "지속 관심 카테고리" 섹션 — 날씨 카드 + 장기 진행 이슈.
///
/// 지금은 정적 목업임: 날씨는 외부 기상 API 연동이 필요하고, 장기
/// 진행 이슈("D+N일째")는 리프레시 주기마다 이슈 id가 바뀌는 문제 때문에
/// 여러 갱신에 걸친 "같은 이슈" 추적 로직이 아직 없음(사용자와 상의 후
/// 우선순위 낮춰 보류하기로 함 — backend/README.md 알려진 한계 참고).
/// 두 기능 다 백엔드 작업이 더 필요해서, 화면 골격만 먼저 잡아둠.
class _OngoingInterestSection extends StatelessWidget {
  const _OngoingInterestSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        const _WeatherCardPlaceholder(),
        const SizedBox(height: 9),
        const _OngoingIssuePlaceholder(),
      ],
    );
  }
}

class _WeatherCardPlaceholder extends StatelessWidget {
  const _WeatherCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: AppCard(
        radius: 10,
        child: Row(
          children: [
            const Icon(Icons.cloud_outlined, color: AppColors.inkMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '날씨 요약 — 준비 중이에요',
                style: TextStyle(fontSize: 13, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OngoingIssuePlaceholder extends StatelessWidget {
  const _OngoingIssuePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: 0.55,
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        radius: 10,
        child: Row(
          children: [
            const Icon(Icons.bar_chart, size: 18, color: AppColors.inkMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '장기 이슈 추적 — 준비 중이에요',
                style: TextStyle(fontSize: 13, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  const _ErrorRetry({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text('불러오지 못했어요', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 6),
          Text(
            error,
            style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
        ],
      ),
    );
  }
}
