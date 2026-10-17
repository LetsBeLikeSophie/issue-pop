import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/issue.dart';
import '../models/reaction.dart';
import '../theme.dart';
import '../widgets/expandable_issue_card.dart';

/// 2026-10-17: 처음 설치했을 때 한 번만 보여주는 짧은 소개(3장, 건너뛰기 가능). 권한(알림)은 여기서 묻지 않음 —
/// 알림이 필요한 순간에 따로 설명함(notification_gate.dart). 이미 쓰던 사람(기기 등록이 돼 있는 경우)은 업데이트로
/// 소개가 뜨지 않게 조용히 "본 것"으로 처리함.
///
/// 2026-10-18: 글만 있으면 "같은 이슈는 한 장으로" 같은 말이 와닿지 않는다는 피드백으로, 가운데 아이콘 대신 앱 화면을
/// 그대로 작게 그려 넣음 — 스크린샷 이미지가 아니라 실제 앱 위젯(이슈 카드 등)을 샘플 데이터로 그리는 방식이라 어떤
/// 화면 크기/색 테마에서도 선명하고, 앱 디자인이 바뀌면 같이 바뀜(낡은 캡처가 안 남음).
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
  const _Page(this.title, this.body, this.art);

  final String title;
  final String body;
  final Widget Function() art;
}

final _pages = <_Page>[
  _Page(
    '오늘의 이슈를 한눈에',
    '여러 언론사의 뉴스를 이슈별로 묶어서\n지금 가장 많이 다뤄지는 이야기부터 보여드려요.',
    () => const _IssueCardArt(),
  ),
  _Page(
    '관심 있는 것만 골라서',
    '관심 키워드를 등록하면\n새 이슈가 뜰 때 알림으로 알려드려요.',
    () => const _KeywordAlertArt(),
  ),
  _Page(
    '저장하고, 반응하고',
    '카드를 왼쪽으로 밀어서 저장하고,\n이모티콘으로 내 반응을 남겨보세요.',
    () => const _SaveReactArt(),
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
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 그림은 누를 수 없는 설명용 — 카드를 눌러 펼쳐지는 등의 동작이 안 일어나게.
          IgnorePointer(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: page.art(),
            ),
          ),
          const SizedBox(height: 30),
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

// ---------------------------------------------------------------------------------------------
// 1장: 실제 이슈 카드(샘플 데이터)
// ---------------------------------------------------------------------------------------------

final _sampleIssue = IssueDetail.fromJson({
  'id': 'sample',
  'keyword': '기준금리',
  'keywords': ['기준금리', '동결'],
  'category': '경제',
  'representative_title': '기준금리 동결 두고 엇갈린 전망…"연내 인하 가능성 열어둬"',
  'article_count': 24,
  'outlet_count': 8,
  'first_seen_at': null,
  'trend': null,
  'trend_delta': null,
  'outlets': [
    for (final o in ['연합뉴스', '한겨레', '경향신문', '매일경제', '머니투데이', 'SBS', '동아일보', '서울신문'])
      {'outlet': o, 'count': 3},
  ],
  'articles': <Map<String, dynamic>>[],
});

class _IssueCardArt extends StatelessWidget {
  const _IssueCardArt();

  @override
  Widget build(BuildContext context) {
    // 뒤에 한 장 더 깔아서 "이슈 카드가 여러 장 쌓여 있는 목록" 느낌.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: 10,
          right: 10,
          bottom: -10,
          child: Container(
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.line),
            ),
          ),
        ),
        ExpandableIssueCard(issue: _sampleIssue, rank: 1, maxOutletCount: 8, archiveMode: true),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// 2장: 관심 키워드 칩 + 알림 모양
// ---------------------------------------------------------------------------------------------

class _KeywordAlertArt extends StatelessWidget {
  const _KeywordAlertArt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in ['금리', '반도체', '환율', '총선'])
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(999)),
                child: Text(k, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.accent)),
              ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
                child: Text('I', style: AppTypography.serif(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("'금리' 새 이슈가 떴어요",
                        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                    const SizedBox(height: 3),
                    Text('기준금리 동결 두고 엇갈린 전망…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft)),
                  ],
                ),
              ),
              Text('지금', style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------------------------
// 3장: 밀어서 저장 + 반응 고르기
// ---------------------------------------------------------------------------------------------

class _SaveReactArt extends StatelessWidget {
  const _SaveReactArt();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 왼쪽으로 밀린 카드 뒤에 "저장" 칸이 드러난 모양.
        SizedBox(
          height: 78,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 18),
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.bookmark, size: 22, color: Colors.white),
                      SizedBox(height: 3),
                      Text('저장', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 70,
                top: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.line),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('기준금리', style: AppTypography.serif(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
                      const SizedBox(height: 6),
                      Container(height: 6, width: 110, decoration: _bar()),
                      const SizedBox(height: 6),
                      Container(height: 6, width: 70, decoration: _bar()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // 실제 반응 팝업과 같은 모양(reaction_button.dart).
        Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2, bottom: 8),
                child: Text('이 소식에 대한 내 반응', style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
              ),
              Row(
                children: [
                  for (final kind in kReactionKinds)
                    Expanded(
                      child: Column(
                        children: [
                          Icon(kind.icon, size: 24, color: kind.key == 'curious' ? AppColors.accent : AppColors.inkSoft),
                          const SizedBox(height: 3),
                          Text(
                            kind.label,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: kind.key == 'curious' ? FontWeight.w700 : FontWeight.w500,
                              color: kind.key == 'curious' ? AppColors.accent : AppColors.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  BoxDecoration _bar() => BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(3));
}
