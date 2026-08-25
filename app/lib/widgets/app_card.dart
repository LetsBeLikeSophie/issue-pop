import 'package:flutter/material.dart';
import '../theme.dart';

/// "이슈판" 아티팩트의 카드 스타일(흰 배경 + 옅은 라인 보더 + 살짝 그림자)을
/// 하나로 뺀 것.
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
        boxShadow: AppColors.cardShadow,
      ),
      child: child,
    );
  }
}
