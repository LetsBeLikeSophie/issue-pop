import 'package:flutter/material.dart';

/// design/*.dc.html에서 반복되는 "회전된 알약 배지" 패턴
/// (transform:rotate(...) + border-radius:20px 스티커 느낌).
class StickerBadge extends StatelessWidget {
  const StickerBadge({
    super.key,
    required this.text,
    required this.background,
    this.foreground = Colors.white,
    this.angle = -0.05,
    this.fontSize = 11,
  });

  final String text;
  final Color background;
  final Color foreground;
  final double angle;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: foreground,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
