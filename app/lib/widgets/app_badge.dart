import 'package:flutter/material.dart';

import '../theme.dart';

/// 2026-09-25: 배지/pill이 화면마다 사각형(radius 4~5)/알약형(radius
/// 999), 테두리형/채움형이 섞여 있던 걸 "전부 알약형" 기준으로 통일 —
/// 분류(카테고리)는 테두리형, 수치·데이터(등락률·티커·매체 건수)는
/// 채움형 두 변형만 씀. 숫자 배지는 [mono]로 IBM Plex Mono를 쓰게 함
/// (앱 전체의 "숫자는 모노스페이스" 규칙, expandable_issue_card.dart
/// 참고).
class AppBadge extends StatelessWidget {
  const AppBadge.outline({super.key, required this.label, required Color color, this.mono = false})
      : foreground = color,
        borderColor = color,
        background = null;

  const AppBadge.filled({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.mono = false,
  }) : borderColor = null;

  final String label;
  final Color? background;
  final Color foreground;
  final Color? borderColor;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? AppTypography.mono(fontSize: 11, fontWeight: FontWeight.w700, color: foreground)
        : TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: foreground);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        border: borderColor != null ? Border.all(color: borderColor!) : null,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: style),
    );
  }
}
