import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// 로그인 없이 이 기기를 서버에 알리는 데 씀(다이제스트 알림 설정 등,
/// backend/db.py의 Device 참고). push_token은 실제 FCM 토큰이 아니라
/// 그냥 이 기기를 구분하는 로컬 난수 — 실제 푸시 연동 붙이면 진짜
/// FCM 토큰으로 교체하면 됨(자리만 미리 잡아둔 것).
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
      token = _randomToken();
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

  String _randomToken() {
    final rand = Random.secure();
    return List.generate(24, (_) => rand.nextInt(16).toRadixString(16)).join();
  }
}
