import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/app_card.dart';

/// 계정/로그인이 아직 없어서(메모: project_infra_deployment — Firebase/
/// Supabase 붙이기 전까지는 게스트 전용) 이 화면은 대부분 정적 UI임.
/// 알림 토글만 로컬 상태로 동작하고, 로그인/구독 버튼은 "준비 중" 안내만
/// 띄움 — 실제 결제/로그인 흐름을 만들기 전까지는 가짜 성공 동작을
/// 만들지 않는 게 맞다고 판단함.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _issueAlerts = true;

  void _notReady(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature — 아직 준비 중이에요')),
    );
  }

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
                    icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Text('설정', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _notReady('로그인'),
                    child: AppCard(
                      radius: 18,
                      child: Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: const BoxDecoration(color: AppColors.chipBg, shape: BoxShape.circle),
                            child: const Icon(Icons.person_outline, color: AppColors.accent),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('게스트 사용자', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.ink)),
                                SizedBox(height: 2),
                                Text(
                                  '로그인하고 기기 간 저장 기사 동기화',
                                  style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, size: 16, color: AppColors.inkMuted),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('알림'),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: EdgeInsets.zero,
                    radius: 18,
                    child: Column(
                      children: [
                        _ToggleRow(
                          label: '관심 이슈 알림',
                          value: _issueAlerts,
                          onChanged: (v) => setState(() => _issueAlerts = v),
                          showDivider: true,
                        ),
                        _ToggleRow(
                          label: '급상승 키워드 알림',
                          badge: '프리미엄',
                          value: false,
                          onChanged: (_) => _notReady('급상승 키워드 알림'),
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('구독'),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppCard(
                          radius: 18,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('무료', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.inkMuted)),
                              const SizedBox(height: 10),
                              Text(
                                '오늘자 이슈만 조회\n기본 트렌드 보기\n광고 포함',
                                style: TextStyle(fontSize: 11, color: AppColors.inkMuted, height: 1.7),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.accent2Soft,
                            border: Border.all(color: AppColors.accent2, width: 1.5),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('프리미엄', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent2)),
                              const SizedBox(height: 10),
                              Text(
                                '과거 트렌드 히스토리\n매체별 분포 심화\n무제한 알림 · 광고 제거',
                                style: TextStyle(fontSize: 11, color: AppColors.ink.withValues(alpha: 0.75), height: 1.7),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => _notReady('프리미엄 구독'),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(color: AppColors.accent2, borderRadius: BorderRadius.circular(16)),
                      child: const Text(
                        '[월 구독료]에 프리미엄 시작하기',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('기타'),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: EdgeInsets.zero,
                    radius: 18,
                    child: Column(
                      children: [
                        _PlainRow(
                          label: '앱 정보',
                          onTap: () => showAboutDialog(context: context, applicationName: '뉴스 트렌드'),
                          showDivider: true,
                        ),
                        _PlainRow(
                          label: '로그아웃',
                          labelColor: AppColors.accent2,
                          onTap: () => _notReady('로그아웃'),
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(text, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: AppColors.inkMuted)),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.showDivider,
    this.badge,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool showDivider;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: showDivider
          ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider)))
          : null,
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: AppColors.ink)),
          if (badge != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: AppColors.accent2Soft, borderRadius: BorderRadius.circular(8)),
              child: Text(badge!, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.accent2)),
            ),
          ],
          const Spacer(),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.white,
            activeTrackColor: AppColors.accent,
          ),
        ],
      ),
    );
  }
}

class _PlainRow extends StatelessWidget {
  const _PlainRow({required this.label, required this.onTap, required this.showDivider, this.labelColor});

  final String label;
  final VoidCallback onTap;
  final bool showDivider;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: showDivider
            ? const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider)))
            : null,
        child: Text(label, style: TextStyle(fontSize: 14, color: labelColor ?? AppColors.ink)),
      ),
    );
  }
}
