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

  Future<int> _deviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getInt(_idKey);
    if (cached != null) return cached;

    var token = prefs.getString(_tokenKey);
    if (token == null) {
      token = await getFcmToken() ?? _randomToken();
      await prefs.setString(_tokenKey, token);
    }
    final id = await api.registerDevice(token);
    await prefs.setInt(_idKey, id);
    return id;
  }

  Future<int?> getDigestHour() async {
    final id = await _deviceId();
    return api.getDigestHour(id);
  }

  Future<void> setDigestHour(int? hour) async {
    final id = await _deviceId();
    await api.setDigestHour(id, hour);
  }

  Future<AlertSettings> getAlertSettings() async {
    final id = await _deviceId();
    return api.getAlertSettings(id);
  }

  Future<AlertSettings> setAlertSettings(AlertSettings settings) async {
    final id = await _deviceId();
    return api.setAlertSettings(id, settings);
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

  Future<bool> getWordOfDayAlert() async {
    final id = await _deviceId();
    return api.getWordOfDayAlert(id);
  }

  Future<void> setWordOfDayAlert(bool enabled) async {
    final id = await _deviceId();
    await api.setWordOfDayAlert(id, enabled);
  }

  String _randomToken() {
    final rand = Random.secure();
    return List.generate(24, (_) => rand.nextInt(16).toRadixString(16)).join();
  }
}
