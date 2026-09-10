import 'package:flutter/material.dart';

import '../api_client.dart';
import '../device_registry.dart';
import '../text_scale_store.dart';
import '../theme.dart';
import '../theme_store.dart';
import '../widgets/app_card.dart';

/// 2026-09-05: 계정/구독/의견보내기/앱정보를 전부 뺌 — 로그인은 붙여도
/// 실질적으로 쓸 데가 없었음(즐겨찾기가 이미 비회원으로 잘 동작하고,
/// 서버 동기화도 연결 안 했었음), 구독도 아직 먼 얘기라 화면에서
/// 지웠음. 이제 이 화면엔 실제로 동작하는 알림 설정 + 글자 크기만 남음.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _issueAlerts = true;
  late final DeviceRegistry _devices = DeviceRegistry(widget.api);
  Future<int?>? _digestHour;
  Future<AlertSettings>? _alertSettings;
  Future<List<KeywordWatch>>? _watches;
  final _keywordController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _digestHour = _devices.getDigestHour();
    _alertSettings = _devices.getAlertSettings();
    _watches = _devices.listWatches();
  }

  @override
  void dispose() {
    _keywordController.dispose();
    super.dispose();
  }

  /// 설정 하나를 바꿀 때마다 지금까지 알고 있던 값에 그 변경만 얹어서
  /// 저장함(PUT이 전체 필드를 요구해서). 다이제스트 시간과 같은
  /// 낙관적 업데이트 패턴 — 화면은 먼저 바뀌고, 저장은 뒤이어 함.
  Future<void> _updateAlertSettings(AlertSettings Function(AlertSettings) update) async {
    final current = await (_alertSettings ?? _devices.getAlertSettings());
    final next = update(current);
    setState(() {
      _alertSettings = Future.value(next);
    });
    await _devices.setAlertSettings(next);
  }

  Future<void> _addKeyword() async {
    final keyword = _keywordController.text.trim();
    if (keyword.isEmpty) return;
    _keywordController.clear();
    await _devices.addWatch(keyword);
    setState(() {
      _watches = _devices.listWatches();
    });
  }

  Future<void> _removeKeyword(int watchId) async {
    await _devices.deleteWatch(watchId);
    setState(() {
      _watches = _devices.listWatches();
    });
  }

  Future<void> _toggleDigest(bool on) async {
    final hour = on ? 9 : null; // 켜면 기본 오전 9시로 시작
    // 화살표 본문은 대입식의 값(Future 자체)을 그대로 반환해서 "setState()
    // callback argument returned a Future" 오류가 남 — 필드는 바뀌지만
    // 정작 다시 그리라는 표시가 예외로 중단돼서 화면이 안 갱신됨
    // (archive_screen.dart _reload에서 발견한 것과 같은 버그, 블록
    // 본문으로 고침).
    setState(() {
      _digestHour = Future.value(hour);
    });
    await _devices.setDigestHour(hour);
  }

  Future<void> _pickDigestHour(int current) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => _HourPickerSheet(selected: current),
    );
    if (picked == null) return;
    setState(() {
      _digestHour = Future.value(picked);
    });
    await _devices.setDigestHour(picked);
  }

  /// 2026-09-10: 실제 발송은 아직 안 붙었지만(서비스 계정 키 필요),
  /// "그럼 뭐가 발송되는데?"를 바로 확인할 수 있게 지금 이 순간의
  /// 다이제스트 텍스트를 바텀시트로 보여줌 — 부수효과 없는 조회만.
  Future<void> _showDigestPreview() async {
    final preview = widget.api.getDigestPreview();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => _DigestPreviewSheet(preview: preview),
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
                    icon: Icon(Icons.arrow_back_ios_new, size: 18, color: AppColors.ink),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Text('설정', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.ink)),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                children: [
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
                        FutureBuilder<int?>(
                          future: _digestHour,
                          builder: (context, snapshot) {
                            final hour = snapshot.data;
                            return _ToggleRow(
                              label: '매일 트렌드 요약 알림',
                              value: hour != null,
                              onChanged: snapshot.connectionState == ConnectionState.waiting
                                  ? null
                                  : _toggleDigest,
                              showDivider: hour != null,
                            );
                          },
                        ),
                        FutureBuilder<int?>(
                          future: _digestHour,
                          builder: (context, snapshot) {
                            final hour = snapshot.data;
                            if (hour == null) return const SizedBox.shrink();
                            return _PlainRow(
                              label: '알림 시간',
                              trailing: _formatHour(hour),
                              onTap: () => _pickDigestHour(hour),
                              showDivider: true,
                            );
                          },
                        ),
                        _PlainRow(
                          label: '발송 내용 미리보기',
                          onTap: _showDigestPreview,
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                    child: Text(
                      '실제 발송(푸시)은 아직 준비 중이에요 — 위 미리보기는 지금 보낸다면 어떤 내용이 나갈지만 보여줘요.',
                      style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('실시간 트렌드 알림'),
                  const SizedBox(height: 8),
                  FutureBuilder<AlertSettings>(
                    future: _alertSettings,
                    builder: (context, snapshot) {
                      final s = snapshot.data;
                      if (s == null) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                        );
                      }
                      return AppCard(
                        radius: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _ToggleRow(
                              label: '새 이슈 · 급상승 알림',
                              value: s.enabled,
                              onChanged: (v) => _updateAlertSettings((c) => c.copyWith(enabled: v)),
                              showDivider: false,
                            ),
                            if (s.enabled) ...[
                              const SizedBox(height: 14),
                              Text('체크 주기', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                              const SizedBox(height: 6),
                              _SegmentRow<int>(
                                options: const [30, 60, 120, 180],
                                labels: const ['30분', '1시간', '2시간', '3시간'],
                                selected: s.intervalMinutes,
                                onSelected: (v) => _updateAlertSettings((c) => c.copyWith(intervalMinutes: v)),
                              ),
                              const SizedBox(height: 14),
                              Text('조용한 시간대 (이 시간에만 알림)', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: _QuietHourButton(
                                      label: '시작',
                                      hour: s.quietHoursStart,
                                      onTap: () async {
                                        final picked = await showModalBottomSheet<int>(
                                          context: context,
                                          backgroundColor: AppColors.surface,
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                          ),
                                          builder: (context) => _HourPickerSheet(selected: s.quietHoursStart),
                                        );
                                        if (picked != null) {
                                          _updateAlertSettings((c) => c.copyWith(quietHoursStart: picked));
                                        }
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: _QuietHourButton(
                                      label: '종료',
                                      hour: s.quietHoursEnd,
                                      onTap: () async {
                                        final picked = await showModalBottomSheet<int>(
                                          context: context,
                                          backgroundColor: AppColors.surface,
                                          shape: const RoundedRectangleBorder(
                                            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                          ),
                                          builder: (context) => _HourPickerSheet(selected: s.quietHoursEnd),
                                        );
                                        if (picked != null) {
                                          _updateAlertSettings((c) => c.copyWith(quietHoursEnd: picked));
                                        }
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text('최소 매체 수 (이 이상 보도된 이슈만)', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                              const SizedBox(height: 6),
                              _SegmentRow<int>(
                                options: const [3, 5, 7, 10],
                                labels: const ['3개', '5개', '7개', '10개'],
                                selected: s.minOutletCount,
                                onSelected: (v) => _updateAlertSettings((c) => c.copyWith(minOutletCount: v)),
                              ),
                              const SizedBox(height: 14),
                              Text('하루 최대 알림', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                              const SizedBox(height: 6),
                              _SegmentRow<int>(
                                options: const [5, 10, 20, 999],
                                labels: const ['5개', '10개', '20개', '무제한'],
                                selected: s.maxDailyAlerts,
                                onSelected: (v) => _updateAlertSettings((c) => c.copyWith(maxDailyAlerts: v)),
                              ),
                              const SizedBox(height: 14),
                              Text('관심 카테고리 (안 고르면 전체)', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                              const SizedBox(height: 6),
                              _CategoryFilterChips(
                                selected: s.categories,
                                onChanged: (cats) => _updateAlertSettings((c) => c.copyWith(categories: cats)),
                              ),
                              const SizedBox(height: 14),
                              Text('관심 키워드', style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted)),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _keywordController,
                                      onSubmitted: (_) => _addKeyword(),
                                      style: TextStyle(fontSize: 13, color: AppColors.ink),
                                      decoration: InputDecoration(
                                        isDense: true,
                                        hintText: '예: 삼성전자',
                                        hintStyle: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                                        filled: true,
                                        fillColor: AppColors.chipBg,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: _addKeyword,
                                    icon: Icon(Icons.add_circle, color: AppColors.accent),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              FutureBuilder<List<KeywordWatch>>(
                                future: _watches,
                                builder: (context, wsnap) {
                                  final watches = wsnap.data ?? [];
                                  if (watches.isEmpty) {
                                    return Text('등록된 키워드가 없어요', style: TextStyle(fontSize: 12, color: AppColors.inkFaint));
                                  }
                                  return Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final w in watches)
                                        _KeywordChip(label: w.keyword, onRemove: () => _removeKeyword(w.id)),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                    child: Text(
                      '설정 저장까지만 준비됐고, 실제 감지/발송은 아직 준비 중이에요.',
                      style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SectionLabel('화면'),
                  const SizedBox(height: 8),
                  AppCard(
                    radius: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('글자 크기', style: TextStyle(fontSize: 14, color: AppColors.ink)),
                        const SizedBox(height: 10),
                        ListenableBuilder(
                          listenable: TextScaleStore.instance,
                          builder: (context, _) {
                            final current = TextScaleStore.instance.scale;
                            return Row(
                              children: [
                                for (var i = 0; i < TextScaleStore.steps.length; i++) ...[
                                  if (i != 0) const SizedBox(width: 6),
                                  Expanded(
                                    child: _TextScaleButton(
                                      label: TextScaleStore.labels[i],
                                      selected: current == TextScaleStore.steps[i],
                                      onTap: () => TextScaleStore.instance.setScale(TextScaleStore.steps[i]),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  AppCard(
                    radius: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('색 테마', style: TextStyle(fontSize: 14, color: AppColors.ink)),
                        const SizedBox(height: 10),
                        ListenableBuilder(
                          listenable: ThemeStore.instance,
                          builder: (context, _) {
                            final current = ThemeStore.instance.preset;
                            return Row(
                              children: [
                                for (var i = 0; i < ColorPreset.values.length; i++) ...[
                                  if (i != 0) const SizedBox(width: 6),
                                  Expanded(
                                    child: _ThemePresetButton(
                                      preset: ColorPreset.values[i],
                                      selected: current == ColorPreset.values[i],
                                      onTap: () => ThemeStore.instance.setPreset(ColorPreset.values[i]),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          },
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
  });

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: showDivider
          ? BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider)))
          : null,
      child: Row(
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: AppColors.ink)),
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

class _TextScaleButton extends StatelessWidget {
  const _TextScaleButton({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.chipBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

/// 2026-09-09: 색 테마 프리셋 버튼 — 라벨만으론 어떤 색인지 안 보여서
/// 그 프리셋의 실제 bg/accent/accent2를 작은 스와치로 미리 보여줌
/// (AppColors.previewColors — 지금 선택된 프리셋이 아니라 버튼이 나타내는
/// 프리셋 자체의 색을 조회함).
class _ThemePresetButton extends StatelessWidget {
  const _ThemePresetButton({required this.preset, required this.selected, required this.onTap});

  final ColorPreset preset;
  final bool selected;
  final VoidCallback onTap;

  static const _labels = {
    ColorPreset.current: '기본',
    ColorPreset.neutral: '화이트',
    ColorPreset.dark: '다크',
  };

  @override
  Widget build(BuildContext context) {
    final (bg, accent, accent2) = AppColors.previewColors(preset);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.chipBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.accent : Colors.transparent, width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: selected ? Colors.white : AppColors.line, width: 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                  const SizedBox(width: 2),
                  Container(width: 6, height: 6, decoration: BoxDecoration(color: accent2, shape: BoxShape.circle)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _labels[preset]!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : AppColors.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 여러 값 중 하나를 고르는 가로 세그먼트 — 체크 주기/최소 매체 수/
/// 하루 최대 알림 셋 다 같은 모양이라 제네릭으로 하나만 둠.
class _SegmentRow<T> extends StatelessWidget {
  const _SegmentRow({
    required this.options,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<T> options;
  final List<String> labels;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i != 0) const SizedBox(width: 6),
          Expanded(
            child: _TextScaleButton(
              label: labels[i],
              selected: selected == options[i],
              onTap: () => onSelected(options[i]),
            ),
          ),
        ],
      ],
    );
  }
}

class _QuietHourButton extends StatelessWidget {
  const _QuietHourButton({required this.label, required this.hour, required this.onTap});

  final String label;
  final int hour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        decoration: BoxDecoration(color: AppColors.chipBg, borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 12, color: AppColors.inkFaint)),
            Text(_formatHour(hour), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}

/// 관심 카테고리 다중 선택 — "전체"(null)와 개별 카테고리 칩. 하나라도
/// 개별 카테고리를 고르면 "전체"는 자동으로 꺼짐(그 반대도 마찬가지).
class _CategoryFilterChips extends StatelessWidget {
  const _CategoryFilterChips({required this.selected, required this.onChanged});

  final List<String>? selected;
  final ValueChanged<List<String>?> onChanged;

  @override
  Widget build(BuildContext context) {
    final isAll = selected == null;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _FilterChip(label: '전체', color: AppColors.accent, selected: isAll, onTap: () => onChanged(null)),
        for (final c in kCategoryOrder)
          _FilterChip(
            label: c,
            color: CategoryColors.of(c),
            selected: !isAll && selected!.contains(c),
            onTap: () {
              final current = selected ?? [];
              final next = current.contains(c) ? (current.toList()..remove(c)) : [...current, c];
              onChanged(next.isEmpty ? null : next);
            },
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.color, required this.selected, required this.onTap});

  final String label;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : AppColors.surface,
          border: Border.all(color: selected ? color : AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? AppColors.ink : AppColors.inkSoft,
          ),
        ),
      ),
    );
  }
}

class _KeywordChip extends StatelessWidget {
  const _KeywordChip({required this.label, required this.onRemove});

  final String label;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
      decoration: BoxDecoration(color: AppColors.accentSoft, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent)),
          const SizedBox(width: 2),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onRemove,
            child: Icon(Icons.close, size: 14, color: AppColors.accent),
          ),
        ],
      ),
    );
  }
}

class _PlainRow extends StatelessWidget {
  const _PlainRow({
    required this.label,
    required this.onTap,
    required this.showDivider,
    this.trailing,
  });

  final String label;
  final VoidCallback onTap;
  final bool showDivider;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: showDivider
            ? BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider)))
            : null,
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 14, color: AppColors.ink))),
            if (trailing != null)
              Text(trailing!, style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            if (trailing != null) const SizedBox(width: 4),
            if (trailing != null) Icon(Icons.chevron_right, size: 16, color: AppColors.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// 2026-08-26: 그냥 오전/오후로만 나누면 "오전 1시"/"오후 1시"처럼 둘 다
/// "1시"가 나와서 헷갈린다는 피드백을 받음 — 한국어에서 새벽 시간대는
/// "오전"이라고 잘 안 하고 "새벽"이라고 하는 게 자연스러움(일기예보의
/// 새벽/오전/오후/저녁 4구간 표기와 동일하게 맞춤).
String _formatHour(int hour) {
  if (hour == 0) return '자정';
  if (hour == 12) return '정오';
  if (hour < 6) return '새벽 $hour시';
  if (hour < 12) return '오전 $hour시';
  if (hour < 18) return '오후 ${hour - 12}시';
  return '저녁 ${hour - 12}시';
}

/// 2026-09-10: "발송 기능이 아직 없는데 그럼 뭐가 발송되는지 보고 싶다"는
/// 요청으로 추가 — 실제 푸시처럼 보이게 알림 배너 흉내를 낸 카드 안에
/// GET /digest/preview가 지금 이 순간 만들어내는 텍스트를 그대로 보여줌.
/// 실제 발송(FCM)과는 무관한 조회 전용이라 기기 목록을 건드리거나
/// last_digest_sent_at을 바꾸지 않음.
class _DigestPreviewSheet extends StatelessWidget {
  const _DigestPreviewSheet({required this.preview});

  final Future<String> preview;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('발송 내용 미리보기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.ink)),
          const SizedBox(height: 4),
          Text(
            '실제로 지금 보낸다면 이런 내용이 나가요. 발송 자체는 아직 준비 중이에요.',
            style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
          ),
          const SizedBox(height: 16),
          FutureBuilder<String>(
            future: preview,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                );
              }
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('불러오지 못했어요: ${snapshot.error}', style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint)),
                );
              }
              final lines = snapshot.data!.split('\n');
              final title = lines.first;
              final body = lines.skip(1).join('\n');
              // 실제 안드로이드/iOS 알림 배너와 비슷한 느낌으로 —
              // 앱 아이콘 자리 + 제목 + 본문. 진짜 시스템 알림은 아니고
              // 어떤 텍스트가 들어가는지 보여주는 목업임.
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.newspaper, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  title,
                                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: AppColors.ink),
                                ),
                              ),
                              Text('지금', style: TextStyle(fontSize: 10.5, color: AppColors.inkFaint)),
                            ],
                          ),
                          if (body.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(body, style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.4)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// 다이제스트 알림 시간을 고르는 바텀시트 — 백엔드가 시(0~23) 단위까지만
/// 받으니(분 단위 아님) 기본 Material 시간 선택기 대신 시간만 고르는
/// 목록으로 만듦(안 그러면 "9시 30분"을 골라도 30분이 조용히 버려져서
/// 헷갈릴 수 있음).
class _HourPickerSheet extends StatelessWidget {
  const _HourPickerSheet({required this.selected});

  final int selected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: 360,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                '알림 시간 선택',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.ink),
              ),
            ),
            Divider(height: 1, color: AppColors.divider),
            Expanded(
              child: ListView.builder(
                itemCount: 24,
                itemBuilder: (context, hour) {
                  final isSelected = hour == selected;
                  return ListTile(
                    title: Text(
                      _formatHour(hour),
                      style: TextStyle(
                        fontSize: 14,
                        color: isSelected ? AppColors.accent : AppColors.ink,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    trailing: isSelected ? Icon(Icons.check, size: 18, color: AppColors.accent) : null,
                    onTap: () => Navigator.of(context).pop(hour),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
