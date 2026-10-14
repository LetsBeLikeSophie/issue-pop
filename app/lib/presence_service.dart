import 'dart:async';

import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'install_id.dart';
import 'models/reaction.dart';

/// 2026-10-13: "최근 10분간 N명이 봤어요". 앱이 화면에 떠 있는 동안 1분마다 서버에
/// 신호를 보내고, 서버가 세어 준 숫자를 [state]로 내보냄. 서버가 최소 인원(3명)
/// 미만이면 show=false를 주고 화면은 아무것도 안 보여줌 — 숫자를 지어내지 않음.
/// 앱이 백그라운드로 가면 신호를 멈추고, 돌아오면 바로 다시 보냄.
class PresenceService with WidgetsBindingObserver {
  PresenceService._();

  static final PresenceService instance = PresenceService._();

  static const _interval = Duration(minutes: 1);

  final ValueNotifier<Presence?> state = ValueNotifier<Presence?>(null);
  ApiClient? _api;
  Timer? _timer;

  void start(ApiClient api) {
    if (_api != null) return;
    _api = api;
    WidgetsBinding.instance.addObserver(this);
    _resume();
  }

  void _resume() {
    _ping();
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _ping());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _resume();
    } else if (state == AppLifecycleState.paused) {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _ping() async {
    final api = _api;
    if (api == null) return;
    try {
      state.value = await api.presencePing(await InstallId.get());
    } catch (_) {
      // 접속자 수는 있으면 좋은 정보라 실패해도 조용히 넘어감(마지막 값을 그대로 둠).
    }
  }
}
