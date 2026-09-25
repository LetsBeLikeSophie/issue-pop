import 'package:flutter/material.dart';

import '../theme.dart';

/// 2026-09-25: home_screen(구 _ErrorRetry)/keyword_watch_screen/
/// stock_watch_screen 세 화면이 "불러오지 못했어요 + 에러 텍스트 +
/// 다시 시도 버튼"을 각자 따로 그리고 있어서 하나로 뺌.
class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('불러오지 못했어요', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
            const SizedBox(height: 6),
            Text(error, style: TextStyle(fontSize: 12, color: AppColors.inkMuted), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}
