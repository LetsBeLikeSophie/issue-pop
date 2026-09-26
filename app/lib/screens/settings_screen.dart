import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../device_registry.dart';
import '../text_scale_store.dart';
import '../theme.dart';
import '../theme_store.dart';
import '../widgets/app_badge.dart';
import '../widgets/app_bottom_sheet.dart';
import '../widgets/app_card.dart';
import '../widgets/screen_header.dart';

/// 2026-09-05: 계정/구독/의견보내기/앱정보를 전부 뺌 — 로그인은 붙여도
/// 실질적으로 쓸 데가 없었음(즐겨찾기가 이미 비회원으로 잘 동작하고,
/// 서버 동기화도 연결 안 했었음), 구독도 아직 먼 얘기라 화면에서
/// 지웠음. 이제 이 화면엔 실제로 동작하는 알림 설정 + 글자 크기만 남음.
/// 2026-09-26: "앱 정보"에 서비스 중인 언론사 목록만 다시 추가함(계정/
/// 구독처럼 아직 실체 없는 기능이 아니라, 지금 실제로 수집 중인
/// 매체를 사실 그대로 보여주는 거라 위 이유(실질적으로 쓸 데 없음)에
/// 안 걸림).
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final DeviceRegistry _devices = DeviceRegistry(widget.api);
  Future<int?>? _digestHour;
  Future<KeywordAlertSettings>? _keywordAlert;
  Future<bool>? _wordOfDayEnabled;
  late final Future<List<SourceOutlet>> _sources;

  @override
  void initState() {
    super.initState();
    _digestHour = _devices.getDigestHour();
    _keywordAlert = _devices.getKeywordAlert();
    _wordOfDayEnabled = _devices.getWordOfDayAlert();
    _sources = widget.api.getSources();
  }

  /// 2026-09-26: "관심 이슈 알림" — 키워드 등록/삭제는 관심 키워드
  /// 화면에서 이미 하므로, 여기선 그 키워드에 새 이슈가 뜨면 알려줄지
  /// on/off + 조용한 시간대만 다룸(다이제스트 시간 설정과 같은 낙관적
  /// 업데이트 패턴 — 지금까지 알고 있던 값에 변경분만 얹어서 저장).
  Future<void> _updateKeywordAlert(KeywordAlertSettings Function(KeywordAlertSettings) update) async {
    final current = await (_keywordAlert ?? _devices.getKeywordAlert());
    final next = update(current);
    setState(() {
      _keywordAlert = Future.value(next);
    });
    await _devices.setKeywordAlert(next);
  }

  Future<void> _pickKeywordAlertQuietHour({required bool isStart, required int current}) async {
    final picked = await showAppBottomSheet<int>(
      context,
      builder: (context) => _HourPickerSheet(selected: current),
    );
    if (picked == null) return;
    await _updateKeywordAlert((c) => isStart ? c.copyWith(quietStart: picked) : c.copyWith(quietEnd: picked));
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
    final picked = await showAppBottomSheet<int>(
      context,
      builder: (context) => _HourPickerSheet(selected: current),
    );
    if (picked == null) return;
    setState(() {
      _digestHour = Future.value(picked);
    });
    await _devices.setDigestHour(picked);
  }

  /// 2026-09-10: "그럼 뭐가 발송되는데?"를 바로 확인할 수 있게 지금
  /// 이 순간의 다이제스트 텍스트를 바텀시트로 보여줌 — 부수효과 없는
  /// 조회만. 2026-09-20: 실제 발송(FCM)도 서버에 연동 완료됨.
  Future<void> _showDigestPreview() async {
    final preview = widget.api.getDigestPreview();
    await showAppBottomSheet<void>(
      context,
      builder: (_) => _DigestPreviewSheet(preview: preview),
    );
  }

  Future<void> _toggleWordOfDay(bool on) async {
    setState(() {
      _wordOfDayEnabled = Future.value(on);
    });
    await _devices.setWordOfDayAlert(on);
  }

  /// 2026-09-11: 오늘의 단어도 다이제스트와 같은 이유로 미리보기 제공 —
  /// 국립국어원 표준국어대사전 API로 뜻풀이까지 가져옴(dictionary.py).
  /// word_of_day.pick_word()가 애초에 뜻풀이를 못 찾은 단어는 후보에서
  /// 걸러내므로 definition이 null인 경우는 사실상 없음 — 그래도 API
  /// 실패 등 만일을 대비해 시트에서 null 케이스는 안내 문구로 대체함.
  Future<void> _showWordOfDayPreview() async {
    final preview = widget.api.getWordOfDay();
    await showAppBottomSheet<void>(
      context,
      builder: (_) => _WordOfDayPreviewSheet(preview: preview),
    );
  }

  /// 2026-09-22: 카카오페이 "받기" 링크로 후원 — 결제를 앱 안에서 직접
  /// 처리하려면 PG 계약/사업자등록이 필요해서, 1인 개발 단계에선 그냥
  /// 카카오페이 앱으로 넘기는 외부 링크만 엶.
  Future<void> _openDonationLink() async {
    await launchUrl(Uri.parse('https://qr.kakaopay.com/FZBmuUqIr'), mode: LaunchMode.externalApplication);
  }

  /// 2026-09-22: mailto: 링크는 메일 클라이언트가 연결 안 된 기기(특히
  /// 웹)에서 그냥 안 열리는 경우가 많아서, 인앱 폼(POST /feedback)으로
  /// 바꿈 — 앱을 안 벗어나고 바로 보낼 수 있음.
  Future<void> _showContactSheet() async {
    await showAppBottomSheet<void>(
      context,
      isScrollControlled: true,
      builder: (_) => _ContactSheet(
        onSubmit: (message, email) => _devices.submitFeedback(message, contactEmail: email),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 2026-09-26: AppColors.xxx는 static getter라(Theme.of(context) 같은
    // InheritedWidget이 아님) 색 테마를 바꿔도 이미 push돼서 화면에 떠
    // 있는 이 화면은 자동으로 다시 안 그려짐 — main.dart의 루트
    // MaterialApp만 ThemeStore를 구독해서 홈 화면만 즉시 반영되고,
    // 설정 화면 자체(타이틀 포함)는 테마를 바꾸는 바로 그 순간엔 색이
    // 안 바뀐 채로 남아있었음. 화면 최상단에서 직접 구독해서 고침.
    return ListenableBuilder(
      listenable: ThemeStore.instance,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const ScreenHeader(title: '설정'),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
                children: [
                  _SectionLabel('알림'),
                  const SizedBox(height: 8),
                  // 2026-09-26: 세 알림(관심 이슈/매일 트렌드 요약/오늘의
                  // 단어)을 카드 하나에 다 몰아넣었더니 "다 붙어있어서
                  // 헷갈린다"는 피드백 — 서로 발송 시점도 성격도 다른
                  // 별개 기능이라, 카드를 셋으로 나눠서 각자의 경계를
                  // 눈으로 바로 구분할 수 있게 함.
                  //
                  // 관심 이슈 알림 — 관심 키워드 화면에 등록해둔 키워드와
                  // 매칭되는 새 이슈가 뜨면 알림. 다이제스트처럼 "정해진
                  // 시각"이 아니라 뜨는 즉시 오는 알림이라, caption으로
                  // 그 성격을 바로 밝힘.
                  FutureBuilder<KeywordAlertSettings>(
                    future: _keywordAlert,
                    builder: (context, snapshot) {
                      final s = snapshot.data;
                      return AppCard(
                        padding: EdgeInsets.zero,
                        radius: 18,
                        child: Column(
                          children: [
                            _ToggleRow(
                              label: '관심 이슈 알림',
                              caption: '새 소식이 뜨면 바로 알려드려요',
                              value: s?.enabled ?? false,
                              onChanged: s == null
                                  ? null
                                  : (v) => _updateKeywordAlert((c) => c.copyWith(enabled: v)),
                              showDivider: s?.enabled ?? false,
                            ),
                            if (s != null && s.enabled) ...[
                              _PlainRow(
                                label: '조용한 시간대 시작',
                                trailing: _formatHour(s.quietStart),
                                onTap: () => _pickKeywordAlertQuietHour(isStart: true, current: s.quietStart),
                                showDivider: true,
                              ),
                              _PlainRow(
                                label: '조용한 시간대 종료',
                                trailing: _formatHour(s.quietEnd),
                                onTap: () => _pickKeywordAlertQuietHour(isStart: false, current: s.quietEnd),
                                showDivider: false,
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // 매일 트렌드 요약 알림 — 지정한 시각에 하루 한 번.
                  FutureBuilder<int?>(
                    future: _digestHour,
                    builder: (context, snapshot) {
                      final hour = snapshot.data;
                      return AppCard(
                        padding: EdgeInsets.zero,
                        radius: 18,
                        child: Column(
                          children: [
                            _ToggleRow(
                              label: '매일 트렌드 요약 알림',
                              caption: '설정한 시각에 하루 한 번',
                              value: hour != null,
                              onChanged: snapshot.connectionState == ConnectionState.waiting
                                  ? null
                                  : _toggleDigest,
                              showDivider: hour != null,
                            ),
                            if (hour != null)
                              _PlainRow(
                                label: '알림 시간',
                                trailing: _formatHour(hour),
                                onTap: () => _pickDigestHour(hour),
                                showDivider: false,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // 2026-09-11: "오늘의 단어" — 오늘 기사에서 뽑은 어려운
                  // 말 + 예문 + 뜻풀이(국립국어원 API)를 다이제스트와
                  // 별개로 켜고 끌 수 있게 함. 서버 고정 시각(매일 아침
                  // 9시)에 발송.
                  FutureBuilder<bool>(
                    future: _wordOfDayEnabled,
                    builder: (context, snapshot) {
                      return AppCard(
                        padding: EdgeInsets.zero,
                        radius: 18,
                        child: _ToggleRow(
                          label: '오늘의 단어 알림',
                          caption: '매일 아침 9시',
                          value: snapshot.data ?? false,
                          onChanged: snapshot.connectionState == ConnectionState.waiting
                              ? null
                              : _toggleWordOfDay,
                          showDivider: false,
                        ),
                      );
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
                    child: Text(
                      '관심 이슈 알림만 조용한 시간대엔 쉬고, 나머지 둘은 정해진 시각에 나가요.',
                      style: TextStyle(fontSize: 11, color: AppColors.inkFaint),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 16),
                  _SectionLabel('지원'),
                  const SizedBox(height: 8),
                  AppCard(
                    padding: EdgeInsets.zero,
                    radius: 18,
                    child: Column(
                      children: [
                        _PlainRow(
                          label: '커피 한잔 후원하기',
                          onTap: _openDonationLink,
                          showDivider: true,
                        ),
                        _PlainRow(
                          label: '문의하기',
                          onTap: _showContactSheet,
                          showDivider: false,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionLabel('앱 정보'),
                  const SizedBox(height: 8),
                  FutureBuilder<List<SourceOutlet>>(
                    future: _sources,
                    builder: (context, snapshot) {
                      final outlets = snapshot.data ?? const <SourceOutlet>[];
                      return AppCard(
                        radius: 18,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              outlets.isEmpty
                                  ? '여러 언론사의 RSS를 모아 이슈판이 이슈를 정리해요. 기사 원문은 각 언론사에서 직접 확인할 수 있어요.'
                                  : '${outlets.length}개 매체의 RSS를 모아 이슈판이 이슈를 정리해요. 기사 원문은 각 언론사에서 직접 확인할 수 있어요.',
                              style: TextStyle(fontSize: 12.5, color: AppColors.inkSoft, height: 1.5),
                            ),
                            if (outlets.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final o in outlets) AppBadge.outline(label: o.outlet, color: AppColors.inkFaint),
                                ],
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  // 2026-09-26: "발송 내용 미리보기"/"오늘의 단어 미리보기"는
                  // 원래 "실제 발송 전에 뭐가 나가는지 보고 싶다"는 개발
                  // 초기 요청으로 만든 확인용 도구라, 실제 사용자 화면에
                  // 알림 토글이랑 섞여 있으면 헷갈리기만 함 — 웹 빌드
                  // (개발/점검용)에서만 맨 아래로 빼서 보여주고, 실제
                  // 모바일 앱 빌드에서는 아예 안 보이게 함.
                  if (kIsWeb) ...[
                    const SizedBox(height: 16),
                    _SectionLabel('미리보기 (웹 전용)'),
                    const SizedBox(height: 8),
                    AppCard(
                      padding: EdgeInsets.zero,
                      radius: 18,
                      child: Column(
                        children: [
                          _PlainRow(
                            label: '매일 트렌드 요약 미리보기',
                            onTap: _showDigestPreview,
                            showDivider: true,
                          ),
                          _PlainRow(
                            label: '오늘의 단어 미리보기',
                            onTap: _showWordOfDayPreview,
                            showDivider: false,
                          ),
                        ],
                      ),
                    ),
                  ],
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
      child: Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.label,
    this.caption,
    required this.value,
    required this.onChanged,
    required this.showDivider,
  });

  final String label;

  /// 2026-09-26: 알림이 세 개(관심 이슈/매일 트렌드 요약/오늘의 단어)로
  /// 늘면서 "이건 언제 오는 거지"가 헷갈린다는 피드백 — 라벨 아래 작은
  /// 글씨로 발송 시점을 바로 보여줌(관심 이슈: 즉시, 나머지: 정해진 시각).
  final String? caption;
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
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: TextStyle(fontSize: 14, color: AppColors.ink)),
                if (caption != null) ...[
                  const SizedBox(height: 2),
                  Text(caption!, style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
                ],
              ],
            ),
          ),
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
    return AppSheetBody(
      title: '발송 내용 미리보기',
      subtitle: '실제로 지금 보낸다면 이런 내용이 나가요.',
      children: [
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
    );
  }
}

/// 2026-09-11: "오늘의 단어" 미리보기 — 오늘 기사에서 뽑은 단어를 사전
/// 표제어 카드처럼 보여줌. 뜻풀이(definition)는 국립국어원 표준국어대사전
/// API(dictionary.py)로 실제로 가져옴 — word_of_day.pick_word()가 애초에
/// 뜻풀이를 못 찾은 단어는 후보에서 걸러내므로 null인 경우는 사실상 없음.
class _WordOfDayPreviewSheet extends StatelessWidget {
  const _WordOfDayPreviewSheet({required this.preview});

  final Future<WordOfDay> preview;

  @override
  Widget build(BuildContext context) {
    return AppSheetBody(
      title: '오늘의 단어 미리보기',
      subtitle: '오늘 기사 제목에서 뽑은 단어예요. 국립국어원 표준국어대사전 뜻풀이도 함께 보여드려요.',
      children: [
          FutureBuilder<WordOfDay>(
            future: preview,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
                );
              }
              if (snapshot.hasError || snapshot.data?.word == null) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('오늘은 뽑을 만한 단어가 없었어요.', style: TextStyle(fontSize: 12.5, color: AppColors.inkFaint)),
                );
              }
              final data = snapshot.data!;
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.chipBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.word!,
                      style: AppTypography.serif(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      data.definition ?? '이 단어는 사전에서 못 찾았어요.',
                      style: TextStyle(
                        fontSize: 13,
                        color: data.definition == null ? AppColors.inkFaint : AppColors.inkSoft,
                        fontStyle: data.definition == null ? FontStyle.italic : FontStyle.normal,
                        height: 1.4,
                      ),
                    ),
                    if (data.definition != null) ...[
                      const SizedBox(height: 4),
                      // CC BY-SA 2.0 KR 라이선스 조건 — 뜻풀이를 그대로
                      // 인용할 때 출처 표시 필수(가공 없이 인용만 하는
                      // 거라 동일조건변경허락까지는 안 걸림).
                      Text(
                        '출처: 국립국어원 표준국어대사전',
                        style: TextStyle(fontSize: 10, color: AppColors.inkFaint),
                      ),
                    ],
                    if (data.example != null) ...[
                      const SizedBox(height: 10),
                      Text('오늘 기사 예문', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.inkFaint)),
                      const SizedBox(height: 3),
                      Text('“${data.example}”', style: TextStyle(fontSize: 12, color: AppColors.inkSoft, height: 1.4)),
                    ],
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}

/// 2026-09-22: "문의하기" 인앱 폼 — 버그 제보/건의사항을 메시지로 받고,
/// 답장받을 이메일은 선택 입력(직접 답장할 때만 씀, 자동 답장 없음).
/// 서버가 IP당 시간당 5건으로 막아둬서(api.py) 429가 오면 그 안내만
/// 보여줌.
class _ContactSheet extends StatefulWidget {
  const _ContactSheet({required this.onSubmit});

  final Future<void> Function(String message, String? contactEmail) onSubmit;

  @override
  State<_ContactSheet> createState() => _ContactSheetState();
}

class _ContactSheetState extends State<_ContactSheet> {
  final _messageController = TextEditingController();
  final _emailController = TextEditingController();
  bool _sending = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _messageController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final message = _messageController.text.trim();
    if (message.isEmpty) {
      setState(() => _error = '내용을 입력해주세요.');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    final email = _emailController.text.trim();
    try {
      await widget.onSubmit(message, email.isEmpty ? null : email);
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.statusCode == 429 ? '너무 자주 보냈어요, 잠시 후 다시 시도해주세요.' : '전송하지 못했어요. 다시 시도해주세요.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '전송하지 못했어요. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetBody(
      title: '문의하기',
      subtitle: '버그 제보나 하고 싶은 말, 뭐든 남겨주세요.',
      children: [
          if (_sent)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.chipBg, borderRadius: BorderRadius.circular(14)),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: AppColors.accent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('잘 받았어요, 읽어볼게요!', style: TextStyle(fontSize: 13.5, color: AppColors.ink))),
                ],
              ),
            )
          else ...[
            TextField(
              controller: _messageController,
              minLines: 3,
              maxLines: 6,
              style: TextStyle(fontSize: 13.5, color: AppColors.ink),
              decoration: InputDecoration(
                hintText: '예: OO 화면에서 버그가 있어요 / 이런 기능이 있으면 좋겠어요',
                hintStyle: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                filled: true,
                fillColor: AppColors.chipBg,
                contentPadding: const EdgeInsets.all(12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              style: TextStyle(fontSize: 13.5, color: AppColors.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: '답장받을 이메일 (선택)',
                hintStyle: TextStyle(fontSize: 13, color: AppColors.inkFaint),
                filled: true,
                fillColor: AppColors.chipBg,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(fontSize: 12, color: AppColors.accent2)),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _sending ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('보내기'),
              ),
            ),
          ],
      ],
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
