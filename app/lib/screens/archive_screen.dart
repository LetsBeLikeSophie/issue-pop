import 'package:flutter/material.dart';

import '../favorites_store.dart';
import '../theme_store.dart';
import '../widgets/empty_state.dart';
import '../widgets/expandable_issue_card.dart';
import '../widgets/screen_header.dart';

/// 2026-08-28: FavoritesStore가 ChangeNotifier 싱글턴으로 바뀌면서
/// FutureBuilder+수동 새로고침(_reload) 구조를 걷어냄 — 이제 그냥
/// ListenableBuilder로 구독하면 즐겨찾기가 어디서 바뀌든(이 화면 안의
/// 스와이프-삭제든, 홈 화면의 스와이프-저장이든) 항상 최신 목록이 보임.
class ArchiveScreen extends StatelessWidget {
  const ArchiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // 2026-09-26: AppColors.xxx는 그냥 static getter라(Theme.of(context)
    // 같은 InheritedWidget이 아님) 색 테마를 바꿔도 이미 Navigator로
    // 밀어둔(=지금 화면처럼 push된) 화면은 자동으로 다시 안 그려짐 —
    // main.dart의 루트 MaterialApp만 ThemeStore를 구독하고 있어서 홈
    // 화면만 즉시 반영되고, 그 위에 push된 화면(저장한 이슈/설정/관심
    // 종목/관심 워치)은 테마를 바꾸는 그 순간 화면에 떠 있으면 색이 안
    // 바뀐 채로 남아있었음("설정 타이틀이 안 보인다"는 버그의 원인).
    // 화면 최상단에서 직접 구독해서 고침.
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: '저장한 이슈'),
            Expanded(
              child: ListenableBuilder(
                listenable: FavoritesStore.instance,
                builder: (context, _) {
                  final items = FavoritesStore.instance.all;
                  if (items.isEmpty) {
                    return const EmptyState(
                      icon: Icons.swipe_left_outlined,
                      title: '아직 저장한 이슈가 없어요',
                      subtitle: '홈 화면에서 이슈 카드를 왼쪽으로 밀면 저장할 수 있어요',
                    );
                  }
                  final maxOutlet =
                      items.map((i) => i.issue.outletCount).reduce((a, b) => a > b ? a : b);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10),
                        child: SwipeHintRow('카드를 왼쪽으로 밀면 삭제할 수 있어요'),
                      ),
                      for (var i = 0; i < items.length; i++) ...[
                        ExpandableIssueCard(
                          key: ValueKey(items[i].issue.id),
                          issue: items[i].issue,
                          maxOutletCount: maxOutlet,
                          subtitle: '저장일 ${items[i].savedAt.month}월 ${items[i].savedAt.day}일',
                          archiveMode: true,
                        ),
                        if (i != items.length - 1) const SizedBox(height: 8),
                      ],
                    ],
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
