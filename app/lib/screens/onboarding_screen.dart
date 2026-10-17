import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme.dart';

/// 2026-10-17: 처음 설치했을 때 한 번만 보여주는 짧은 소개(3장, 건너뛰기 가능). 권한(알림)은 여기서 묻지 않음 —
/// 알림이 필요한 순간에 따로 설명함(notification_gate.dart). 이미 쓰던 사람(기기 등록이 돼 있는 경우)은 업데이트로
/// 소개가 뜨지 않게 조용히 "본 것"으로 처리함.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  static const _seenKey = 'onboarding_seen_v1';
  static const _deviceIdKey = 'device_id_v1'; // device_registry.dart의 _idKey

  /// 소개를 보여줘야 하는 첫 설치인지. 이미 봤거나 이미 쓰던 기기면 false.
  static Future<bool> shouldShow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_seenKey) == true) return false;
      if (prefs.containsKey(_deviceIdKey)) {
        await prefs.setBool(_seenKey, true);
        return false;
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      await (await SharedPreferences.getInstance()).setBool(_seenKey, true);
    } catch (_) {}
  }

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _Page {
  const _Page(this.icon, this.title, this.body);

  final IconData icon;
  final String title;
  final String body;
}

const _pages = <_Page>[
  _Page(
    Icons.layers_outlined,
    '같은 이슈는 한 장으로',
    '여러 언론사가 다룬 이슈를 한 카드로 묶어서,\n오늘 무엇이 가장 많이 보도됐는지 한눈에 보여드려요.',
  ),
  _Page(
    Icons.tune,
    '관심 있는 것만 골라서',
    '관심 키워드와 종목을 설정하면\n새 이슈를 알림으로 받아볼 수 있어요.',
  ),
  _Page(
    Icons.bookmark_border,
    '저장하고, 반응하고',
    '카드를 왼쪽으로 밀어서 저장하고,\n이모티콘으로 내 반응을 남겨보세요.',
  ),
];

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await OnboardingScreen.markSeen();
    if (mounted) Navigator.of(context).pop();
  }

  void _next() {
    if (_index >= _pages.length - 1) {
      _finish();
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 240), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return PopScope(
      canPop: false, // 뒤로가기로 그냥 닫히면 "본 것"으로 기록이 안 남음 — 건너뛰기/시작하기로만 닫음
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _finish();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
                  child: TextButton(
                    onPressed: _finish,
                    child: Text('건너뛰기', style: TextStyle(color: AppColors.inkFaint, fontSize: 13)),
                  ),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) => _PageView(page: _pages[i]),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _index ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _index ? AppColors.accent : AppColors.line,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: _next,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(last ? '시작하기' : '다음', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PageView extends StatelessWidget {
  const _PageView({required this.page});

  final _Page page;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(color: AppColors.accentSoft, shape: BoxShape.circle),
            child: Icon(page.icon, size: 42, color: AppColors.accent),
          ),
          const SizedBox(height: 28),
          Text(
            page.title,
            textAlign: TextAlign.center,
            style: AppTypography.serif(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 12),
          Text(
            page.body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.6, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}
