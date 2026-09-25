import 'package:flutter/material.dart';

import '../favorites_store.dart';
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
