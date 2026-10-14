import 'dart:async';

import 'package:flutter/material.dart';

import '../theme.dart';

/// 2026-09-25: home_screen(구 _ErrorRetry)/keyword_watch_screen/
/// stock_watch_screen 세 화면이 "불러오지 못했어요 + 에러 텍스트 +
/// 다시 시도 버튼"을 각자 따로 그리고 있어서 하나로 뺌.
class ErrorRetry extends StatefulWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  State<ErrorRetry> createState() => _ErrorRetryState();
}

class _ErrorRetryState extends State<ErrorRetry> {
  Timer? _timer;

  /// 2026-10-14: 서버가 5xx(재시작/갱신 중)를 준 거면 "불러오지 못했어요" + 영어 에러 대신
  /// 서버를 업데이트 중이라고 안내하고, 20초마다 알아서 다시 시도함. ApiException.toString()이
  /// 'ApiException(502): ...' 모양이라 문자열로 구분(이 위젯은 에러를 문자열로만 받음).
  bool get _serverBusy => RegExp(r'^ApiException\(5\d\d\)').hasMatch(widget.error);

  @override
  void initState() {
    super.initState();
    if (_serverBusy) {
      _timer = Timer.periodic(const Duration(seconds: 20), (_) {
        if (mounted) widget.onRetry();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    final onRetry = widget.onRetry;
    if (_serverBusy) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.accent),
              ),
              const SizedBox(height: 14),
              Text('서버를 업데이트하고 있어요', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.ink)),
              const SizedBox(height: 6),
              Text(
                '잠시만 기다려주세요. 끝나면 자동으로 불러올게요.',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('지금 다시 시도')),
            ],
          ),
        ),
      );
    }
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
