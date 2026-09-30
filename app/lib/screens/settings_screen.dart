import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../device_registry.dart';
import '../push_token.dart';
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

class _SettingsScreenState extends State<SettingsScreen> with WidgetsBindingObserver {
  late final DeviceRegistry _devices = DeviceRegistry(widget.api);
  Future<DigestSettings>? _digest;
  Future<KeywordAlertSettings>? _keywordAlert;
  Future<WordOfDayAlertSettings>? _wordOfDayAlert;
  late final Future<List<SourceOutlet>> _sources;

  /// 2026-09-28: OS 알림 권한은 앱이 통제할 수 없는 시점에 바뀔 수 있음
  /// (사용자가 기기 설정으로 나가서 껐다 켰다 할 수 있음) — 그래서 앱을
  /// 다시 시작해야만 반영되는 대신, 화면이 "다시 보일 때마다"(포그라운드
  /// 복귀 시점, didChangeAppLifecycleState의 resumed) 매번 다시 조회함.
  /// 이건 순수 로컬 조회라(getNotificationSettings()는 기기 OS 상태를
  /// 그냥 읽어오는 것 — 서버 왕복 전혀 없음) 매번 다시 불러도 비용이
  /// 없음. null=아직 확인 전, true=거부됨(토글 비활성화), false=허용됨.
  bool? _notificationsDenied;
  AuthorizationStatus? _lastKnownNotificationStatus;

  /// 2026-09-27: 캐시가 없는 첫 실행에서는 토글들이 네트워크 왕복 후에야
  /// 뜨는 통에 화면이 잠깐 비어 보이다 툭 튀어나오는 느낌이 있었음 —
  /// 설정값이 다 준비된 다음에 화면을 그리게 함(로컬 캐시가 있으면
  /// 이 Future가 사실상 즉시 끝나서 체감상 로딩이 안 보임).
  late final Future<void> _initialLoad;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _digest = _devices.getDigest();
    _keywordAlert = _devices.getKeywordAlert();
    _wordOfDayAlert = _devices.getWordOfDayAlert();
    _sources = widget.api.getSources();
    _initialLoad = Future.wait([_digest!, _keywordAlert!, _wordOfDayAlert!]);
    // 2026-09-27: getNotificationSettings()를 곧바로 부르면, 첫 실행 때는
    // OS 권한 다이얼로그(디바이스 등록 체인 안에서 요청됨)에 사용자가
    // 아직 답하기 전 상태를 그대로 읽어버림 — "허용"을 눌러도 배너가 계속
    // "거부됨"으로 남아있던 버그. _initialLoad가 끝난 뒤에 체크하면 그
    // 안에서 이미 권한 요청까지 다 끝난 뒤라 실제 답변이 반영된 상태를 읽음.
    _initialLoad.then((_) => _refreshNotificationStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 2026-09-28: 사용자가 배너를 보고 기기 설정으로 나가서 권한을 켠 뒤
  /// 이 화면으로 돌아오면(resumed), 재실행 없이 바로 반영되게 함.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshNotificationStatus();
    }
  }

  Future<void> _refreshNotificationStatus() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (!mounted) return;
    setState(() {
      _lastKnownNotificationStatus = settings.authorizationStatus;
      _notificationsDenied = settings.authorizationStatus == AuthorizationStatus.denied;
    });
  }

  /// 2026-09-26: "관심 이슈 알림" — 키워드 등록/삭제는 관심 키워드
  /// 화면에서 이미 하므로, 여기선 그 키워드에 새 이슈가 뜨면 알려줄지
  /// on/off + 조용한 시간대만 다룸(다이제스트 시간 설정과 같은 낙관적
  /// 업데이트 패턴 — 지금까지 알고 있던 값에 변경분만 얹어서 저장).
  Future<KeywordAlertSettings> _updateKeywordAlert(
    KeywordAlertSettings Function(KeywordAlertSettings) update,
  ) async {
    final current = await (_keywordAlert ?? _devices.getKeywordAlert());
    final next = update(current);
    setState(() {
      _keywordAlert = Future.value(next);
    });
    await _devices.setKeywordAlert(next);
    return next;
  }

  Future<void> _pickKeywordAlertQuietHour({required bool isStart, required int current}) async {
    final picked = await showAppBottomSheet<int>(
      context,
      builder: (context) => _HourPickerSheet(selected: current),
    );
    if (picked == null) return;
    final next = await _updateKeywordAlert(
      (c) => isStart ? c.copyWith(quietStart: picked) : c.copyWith(quietEnd: picked),
    );
    // 2026-09-27: 시작=종료로 맞추면 "알림 금지 시간대 없음(항상 허용)"과
    // 같은 뜻인데, 그 상태를 그냥 두면 헷갈리니 아예 관심 키워드 토글
    // 자체를 꺼서 시간대 선택 UI도 같이 접히게 함(카드에 남는 안내 문구
    // 대신 토스트 한 번으로 알려줌).
    if (next.quietStart == next.quietEnd) {
      await _updateKeywordAlert((c) => c.copyWith(enabled: false));
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Center(child: Text('시작·종료가 같아서 관심 키워드 알림을 껐어요')),
          duration: Duration(milliseconds: 1800),
          behavior: SnackBarBehavior.floating,
          width: 320,
        ),
      );
    }
  }

  Future<void> _toggleDigest(bool on) async {
    final settings = DigestSettings(hour: on ? 9 : null, minute: 0); // 켜면 기본 9시 정각으로 시작
    // 화살표 본문은 대입식의 값(Future 자체)을 그대로 반환해서 "setState()
    // callback argument returned a Future" 오류가 남 — 필드는 바뀌지만
    // 정작 다시 그리라는 표시가 예외로 중단돼서 화면이 안 갱신됨
    // (archive_screen.dart _reload에서 발견한 것과 같은 버그, 블록
    // 본문으로 고침).
    setState(() {
      _digest = Future.value(settings);
    });
    await _devices.setDigest(settings);
  }

  Future<void> _pickDigestTime(int currentHour) async {
    final picked = await showAppBottomSheet<int>(
      context,
      builder: (context) => _TimePickerSheet(initialHour: currentHour),
    );
    if (picked == null) return;
    final settings = DigestSettings(hour: picked, minute: 0);
    setState(() {
      _digest = Future.value(settings);
    });
    await _devices.setDigest(settings);
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

  /// 2026-09-26: 오늘의 단어도 오늘의 이슈팝처럼 기기별 발송 시각을
  /// 고를 수 있게 함(서버 고정 9시에서 변경) — _updateKeywordAlert와
  /// 같은 낙관적 업데이트 패턴.
  Future<void> _updateWordOfDayAlert(WordOfDayAlertSettings Function(WordOfDayAlertSettings) update) async {
    final current = await (_wordOfDayAlert ?? _devices.getWordOfDayAlert());
    final next = update(current);
    setState(() {
      _wordOfDayAlert = Future.value(next);
    });
    await _devices.setWordOfDayAlert(next);
  }

  Future<void> _pickWordOfDayTime(int currentHour) async {
    final picked = await showAppBottomSheet<int>(
      context,
      builder: (context) => _TimePickerSheet(initialHour: currentHour),
    );
    if (picked == null) return;
    await _updateWordOfDayAlert((c) => c.copyWith(hour: picked, minute: 0));
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

  /// 2026-09-22: 카카오페이 "받기" 링크로 후원 시작 — 결제를 앱 안에서
  /// 직접 처리하려면 PG 계약/사업자등록이 필요해서, 1인 개발 단계에선
  /// 외부 링크로 넘기는 방식만 씀.
  /// 2026-09-26: 카카오페이는 송금 화면에 개발자 본명이 그대로 노출돼서
  /// Buy Me a Coffee로 교체함 — 후원자에게는 페이지 닉네임만 보임.
  Future<void> _openDonationLink() async {
    await launchUrl(Uri.parse('https://buymeacoffee.com/itssophie'), mode: LaunchMode.externalApplication);
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

  /// 2026-09-28: "알림이 하루종일 안 온다"를 실기기 로그 없이도 점검할
  /// 수 있게 — 지금 권한 상태/토큰 상태/마지막 토큰 발급 시도 결과를
  /// 한 화면에 모아 보여줌. FcmDiagnostics(push_token.dart)는 그 세션
  /// 안에서 가장 최근 시도한 결과만 담고 있어서, 이 화면을 보기 전에
  /// 한 번은 앱을 열어(설정 화면 진입 시 기기 등록/토큰 갱신이 돎)
  /// 실제로 시도가 있었어야 값이 참.
  Future<void> _showNotificationDiagnostics() async {
    await _refreshNotificationStatus();
    final tokenInfo = await _devices.tokenDiagnostic();
    if (!mounted) return;
    await showAppBottomSheet<void>(
      context,
      builder: (_) => _NotificationDiagnosticsSheet(
        permissionStatus: _lastKnownNotificationStatus,
        tokenInfo: tokenInfo,
        lastAttemptStatus: FcmDiagnostics.lastStatus,
        lastError: FcmDiagnostics.lastError,
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
              child: FutureBuilder<void>(
                future: _initialLoad,
                builder: (context, loadSnapshot) {
                  if (loadSnapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  return _buildList(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 24),
      children: [
                  Builder(
                    builder: (context) {
                      if (_notificationsDenied != true) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: AppColors.accent2Soft,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(Icons.notifications_off_outlined, size: 18, color: AppColors.accent2),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  '알림을 받으려면 켜주세요',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
                                ),
                              ),
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: openNotificationSettings,
                                style: TextButton.styleFrom(
                                  backgroundColor: AppColors.accent2,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                child: const Text('알림 설정 열기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  _SectionLabel('알림'),
                  const SizedBox(height: 8),
                  // 2026-09-26: 세 알림을 카드 하나에 다 몰아넣었더니 "다
                  // 붙어있어서 헷갈린다"는 피드백 — 서로 발송 시점도
                  // 성격도 다른 별개 기능이라, 카드를 셋으로 나눠서 각자의
                  // 경계를 눈으로 바로 구분할 수 있게 함. 이름/순서도
                  // 정리함:
                  //   1. 오늘의 이슈팝(구 매일 트렌드 요약 알림)
                  //   2. 오늘의 단어(구 오늘의 단어 알림)
                  //   3. 관심 키워드(구 관심 이슈 알림)
                  // "오늘의 OO" 두 개(정해진 시각에 하루 한 번)를 먼저
                  // 묶고, 성격이 다른 실시간 알림(관심 키워드)을 맨
                  // 뒤로 뺌.
                  //
                  // 2026-09-26 추가: 캡션 문구는 뺐음 — 오늘의 이슈팝/
                  // 오늘의 단어는 이제 둘 다 "알림 시간" 행이 바로 아래
                  // 보이니 그걸로 "언제"가 충분히 전달되고, 토글 이름
                  // 자체가 "뭘" 보내는지도 어느 정도 설명됨(궁금하면
                  // 아래 "미리보기"도 있음). 관심 키워드만 "뜨는 즉시"
                  // 오는 실시간 알림이라 캡션 없이는 그 성격이 안
                  // 드러나서 유일하게 캡션을 남겨둠.
                  //
                  // 오늘의 이슈팝 — 지정한 시각에 하루 한 번.
                  FutureBuilder<DigestSettings>(
                    future: _digest,
                    builder: (context, snapshot) {
                      final settings = snapshot.data;
                      final hour = settings?.hour;
                      return AppCard(
                        padding: EdgeInsets.zero,
                        radius: 18,
                        child: Column(
                          children: [
                            _ToggleRow(
                              label: '오늘의 이슈팝',
                              value: hour != null,
                              onChanged: snapshot.connectionState == ConnectionState.waiting || _notificationsDenied == true
                                  ? null
                                  : _toggleDigest,
                              showDivider: hour != null,
                            ),
                            if (hour != null)
                              _PlainRow(
                                label: '알림 시간',
                                trailing: _formatTime(hour, settings!.minute),
                                onTap: () => _pickDigestTime(hour),
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
                  // 별개로 켜고 끌 수 있게 함. 2026-09-26: 서버 고정
                  // 9시에서 오늘의 이슈팝과 같은 기기별 시각 선택으로 바꿈.
                  FutureBuilder<WordOfDayAlertSettings>(
                    future: _wordOfDayAlert,
                    builder: (context, snapshot) {
                      final s = snapshot.data;
                      return AppCard(
                        padding: EdgeInsets.zero,
                        radius: 18,
                        child: Column(
                          children: [
                            _ToggleRow(
                              label: '오늘의 단어',
                              value: s?.enabled ?? false,
                              onChanged: s == null || _notificationsDenied == true
                                  ? null
                                  : (v) => _updateWordOfDayAlert((c) => c.copyWith(enabled: v)),
                              showDivider: s?.enabled ?? false,
                            ),
                            if (s != null && s.enabled)
                              _PlainRow(
                                label: '알림 시간',
                                trailing: _formatTime(s.hour, s.minute),
                                onTap: () => _pickWordOfDayTime(s.hour),
                                showDivider: false,
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  // 관심 키워드(구 관심 이슈 알림) — 관심 키워드 화면에
                  // 등록해둔 키워드와 매칭되는 새 이슈가 뜨면 알림. 위
                  // 둘과 달리 "정해진 시각"이 아니라 뜨는 즉시 오는
                  // 알림이라 캡션에서 그 성격을 분명히 함.
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
                              label: '관심 키워드',
                              value: s?.enabled ?? false,
                              onChanged: s == null || _notificationsDenied == true
                                  ? null
                                  : (v) => _updateKeywordAlert((c) => c.copyWith(enabled: v)),
                              showDivider: s?.enabled ?? false,
                            ),
                            if (s != null && s.enabled) ...[
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                                child: Text(
                                  '알림 금지 시간대',
                                  style: TextStyle(fontSize: 12, color: AppColors.inkFaint),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: _QuietHourCell(
                                        label: '시작',
                                        value: _formatHour(s.quietStart),
                                        onTap: () =>
                                            _pickKeywordAlertQuietHour(isStart: true, current: s.quietStart),
                                      ),
                                    ),
                                    Container(width: 1, height: 34, color: AppColors.divider),
                                    Expanded(
                                      child: _QuietHourCell(
                                        label: '종료',
                                        value: _formatHour(s.quietEnd),
                                        onTap: () =>
                                            _pickKeywordAlertQuietHour(isStart: false, current: s.quietEnd),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
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
                        // 2026-09-26: "후원하기"보다 Buy Me a Coffee 자체
                        // 브랜딩(서비스명 그대로)을 쓰는 게 낫다는 피드백 —
                        // 이모지는 빼고 이름만.
                        _PlainRow(
                          label: 'Buy Me a Coffee',
                          onTap: _openDonationLink,
                          showDivider: true,
                        ),
                        _PlainRow(
                          label: '문의하기',
                          onTap: _showContactSheet,
                          showDivider: true,
                        ),
                        // 2026-09-28: "알림이 하루종일 안 온다"를 실기기
                        // 로그(adb) 없이도 점검할 수 있게 — 지금 저장된
                        // 토큰이 진짜 FCM 토큰인지, 마지막 발급 시도에서
                        // 뭐가 잘못됐는지를 바로 보여줌.
                        _PlainRow(
                          label: '알림 진단 정보',
                          onTap: _showNotificationDiagnostics,
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
                                  ? '이슈판이 정보를 받아오는 언론사들이에요. 기사 원문은 각 언론사에서 직접 확인할 수 있어요.'
                                  : '이슈판이 정보를 받아오는 ${outlets.length}개 언론사예요. 기사 원문은 각 언론사에서 직접 확인할 수 있어요.',
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
                            label: '오늘의 이슈팝 미리보기',
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
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 14, color: AppColors.ink)),
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

/// 2026-09-26: 조용한 시간대 시작/종료를 각각 독립된 행으로 두니 "이게
/// 왜 두 줄이나 차지하지" 싶게 UI가 무거워 보인다는 피드백 — 하나의
/// "조용한 시간대 설정" 아래, 시작/종료를 반반씩 나눠 한 줄로 묶음.
class _QuietHourCell extends StatelessWidget {
  const _QuietHourCell({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: AppColors.inkFaint)),
            const SizedBox(height: 3),
            Text(value, style: TextStyle(fontSize: 15, color: AppColors.ink, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// 2026-08-26: 새벽/오전/오후/저녁 4구간 → 표준 12시간제(오전/오후) →
/// 2026-09-30에 다시 24시간제로 정리함(비공개 테스트 준비하며 UI 정돈 —
/// "오전 11시"에서 "오후 12시"로 넘어가는 지점 등 12시간제 자체가 스크롤
/// 휠에서 오히려 헷갈린다는 피드백). "13시"처럼 그대로 읽는 24시간제가
/// 시간표/일정 앱에서 흔히 쓰는 표기라 스크롤 휠이랑도 잘 맞음.
String _formatHour(int hour) => '$hour시';

/// 2026-09-27: "지금 테스트해보게 분 단위로도 설정할 수 있게" 요청으로
/// 추가했다가, 2026-09-30에 실사용엔 분 단위가 불필요하다는 피드백으로
/// 피커에서는 뺌 — 다만 이 함수는 남겨둠. 과거에 분 단위로 저장된 값이
/// 있으면(테스트 중 고른 값 등) 여전히 "9시 5분"처럼 보여주기 위해서.
String _formatTime(int hour, int minute) {
  final base = _formatHour(hour);
  if (minute == 0) return base;
  return '$base ${minute.toString().padLeft(2, '0')}분';
}

/// 2026-09-10: "발송 기능이 아직 없는데 그럼 뭐가 발송되는지 보고 싶다"는
/// 요청으로 추가 — 실제 푸시처럼 보이게 알림 배너 흉내를 낸 카드 안에
/// GET /digest/preview가 지금 이 순간 만들어내는 텍스트를 그대로 보여줌.
/// 실제 발송(FCM)과는 무관한 조회 전용이라 기기 목록을 건드리거나
/// last_digest_sent_at을 바꾸지 않음.
/// 2026-09-28: "알림이 하루종일 안 온다"를 실기기 로그(adb) 없이도
/// 점검할 수 있게 만든 진단 화면 — 권한 상태/토큰 상태/마지막 토큰
/// 발급 시도 결과를 그대로 보여줌. 문의하기로 이 내용을 복사해 보내면
/// 원인 파악이 훨씬 빨라짐.
class _NotificationDiagnosticsSheet extends StatelessWidget {
  const _NotificationDiagnosticsSheet({
    required this.permissionStatus,
    required this.tokenInfo,
    required this.lastAttemptStatus,
    required this.lastError,
  });

  final AuthorizationStatus? permissionStatus;
  final String tokenInfo;
  final String? lastAttemptStatus;
  final String? lastError;

  String _permissionLabel(AuthorizationStatus? status) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return '허용됨';
      case AuthorizationStatus.denied:
        return '거부됨';
      case AuthorizationStatus.provisional:
        return '임시 허용(조용한 알림)';
      case AuthorizationStatus.notDetermined:
        return '아직 물어본 적 없음';
      case null:
        return '확인 실패';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppSheetBody(
      title: '알림 진단 정보',
      subtitle: '알림이 안 온다면 이 값들을 확인해보세요. 문의하기에 그대로 붙여 보내주시면 더 빨리 봐드릴 수 있어요.',
      children: [
        _DiagnosticRow(label: '기기 알림 권한', value: _permissionLabel(permissionStatus)),
        _DiagnosticRow(label: '알림 토큰 상태', value: tokenInfo),
        _DiagnosticRow(label: '마지막 토큰 발급 시도', value: lastAttemptStatus ?? '이번 세션에서 아직 시도 안 함'),
        if (lastError != null) _DiagnosticRow(label: '마지막 오류', value: lastError!),
      ],
    );
  }
}

class _DiagnosticRow extends StatelessWidget {
  const _DiagnosticRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: AppColors.inkFaint, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          SelectableText(value, style: TextStyle(fontSize: 13, color: AppColors.ink)),
        ],
      ),
    );
  }
}

class _DigestPreviewSheet extends StatelessWidget {
  const _DigestPreviewSheet({required this.preview});

  final Future<String> preview;

  @override
  Widget build(BuildContext context) {
    return AppSheetBody(
      title: '오늘의 이슈팝 미리보기',
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

/// 2026-09-27: 관심 키워드의 "알림 금지 시간대" 시작/종료를 고르는
/// 바텀시트 — 이건 특정 순간에 보내는 알림이 아니라 시(0~23) 경계값이라
/// 분 단위가 의미 없어서 그대로 둠(분까지 고를 수 있는 _TimePickerSheet는
/// 오늘의 이슈팝/오늘의 단어처럼 실제 "이 시각에 보낸다"는 알림에만 씀).
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

/// 2026-09-27: 오늘의 이슈팝/오늘의 단어 알림 시각 고르는 바텀시트 —
/// 처음엔 시/분 휠 두 개짜리로 만들었다가(테스트용 분 단위 설정 요청),
/// 2026-09-30에 비공개 테스트 준비하며 분 단위는 실사용에 불필요하다는
/// 피드백으로 시 하나만 고르는 휠로 정리함(백엔드 digest_minute/
/// word_of_day_minute 컬럼 자체는 나중을 위해 그대로 둠 — 여기서는 항상
/// 0으로 보냄). CupertinoPicker는 flutter SDK에 이미 포함돼 있어서 별도
/// 패키지 없이 씀 — 최근 위젯 패키지 하나로 며칠 크래시를 겪어서, 새
/// 네이티브 의존성은 최대한 피함.
class _TimePickerSheet extends StatefulWidget {
  const _TimePickerSheet({required this.initialHour});

  final int initialHour;

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  late int _hour = widget.initialHour;

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
              child: CupertinoPicker(
                scrollController: FixedExtentScrollController(initialItem: widget.initialHour),
                itemExtent: 40,
                onSelectedItemChanged: (i) => setState(() => _hour = i),
                selectionOverlay: Container(
                  decoration: BoxDecoration(
                    border: Border.symmetric(horizontal: BorderSide(color: AppColors.divider)),
                  ),
                ),
                children: [
                  for (var h = 0; h < 24; h++)
                    Center(
                      child: Text(
                        _formatHour(h),
                        style: TextStyle(fontSize: 15, color: AppColors.ink),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_hour),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                  child: const Text('확인'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
