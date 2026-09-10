import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/issue.dart';
import '../theme.dart';
import '../widgets/expandable_issue_card.dart';
import '../widgets/share_card.dart';
import 'archive_screen.dart';
import 'keyword_watch_screen.dart';
import 'settings_screen.dart';
import 'stock_watch_screen.dart';

enum _SortMode { outlet, count }

/// 2026-09-02: 카테고리 필터(같은 목록을 다시 걸러 보여주기)에서
/// 실제 "페이지"(제스처로 옆으로 넘기면 완전히 다른 화면)로 바꿈 —
/// 애초에 "신문처럼 페이지가 늘어나는" 컨셉이었고, 카드 스와이프 저장도
/// 쓰는 앱이라 제스처 내비게이션 방향이 잘 맞는다는 의견.
///
/// 2026-09-02~04: 살림/재테크/문화생활/IT 같은 "큐레이션 페이지"를
/// 여기 붙였다 뺐다 하며 여러 형태(탭바 안에 섞기 → 상단바 아이콘 →
/// 매거진 캐러셀)로 시도했는데, 결국 "이 앱은 뉴스 클러스터링 하나에
/// 집중하고, 그런 잡지형 큐레이션은 나중에 완전히 별도 앱으로 빼는 게
/// 낫겠다"는 결론으로 정리함 — 그래서 이 파일엔 순수 카테고리 필터만
/// 남음. 큐레이션 쪽 코드는 필요해지면 새 프로젝트에서 처음부터 다시
/// 설계하는 게 나을 것 같아 여기서는 완전히 제거함.
class _PageSpec {
  const _PageSpec(this.label, this.categories);

  /// 탭/페이지 표시 이름.
  final String label;

  /// 이 페이지가 보여줄 카테고리 집합. null이면 "전체"(모든 이슈,
  /// _trending의 풍부한 데이터 그대로 씀). 빈 값 없는 Set이면 그
  /// 카테고리(들)만 클라이언트에서 걸러서 보여줌.
  final Set<String>? categories;

  /// 탭 점 색깔 — "전체"는 accent, 나머지는 그 카테고리 고유 색.
  Color get color => categories == null ? AppColors.accent : CategoryColors.of(categories!.first);
}

final List<_PageSpec> _pageSpecs = [
  const _PageSpec('전체', null),
  const _PageSpec('정치', {'정치'}),
  const _PageSpec('경제', {'경제'}),
  const _PageSpec('사회', {'사회'}),
  const _PageSpec('국제', {'국제'}),
  const _PageSpec('스포츠', {'스포츠'}),
  const _PageSpec('연예', {'연예'}),
  const _PageSpec('IT/과학', {'IT/과학'}),
  const _PageSpec('문화', {'문화'}),
  const _PageSpec('기타', {'기타'}),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<IssueDetail>> _trending;

  /// 검색·카테고리 페이지용 — 이슈 전체를 요약(기사 목록 제외)만 한 번
  /// 받아서 클라이언트가 들고 있음. 페이지 전환은 이 데이터를 그때그때
  /// 걸러서 보여주는 거라 네트워크 왕복이 없음(검색과 같은 패턴).
  late Future<List<IssueSummary>> _index;

  _SortMode _sort = _SortMode.outlet;
  final _searchController = TextEditingController();
  String _query = '';

  late final PageController _pageController;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _trending = widget.api.getTrending(limit: 40);
    _index = widget.api.getIndex();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _trending = widget.api.getTrending(limit: 40);
      _index = widget.api.getIndex();
    });
    await _trending;
  }

  void _goToPage(int i) {
    _pageController.animateToPage(i, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  List<IssueSummary> _search(List<IssueSummary> pool) {
    final q = _query.toLowerCase();
    return pool
        .where((i) =>
            i.keyword.toLowerCase().contains(q) ||
            i.keywords.any((k) => k.toLowerCase().contains(q)) ||
            i.representativeTitle.toLowerCase().contains(q))
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
            _TopBar(
              onStocks: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => StockWatchScreen(api: widget.api)),
              ),
              onKeywords: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => KeywordWatchScreen(api: widget.api)),
              ),
              onShare: () async {
                final issues = await _trending;
                if (!context.mounted) return;
                await shareTodayTrend(context, issues);
              },
              onArchive: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ArchiveScreen()),
              ),
              onSettings: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => SettingsScreen(api: widget.api)),
              ),
            ),
            if (!isSearching)
              Padding(
                key: const ValueKey('pageTabBar'),
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: _PageTabBar(
                  specs: _pageSpecs,
                  active: _page,
                  onSelected: _goToPage,
                ),
              ),
            // 2026-09-10: 검색어를 입력하면 isSearching이 true가 되면서
            // 바로 위 카테고리 탭바가 트리에서 사라지는데, 그러면 이
            // Toolbar(검색창 포함)가 Column의 children 목록에서 한 칸
            // 앞으로 밀림 — Key 없이는 Flutter가 "그 자리"에 있던 이전
            // 위젯(카테고리 탭바)과 타입이 달라서 이 Toolbar를 완전히 새로
            // 마운트해버림. 그 바람에 TextField가 통째로 재생성되면서
            // 포커스/커서/IME 조합 상태가 다 날아가서 "ㄱ" 치자마자 커서가
            // 밖으로 나가고 "가"가 "ㄱㅏ"로 따로 놀던 버그였음. Key로
            // 이 Toolbar가 위치와 무관하게 "같은 위젯"임을 알려줘서 고침.
            Padding(
              key: const ValueKey('toolbar'),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: _Toolbar(
                controller: _searchController,
                sort: _sort,
                onSortChanged: (m) => setState(() => _sort = m),
                onQueryChanged: (q) => setState(() => _query = q),
              ),
            ),
            if (isSearching)
              Expanded(
                key: const ValueKey('searchResults'),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  child: FutureBuilder<List<IssueSummary>>(
                    future: _index,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return _ErrorRetry(error: snapshot.error.toString(), onRetry: _refresh);
                      }
                      final issues = _sorted(_search(snapshot.data ?? []));
                      return ListView(
                        children: [
                          _IssueList(
                            issues: issues,
                            api: widget.api,
                            showRank: false,
                            emptyText: '검색 결과가 없어요',
                          ),
                        ],
                      );
                    },
                  ),
                ),
              )
            else ...[
              const SizedBox(height: 6, key: ValueKey('pageViewGap')),
              Expanded(
                key: const ValueKey('pageView'),
                child: PageView(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    for (final spec in _pageSpecs)
                      _CategoryPage(
                        spec: spec,
                        trending: _trending,
                        index: _index,
                        api: widget.api,
                        sorter: _sorted,
                        onRefresh: _refresh,
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 카테고리 페이지 하나(전체/정치/경제/…)의 본문 — 필터링된 이슈
/// 목록을 보여줌. "전체"(spec.categories == null)는 _trending(풍부한
/// 데이터, 즉시 펼침)을 그대로 쓰고, 나머지는 _index를 클라이언트에서
/// 걸러서 씀(검색과 같은 패턴 — 페이지 전환마다 네트워크를 안 타서
/// 즉각적임).
class _CategoryPage extends StatelessWidget {
  const _CategoryPage({
    required this.spec,
    required this.trending,
    required this.index,
    required this.api,
    required this.sorter,
    required this.onRefresh,
  });

  final _PageSpec spec;
  final Future<List<IssueDetail>> trending;
  final Future<List<IssueSummary>> index;
  final ApiClient api;
  final List<T> Function<T extends IssueSummary>(List<T>) sorter;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final categories = spec.categories;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const _SwipeHint(),
          const SizedBox(height: 6),
          if (categories == null)
            FutureBuilder<List<IssueDetail>>(
              future: trending,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _ErrorRetry(error: snapshot.error.toString(), onRetry: onRefresh);
                }
                final issues = sorter<IssueDetail>(snapshot.data ?? []);
                return _IssueList(
                  issues: issues,
                  api: null,
                  showRank: true,
                  emptyText: '아직 집계된 이슈가 없어요',
                );
              },
            )
          else
            FutureBuilder<List<IssueSummary>>(
              future: index,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return _ErrorRetry(error: snapshot.error.toString(), onRetry: onRefresh);
                }
                final filtered = (snapshot.data ?? []).where((i) => categories.contains(i.category)).toList();
                final issues = sorter(filtered);
                return _IssueList(
                  issues: issues,
                  api: api,
                  showRank: false,
                  emptyText: '이 페이지엔 아직 이슈가 없어요',
                );
              },
            ),
        ],
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

/// 카드를 옆으로 밀면 저장할 수 있다는 걸 몰라보는 사람이 있다는
/// 피드백을 받고 추가한 짧은 안내 문구.
class _SwipeHint extends StatelessWidget {
  const _SwipeHint();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.swipe_left_outlined, size: 12, color: AppColors.inkFaint),
        const SizedBox(width: 4),
        Text('카드를 왼쪽으로 밀면 저장할 수 있어요', style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onStocks,
    required this.onKeywords,
    required this.onShare,
    required this.onArchive,
    required this.onSettings,
  });

  final VoidCallback onStocks;
  final VoidCallback onKeywords;
  final VoidCallback onShare;
  final VoidCallback onArchive;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.ink, width: 2.5))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              'Issue Pop',
              // 2026-09-09: 좁은 화면 + 아이콘 5개 조합에서 "Issue"가 한
              // 단어라 줄바꿈으로도 못 줄여서(RenderFlex overflow) 이슈
              // 카드/카테고리까지 밀려버리는 버그가 있었음 — 두 줄까지는
              // 허용하되(사용자가 "두 줄 정도는 괜찮다"고 함), 그래도 안
              // 들어가면 잘라서 절대 넘치지 않게 함.
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.serif(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
          ),
          // 2026-09-09: 아이콘이 3개→5개로 늘면서(관심 워치/공유 추가)
          // 좁은 화면에서 타이틀이 밀려 넘치는 문제가 있었음 — 기본
          // IconButton은 48px 최소 탭 영역을 잡는데, 이 5개를 다 그렇게
          // 두기엔 자리가 부족해서 각각 살짝 좁힘(터치 자체는 여전히 넉넉함).
          IconButton(
            icon: Icon(Icons.show_chart, color: AppColors.ink),
            onPressed: onStocks,
            tooltip: '관심 종목',
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: Icon(Icons.person_search, color: AppColors.ink),
            onPressed: onKeywords,
            tooltip: '관심 워치',
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: Icon(Icons.ios_share, color: AppColors.ink),
            onPressed: onShare,
            tooltip: '오늘의 트렌드 공유',
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: Icon(Icons.bookmark_border, color: AppColors.ink),
            onPressed: onArchive,
            tooltip: '저장한 이슈',
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(),
          ),
          IconButton(
            icon: Icon(Icons.person_outline, color: AppColors.ink),
            onPressed: onSettings,
            tooltip: '설정',
            padding: const EdgeInsets.symmetric(horizontal: 4),
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

/// 검색창 — "이슈판"과 동일하게 페이지 이동 없이 입력하는 즉시 목록을
/// 걸러냄(별도 검색 화면으로 넘어가는 방식이 느리게 느껴진다는 피드백).
/// 검색 중엔 페이지 탭 대신 전체에서 걸러서 보여줌.
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
                    style: TextStyle(fontSize: 13, color: AppColors.ink),
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

/// 2026-09-01: 9개 카테고리 + 전체가 Wrap으로 2~3줄까지 줄바꿈되던 걸
/// 한 줄 가로 스크롤로 바꿨었음. 2026-09-02: 탭을 누르면 그냥 필터링만
/// 하던 걸 실제 페이지 전환(PageView)으로 바꿈.
class _PageTabBar extends StatelessWidget {
  const _PageTabBar({required this.specs, required this.active, required this.onSelected});

  final List<_PageSpec> specs;
  final int active;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < specs.length; i++) ...[
            if (i != 0) const SizedBox(width: 6),
            _PageTabChip(
              label: specs[i].label,
              color: specs[i].color,
              selected: active == i,
              onTap: () => onSelected(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _PageTabChip extends StatelessWidget {
  const _PageTabChip({
    required this.label,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
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
