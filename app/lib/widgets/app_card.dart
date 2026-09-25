import 'package:flutter/material.dart';
import '../theme.dart';

/// "이슈판" 아티팩트의 카드 스타일(흰 배경 + 옅은 라인 보더)을 하나로 뺀 것.
///
/// 2026-09-25: 그림자를 뺌 — 2026-09-20 "클린 뉴스룸" 리디자인 때
/// expandable_issue_card.dart(홈/저장한 이슈/관심 워치가 쓰는 이슈
/// 카드)는 그림자 대신 라인으로만 카드를 구분하게 바꿨는데, 이 위젯을
/// 쓰는 설정·관심 종목 카드는 그림자를 그대로 들고 있어서 화면마다
/// 카드 톤이 미묘하게 달랐음(홈은 납작한데 설정만 살짝 떠 보임).
/// 앱 전체를 라인 기반 톤 하나로 통일.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 10,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.line),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}
