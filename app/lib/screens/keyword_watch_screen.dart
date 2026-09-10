import 'package:flutter/material.dart';

import '../api_client.dart';
import '../device_registry.dart';
import '../models/issue.dart';
import '../theme.dart';
import '../widgets/expandable_issue_card.dart';

/// 2026-09-08: 관심 인물·키워드 워치. 원래 DeviceKeywordWatch는 다이제스트
/// 알림 대상을 고르는 용도로만 쓰였는데(설정 화면 안에 묻혀있었음), 관심
/// 종목 화면을 실제로 써보니 "등록해두면 그 대상 관련 뉴스를 바로 훑어볼 수
/// 있는" 패턴 자체가 좋아서 키워드 워치도 같은 패턴으로 만듦 —
/// stock_watch_screen.dart와 거의 동일한 화면 구조(칩+섹션별 목록).
///
/// 관심종목과 다른 점: 종목은 매체별 RSS를 서버에서 새로 받아와야 하지만,
/// 키워드는 이미 홈 화면이 들고 있는 전체 이슈 인덱스(GET /index)를 그대로
/// 클라이언트에서 필터링하면 되므로 새 백엔드 엔드포인트가 필요 없음(홈
/// 화면 검색과 같은 방식). 매칭된 이슈는 요약(IssueSummary)만 있으므로
/// ExpandableIssueCard가 펼칠 때 알아서 상세를 받아옴(검색 결과와 동일).
class KeywordWatchScreen extends StatefulWidget {
  const KeywordWatchScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<KeywordWatchScreen> createState() => _KeywordWatchScreenState();
}

class _KeywordWatchScreenState extends State<KeywordWatchScreen> {
  late final DeviceRegistry _devices = DeviceRegistry(widget.api);
  Future<List<KeywordWatch>>? _watches;
  late final Future<List<IssueSummary>> _index;

  final _scrollController = ScrollController();
  bool _showScrollTop = false;
  final Map<String, GlobalKey> _cardKeys = {};

  void _scrollToKeyword(String keyword) {
    final ctx = _cardKeys[keyword]?.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.05);
  }

  void _scrollToTop() {
    _scrollController.animateTo(0, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  void initState() {
    super.initState();
    _watches = _devices.listWatches();
    _index = widget.api.getIndex();
    _scrollController.addListener(() {
      final show = _scrollController.offset > 300;
      if (show != _showScrollTop) setState(() => _showScrollTop = show);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _watches = _devices.listWatches();
    });
    await _watches;
  }

  Future<void> _removeKeyword(int watchId) async {
    await _devices.deleteWatch(watchId);
    await _refresh();
  }

  Future<void> _showAddSheet() async {
    final current = (await _watches)?.map((w) => w.keyword).toSet() ?? <String>{};
    if (!mounted) return;
    final index = await _index;
    if (!mounted) return;
    final keyword = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      isScrollControlled: true,
      builder: (_) => _KeywordAddSheet(index: index, currentKeywords: current),
    );
    if (keyword == null) return;
    await _devices.addWatch(keyword);
    await _refresh();
  }

  /// 홈 화면 검색(_HomeScreenState._search)과 같은 매칭 기준 — 대표
  /// 키워드, 보조 키워드, 대표 기사 제목 중 하나라도 포함하면 매치.
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
      floatingActionButton: _showScrollTop
          ? FloatingActionButton.small(
              onPressed: _scrollToTop,
              backgroundColor: AppColors.ink,
              tooltip: '맨 위로',
              child: const Icon(Icons.arrow_upward, color: Colors.white, size: 18),
            )
          : null,
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
                    child: Text('관심 워치', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
                  ),
                  TextButton.icon(
                    onPressed: _showAddSheet,
                    icon: Icon(Icons.add, size: 16, color: AppColors.accent),
                    label: Text(
                      '키워드 추가',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.accent),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder<List<KeywordWatch>>(
                future: _watches,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('불러오지 못했어요', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
                            const SizedBox(height: 6),
                            Text(
                              '${snapshot.error}',
                              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(onPressed: _refresh, child: const Text('다시 시도')),
                          ],
                        ),
                      ),
                    );
                  }

                  final watches = snapshot.data ?? [];
                  if (watches.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_search, size: 28, color: AppColors.inkFaint),
                            const SizedBox(height: 10),
                            Text(
                              '아직 등록된 워치가 없어요',
                              style: TextStyle(color: AppColors.inkMuted, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '위 "키워드 추가"로 관심 있는 인물이나 키워드를 등록해보세요',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.inkFaint, fontSize: 11.5, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  for (final w in watches) {
                    _cardKeys.putIfAbsent(w.keyword, () => GlobalKey());
                  }

                  return FutureBuilder<List<IssueSummary>>(
                    future: _index,
                    builder: (context, indexSnapshot) {
                      if (indexSnapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                      }
                      final index = indexSnapshot.data ?? const [];
                      final maxOutlet = index.isEmpty ? 1 : index.map((i) => i.outletCount).reduce((a, b) => a > b ? a : b);

                      return RefreshIndicator(
                        onRefresh: _refresh,
                        child: SingleChildScrollView(
                          // 관심종목 화면과 같은 이유(스크롤로 이동한 항목이
                          // ListView 가상화로 언마운트되며 GlobalKey가 깨지는
                          // 문제)로 여기도 ListView 대신 이 위젯을 씀.
                          controller: _scrollController,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final w in watches)
                                    _KeywordChip(
                                      label: w.keyword,
                                      onTap: () => _scrollToKeyword(w.keyword),
                                      onRemove: () => _removeKeyword(w.id),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              for (final w in watches) ...[
                                _KeywordSection(
                                  key: _cardKeys[w.keyword],
                                  keyword: w.keyword,
                                  issues: _matches(index, w.keyword),
                                  api: widget.api,
                                  maxOutletCount: maxOutlet,
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
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

class _KeywordChip extends StatelessWidget {
  const _KeywordChip({required this.label, required this.onTap, required this.onRemove});

  final String label;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 5, 6, 5),
      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
                  const SizedBox(width: 2),
                  Icon(Icons.arrow_downward, size: 10, color: AppColors.accent.withValues(alpha: 0.6)),
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

class _KeywordSection extends StatelessWidget {
  const _KeywordSection({
    super.key,
    required this.keyword,
    required this.issues,
    required this.api,
    required this.maxOutletCount,
  });

  final String keyword;
  final List<IssueSummary> issues;
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
              Text(
                '$keyword · 관련 이슈 ${issues.length}건',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkSoft, letterSpacing: 0.3),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        if (issues.isEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text('아직 관련 이슈가 없어요', style: TextStyle(fontSize: 11.5, color: AppColors.inkFaint)),
          )
        else
          for (final issue in issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ExpandableIssueCard(
                key: ValueKey(issue.id),
                issue: issue,
                api: api,
                maxOutletCount: maxOutletCount,
              ),
            ),
      ],
    );
  }
}

/// 키워드 추가 바텀시트 — 종목과 달리 정해진 카탈로그가 없으므로 자유
/// 텍스트 입력이 기본이고, 검색어가 비어있을 때는 현재 인덱스에서 매체
/// 커버리지 상위 키워드를 "인기 검색어"처럼 미리보기로 보여줌(관심종목
/// 화면의 "인기 종목" 미리보기와 같은 패턴 — 2026-09-06 피드백대로).
class _KeywordAddSheet extends StatefulWidget {
  const _KeywordAddSheet({required this.index, required this.currentKeywords});

  final List<IssueSummary> index;
  final Set<String> currentKeywords;

  @override
  State<_KeywordAddSheet> createState() => _KeywordAddSheetState();
}

class _KeywordAddSheetState extends State<_KeywordAddSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit([String? keyword]) {
    final value = (keyword ?? _controller.text).trim();
    if (value.isEmpty) return;
    Navigator.of(context).pop(value);
  }

  List<String> _visible() {
    final sorted = [...widget.index]..sort((a, b) => b.outletCount.compareTo(a.outletCount));
    final pool = <String>[];
    final seen = <String>{};
    for (final i in sorted) {
      if (widget.currentKeywords.contains(i.keyword) || seen.contains(i.keyword)) continue;
      seen.add(i.keyword);
      pool.add(i.keyword);
    }
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return pool.take(8).toList();
    return pool.where((k) => k.toLowerCase().contains(q)).take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final matches = _visible();
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('키워드 추가', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text('인물, 기관, 키워드 등 무엇이든 등록할 수 있어요 (예: 이재명, 삼성전자)',
              style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  onSubmitted: (_) => _submit(),
                  style: TextStyle(fontSize: 14, color: AppColors.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '키워드 입력',
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
          if (matches.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              _query.trim().isEmpty ? '오늘 많이 보도된 키워드' : '검색 결과',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.inkFaint, letterSpacing: 0.3),
            ),
            const SizedBox(height: 6),
            Container(
              constraints: const BoxConstraints(maxHeight: 240),
              decoration: BoxDecoration(color: AppColors.chipBg, borderRadius: BorderRadius.circular(10)),
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: matches.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: AppColors.divider),
                itemBuilder: (context, i) {
                  final k = matches[i];
                  return InkWell(
                    onTap: () => _submit(k),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      child: Text(k, style: TextStyle(fontSize: 13, color: AppColors.ink)),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
