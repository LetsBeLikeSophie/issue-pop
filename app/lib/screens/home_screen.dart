import 'dart:async';

import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models/issue.dart';
import '../models/reaction.dart';
import '../offline_cache.dart';
import '../presence_service.dart';
import '../reaction_store.dart';
import '../theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_retry.dart';
import '../widgets/expandable_issue_card.dart';
import '../widgets/launch_loading.dart';
import 'onboarding_screen.dart';
import '../widgets/scroll_spotlight.dart';
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

  _SortMode _sort = _SortMode.count;
  final _searchController = TextEditingController();
  String _query = '';

  late final PageController _pageController;
  int _page = 0;

  /// 2026-09-26: 관심 종목/워치에 있던 "맨 위로/아래로" 버튼을 홈
  /// 화면에도 적용 — 페이지(전체/정치/경제/…)마다 스크롤 위치가
  /// 따로라서 _pageSpecs 개수만큼 컨트롤러를 따로 둠(현재 보이는
  /// 페이지의 것만 FAB에 씀).
  late final List<ScrollSpotlightController> _pageSpotlights;

  /// 2026-09-21: 상단바의 "N분 전 업데이트" 표시용. 서버가 30분마다
  /// 재수집하면서 기록해두는 시각을 한 번 받아온 다음, 1분마다
  /// setState만 다시 해서(네트워크 재요청 없이) 상대 시간 문구를
  /// 최신으로 유지함 — 정치성향 필터를 빼면서 비게 된 우측 상단
  /// 자리에 넣음.
  DateTime? _lastRefreshAt;
  Timer? _clockTimer;
  Timer? _retryTimer;

  /// 2026-10-13: 첫 이슈 목록을 받아오는 동안 덮어두는 로딩 화면(LaunchLoading).
  bool _showLaunch = true;

  @override
  void initState() {
    super.initState();
    _trending = widget.api.getTrending(limit: 40);
    _index = widget.api.getIndex()..ignore(); // 카테고리 페이지를 열기 전엔 아무도 안 듣는 future — 실패해도 미처리 예외로 안 남게
    // 성공이든 실패든 첫 응답이 오면 로딩 화면을 걷음(실패는 각 화면의 에러/오프라인 표시가 담당).
    // 너무 빨리 끝나도 깜빡이지 않게 최소 0.5초는 보여줌.
    Future.wait([
      _trending.then<void>((_) {}, onError: (_) {}),
      AppFonts.ready, // 2026-10-18: 글꼴이 다 도착하기 전에 걷으면 글자가 뚝뚝 바뀌어 보임(theme.dart AppFonts)
      Future<void>.delayed(const Duration(milliseconds: 500)),
    ]).then((_) {
      if (mounted) setState(() => _showLaunch = false);
      _maybeShowIntro();
    });
    _pageController = PageController();
    _pageSpotlights = List.generate(_pageSpecs.length, (_) => ScrollSpotlightController());
    widget.api.getLastRefresh().then((t) {
      if (mounted) setState(() => _lastRefreshAt = t);
    }).catchError((_) {});
    _clockTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    // 2026-10-14: 받아둔 데이터를 보여주는 중이면(서버 재시작/네트워크 끊김) 손 안 대도 복구되도록
    // 30초마다 조용히 다시 불러옴. 성공하면 배너가 알아서 사라짐.
    _retryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && OfflineCache.staleSince.value != null) _refresh();
    });
  }

  /// 2026-10-17: 처음 설치했을 때만 짧은 소개를 한 번 보여줌(onboarding_screen.dart).
  Future<void> _maybeShowIntro() async {
    if (!await OnboardingScreen.shouldShow() || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const OnboardingScreen()),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _pageController.dispose();
    for (final s in _pageSpotlights) {
      s.dispose();
    }
    _clockTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _trending = widget.api.getTrending(limit: 40);
      _index = widget.api.getIndex()..ignore();
    });
    ReactionStore.instance.refreshAll();
    try {
      await _trending;
      final t = await widget.api.getLastRefresh();
      if (mounted) setState(() => _lastRefreshAt = t);
    } catch (_) {
      // 실패는 각 FutureBuilder(에러 화면/오프라인 배너)가 이미 보여줌.
    }
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
      floatingActionButton: isSearching ? null : ScrollJumpFab(controller: _pageSpotlights[_page]),
      body: Stack(
        children: [
          SafeArea(
        child: Column(
          children: [
            _TopBar(
              lastRefreshAt: _lastRefreshAt,
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
            ValueListenableBuilder<DateTime?>(
              valueListenable: OfflineCache.staleSince,
              builder: (context, since, _) =>
                  since == null
                      ? const SizedBox.shrink()
                      : ValueListenableBuilder<bool>(
                          valueListenable: OfflineCache.serverBusy,
                          builder: (context, busy, _) => _OfflineBanner(since: since, serverBusy: busy, onRetry: _refresh),
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
                        return ErrorRetry(error: snapshot.error.toString(), onRetry: _refresh);
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
                    for (var i = 0; i < _pageSpecs.length; i++)
                      _CategoryPage(
                        spec: _pageSpecs[i],
                        trending: _trending,
                        index: _index,
                        api: widget.api,
                        sorter: _sorted,
                        onRefresh: _refresh,
                        spotlight: _pageSpotlights[i],
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
          ),
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: _showLaunch
                  ? const LaunchLoading(key: ValueKey('launch'))
                  : const SizedBox.shrink(key: ValueKey('launch-done')),
            ),
          ),
        ],
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
    required this.spotlight,
  });

  final _PageSpec spec;
  final Future<List<IssueDetail>> trending;
  final Future<List<IssueSummary>> index;
  final ApiClient api;
  final List<T> Function<T extends IssueSummary>(List<T>) sorter;
  final Future<void> Function() onRefresh;
  final ScrollSpotlightController spotlight;

  @override
  Widget build(BuildContext context) {
    final categories = spec.categories;
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        controller: spotlight.scrollController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const SwipeHintRow('카드를 왼쪽으로 밀면 저장할 수 있어요'),
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
                  return ErrorRetry(error: snapshot.error.toString(), onRetry: onRefresh);
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
                  return ErrorRetry(error: snapshot.error.toString(), onRetry: onRefresh);
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

/// 2026-10-13: 서버/네트워크 문제로 새 데이터를 못 받아서 기기에 남겨둔 마지막
/// 데이터를 대신 보여주는 중일 때만 뜨는 안내(OfflineCache 참고).
class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner({required this.since, required this.serverBusy, required this.onRetry});

  final DateTime since;

  /// 서버가 재시작/갱신 중이라 못 받은 거면 true(OfflineCache.serverBusy).
  final bool serverBusy;
  final Future<void> Function() onRetry;

  String _ago() {
    final m = DateTime.now().difference(since).inMinutes;
    if (m < 1) return '방금';
    if (m < 60) return '$m분 전';
    if (m < 60 * 24) return '${m ~/ 60}시간 전';
    return '${m ~/ (60 * 24)}일 전';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.accent2Soft,
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      child: Row(
        children: [
          Icon(serverBusy ? Icons.sync : Icons.cloud_off, size: 15, color: AppColors.accent2),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              serverBusy
                  ? '서버를 업데이트하고 있어요 · ${_ago()} 받아둔 이슈를 보여드려요'
                  : '연결이 안 돼요 · ${_ago()} 받아둔 이슈를 보여드려요',
              style: TextStyle(fontSize: 11.5, color: AppColors.ink),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text('다시 시도', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.accent2)),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.lastRefreshAt,
    required this.onStocks,
    required this.onKeywords,
    required this.onShare,
    required this.onArchive,
    required this.onSettings,
  });

  final DateTime? lastRefreshAt;
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
            // 2026-09-26: "Pop" 뒤에 형광펜으로 칠한 것 같은 하이라이트
            // 블록을 넣어달라는 요청 — 두 단어를 하나의 Text로 두면 배경색을
            // 글자 하나만 따로 칠할 수 없어서 Wrap으로 쪼갬. 예전엔 좁은
            // 화면에서 "Issue"가 한 단어라 줄바꿈도 못 하고 넘쳤던 버그가
            // 있었는데(2026-09-09), Wrap은 자간 단위로 알아서 다음 줄로
            // 넘어가므로 그 문제도 같이 해결됨(대신 문자 단위로 잘리는
            // ellipsis 안전장치는 없어짐 — "Issue Pop" 정도 길이면 필요
            // 없다고 판단).
            //
            // 2026-10-18: 글자 크기를 키우면 로고가 "Issu / e / Pop"으로 줄바꿈되던 문제(실기기 캡처) — 로고는 글자가 아니라 브랜드
            // 마크라서 글자 크기 설정의 영향을 안 받게 하고(withNoTextScaling), 그래도 자리가 모자라면(좁은 화면 + 아이콘 5개) 줄바꿈 대신
            // 통째로 줄어들게(FittedBox scaleDown) 함. 그래서 Wrap → Row.
            child: MediaQuery.withNoTextScaling(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.bottomLeft,
                child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Issue ',
                  style: AppTypography.serif(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink),
                ),
                Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    // 2026-09-26: 처음엔 글자 전체 높이를 박스로 감쌌더니
                    // "형광펜"이라기보다 그냥 배지처럼 보인다는 피드백 —
                    // 실제 형광펜처럼 글자 아래쪽 절반 정도만 칠하게
                    // Stack+FractionallySizedBox로 바꿈(하이라이트 높이가
                    // Text 높이의 절반만 차지, 아래쪽 정렬).
                    Positioned.fill(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: 0.5,
                          widthFactor: 1,
                          child: ColoredBox(color: const Color(0xFFF4C94E)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      child: Text(
                        'Pop',
                        style: AppTypography.serif(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ),
                  ],
                ),
              ],
            ),
              ),
            ),
          ),
          // 2026-09-09: 아이콘이 3개→5개로 늘면서(관심 워치/공유 추가)
          // 좁은 화면에서 타이틀이 밀려 넘치는 문제가 있었음 — 기본
          // IconButton은 48px 최소 탭 영역을 잡는데, 이 5개를 다 그렇게
          // 두기엔 자리가 부족해서 각각 살짝 좁힘(터치 자체는 여전히 넉넉함).
          //
          // 2026-09-21: 정치성향 필터를 빼면서 비게 된 자리에 "N분 전
          // 업데이트" 표시를 넣음 — 서버가 30분마다 재수집하는 걸 사용자가
          // 알 방법이 없었어서.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.15,
            child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 2026-10-13: 서버가 "최근 10분간 최소 3명 이상"이라고 확인해준 경우에만 보임
                  // (숫자를 부풀리거나 지어내지 않음 — PresenceService 참고).
                  ValueListenableBuilder<Presence?>(
                    valueListenable: PresenceService.instance.state,
                    builder: (context, presence, _) {
                      if (presence == null || !presence.show) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: const BoxDecoration(color: Color(0xFF2E9E6B), shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '최근 ${presence.windowMinutes}분 ${presence.online}명',
                              style: TextStyle(fontSize: 10.5, color: AppColors.inkFaint),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  _LastRefreshLabel(at: lastRefreshAt),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                    tooltip: '관심 키워드',
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
            ],
          ),
          ),
        ],
      ),
    );
  }
}

/// 2026-09-21: "N분 전 업데이트" — 서버가 30분마다 재수집하는 걸 사용자가
/// 알 방법이 없어서 추가함. 평소엔 무채색으로 조용히 있다가, 갱신
/// 주기(30분)의 3배(90분)를 넘도록 안 바뀌면 뭔가 잘못됐다는 뜻이라
/// accent2(경고 톤으로 이미 쓰던 색)로 눈에 띄게 함 — 새 색을 안 만들고
/// 기존 "삭제/취소" 등에 쓰던 색을 재사용.
class _LastRefreshLabel extends StatelessWidget {
  const _LastRefreshLabel({required this.at});

  final DateTime? at;

  static const _staleAfter = Duration(minutes: 90);

  @override
  Widget build(BuildContext context) {
    if (at == null) return const SizedBox(height: 14);
    final elapsed = DateTime.now().difference(at!);
    final text = elapsed.inMinutes < 1
        ? '방금 업데이트'
        : elapsed.inMinutes < 60
            ? '${elapsed.inMinutes}분 전 업데이트'
            : '${elapsed.inHours}시간 전 업데이트';
    final stale = elapsed > _staleAfter;
    return Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        color: stale ? AppColors.accent2 : AppColors.inkFaint,
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
        Row(
          children: [
            _SortButton(label: '매체수', selected: sort == _SortMode.outlet, onTap: () => onSortChanged(_SortMode.outlet)),
            const SizedBox(width: 10),
            _SortButton(label: '기사수', selected: sort == _SortMode.count, onTap: () => onSortChanged(_SortMode.count)),
          ],
        ),
      ],
    );
  }
}

/// 2026-09-20: "클린 뉴스룸" 톤 리디자인 — 채워진 알약 토글 대신
/// 텍스트 + 밑줄(선택된 것만)로 바꿈.
class _SortButton extends StatelessWidget {
  const _SortButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Container(
          padding: const EdgeInsets.only(bottom: 1),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: selected ? AppColors.ink : Colors.transparent, width: 1.5)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? AppColors.ink : AppColors.inkFaint,
            ),
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
            if (i != 0) const SizedBox(width: 16),
            _PageTabChip(
              label: specs[i].label,
              selected: active == i,
              onTap: () => onSelected(i),
            ),
          ],
        ],
      ),
    );
  }
}

/// 2026-09-20: "클린 뉴스룸" 톤 리디자인 — 카테고리별 원색 점 대신
/// BBC/Reuters류 텍스트 탭(선택된 탭만 굵게)으로 바꿈.
/// 2026-09-25: 밑줄 인디케이터가 굳이 없어도 굵기·색 대비만으로 선택
/// 상태가 충분히 구분된다는 피드백으로 밑줄을 뺌.
class _PageTabChip extends StatelessWidget {
  const _PageTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.ink : AppColors.inkFaint,
          ),
        ),
      ),
    );
  }
}

