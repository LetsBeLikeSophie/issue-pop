import 'package:flutter/material.dart';

import '../theme.dart';

/// 2026-09-25: archive_screen/keyword_watch_screen/stock_watch_screen
/// 세 화면이 "아이콘 + 제목 + 설명" 빈 상태 레이아웃을 문구만 바꿔서
/// 각자 그리고 있어서 하나로 뺌.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.subtitle});

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: AppColors.inkFaint),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(color: AppColors.inkMuted, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.inkFaint, fontSize: 11.5, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// 2026-09-25: home_screen(구 _SwipeHint)/archive_screen이 "카드를
/// 왼쪽으로 밀면 ~할 수 있어요" 힌트 줄을 각자 그리고 있어서 하나로 뺌.
class SwipeHintRow extends StatelessWidget {
  const SwipeHintRow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.swipe_left_outlined, size: 12, color: AppColors.inkFaint),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
      ],
    );
  }
}
