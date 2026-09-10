import 'package:flutter/material.dart';

import '../favorites_store.dart';
import '../theme.dart';
import '../widgets/expandable_issue_card.dart';

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
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text(
                    '저장한 이슈',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: FavoritesStore.instance,
                builder: (context, _) {
                  final items = FavoritesStore.instance.all;
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swipe_left_outlined, size: 28, color: AppColors.inkFaint),
                            const SizedBox(height: 10),
                            Text(
                              '아직 저장한 이슈가 없어요',
                              style: TextStyle(color: AppColors.inkMuted, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '홈 화면에서 이슈 카드를 왼쪽으로 밀면 저장할 수 있어요',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.inkFaint, fontSize: 11.5, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                    );
                  }
                  final maxOutlet =
                      items.map((i) => i.issue.outletCount).reduce((a, b) => a > b ? a : b);
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 24),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Icon(Icons.swipe_left_outlined, size: 12, color: AppColors.inkFaint),
                            const SizedBox(width: 4),
                            Text('카드를 왼쪽으로 밀면 삭제할 수 있어요', style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
                          ],
                        ),
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
