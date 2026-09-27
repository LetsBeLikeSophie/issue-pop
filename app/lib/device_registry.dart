import 'dart:async';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'push_token.dart';

/// 로그인 없이 이 기기를 서버에 알리는 데 씀(다이제스트 알림 설정 등,
/// backend/db.py의 Device 참고).
///
/// 2026-09-08: push_token을 실제 FCM 토큰으로 교체 시작 — 그동안은 그냥
/// 이 기기를 구분하는 로컬 난수였음(실제 발송 연동 전엔 자리만 잡아둔
/// 것). 이제 FCM 토큰을 먼저 시도하고(push_token.dart), 권한 거부/웹
/// VAPID 키 미설정 등으로 못 받아오면 기존 랜덤 토큰으로 폴백함 —
/// 그래도 최소한 "이 기기가 뭔지 구분"은 계속 되니까 앱이 안 죽음.
class DeviceRegistry {
  DeviceRegistry(this.api);

  final ApiClient api;

  static const _tokenKey = 'device_push_token_v1';
  static const _idKey = 'device_id_v1';

  /// 랜덤 폴백 토큰은 항상 이 길이(24자 hex) — 진짜 FCM 토큰은
  /// 훨씬 길어서(보통 140자 이상) 구분에 씀.
  static const _fallbackTokenLength = 24;

  Future<int> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getInt(_idKey);
    if (cached != null) {
      unawaited(_maybeUpgradeToken(prefs, cached));
      return cached;
    }

    var token = prefs.getString(_tokenKey);
    if (token == null) {
      token = await getFcmToken() ?? _randomToken();
      await prefs.setString(_tokenKey, token);
    }
    final id = await api.registerDevice(token);
    await prefs.setInt(_idKey, id);
    return id;
  }

  /// 2026-09-27: 서비스 워커가 오리진 루트에 없어서(/app/ 밑에만 있어서)
  /// getFcmToken()이 계속 실패해 랜덤 폴백 토큰으로만 등록되던 기기들이
  /// 있음 — 서버 배포로 그 문제를 고친 뒤에도, 이미 랜덤 토큰으로 등록된
  /// 기기는 다시 시도하지 않으면 영원히 알림을 못 받음. 그래서 기기 실행
  /// 때마다(이미 device_id가 있어도) 조용히 한 번씩 진짜 토큰을 다시
  /// 요청해보고, 성공하면 같은 device_id를 유지한 채로 갈아끼움 — 등록해둔
  /// 키워드/조용한 시간대 설정을 잃지 않게. 이미 진짜 토큰이면(길이로
  /// 판단) 매번 재요청할 필요 없음.
  Future<void> _maybeUpgradeToken(SharedPreferences prefs, int deviceId) async {
    final current = prefs.getString(_tokenKey);
    if (current != null && current.length > _fallbackTokenLength) return;
    final real = await getFcmToken();
    if (real == null || real == current) return;
    try {
      await api.updateDevicePushToken(deviceId, real);
      await prefs.setString(_tokenKey, real);
    } catch (_) {
      // 다음 실행 때 다시 시도하면 되니 조용히 무시.
    }
  }

  Future<int?> getDigestHour() async {
    final id = await _deviceId();
    return api.getDigestHour(id);
  }

  Future<void> setDigestHour(int? hour) async {
    final id = await _deviceId();
    await api.setDigestHour(id, hour);
  }

  Future<KeywordAlertSettings> getKeywordAlert() async {
    final id = await _deviceId();
    return api.getKeywordAlert(id);
  }

  Future<KeywordAlertSettings> setKeywordAlert(KeywordAlertSettings settings) async {
    final id = await _deviceId();
    return api.setKeywordAlert(id, settings);
  }

  Future<void> addWatch(String keyword) async {
    final id = await _deviceId();
    await api.addWatch(id, keyword);
  }

  Future<List<KeywordWatch>> listWatches() async {
    final id = await _deviceId();
    return api.listWatches(id);
  }

  Future<void> deleteWatch(int watchId) async {
    await api.deleteWatch(watchId);
  }

  Future<List<StockWatch>> listStockWatches() async {
    final id = await _deviceId();
    return api.listStockWatches(id);
  }

  Future<StockWatch> addStockWatch(String ticker) async {
    final id = await _deviceId();
    return api.addStockWatch(id, ticker);
  }

  Future<void> deleteStockWatch(int watchId) async {
    await api.deleteStockWatch(watchId);
  }

  Future<WordOfDayAlertSettings> getWordOfDayAlert() async {
    final id = await _deviceId();
    return api.getWordOfDayAlert(id);
  }

  Future<WordOfDayAlertSettings> setWordOfDayAlert(WordOfDayAlertSettings settings) async {
    final id = await _deviceId();
    return api.setWordOfDayAlert(id, settings);
  }

  Future<void> submitFeedback(String message, {String? contactEmail}) async {
    final id = await _deviceId();
    await api.submitFeedback(deviceId: id, message: message, contactEmail: contactEmail);
  }

  String _randomToken() {
    final rand = Random.secure();
    return List.generate(24, (_) => rand.nextInt(16).toRadixString(16)).join();
  }
}
