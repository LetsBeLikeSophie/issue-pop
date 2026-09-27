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

  /// 2026-09-27: 설정/관심종목/관심키워드 화면이 각자 자기 DeviceRegistry
  /// 인스턴스를 만들어 써서(위젯마다 `DeviceRegistry(widget.api)`), 인스턴스
  /// 필드로 캐싱해봐야 화면 하나 안에서만 유효했음 — 화면을 새로 열 때마다
  /// (또는 같은 화면 안에서 다이제스트/키워드알림/오늘의단어를 각각 부를
  /// 때마다) 기기 등록·토큰 갱신 확인을 매번 다시 했던 게 설정 화면이
  /// 느려 보이던 원인. 앱 프로세스가 살아있는 동안 딱 한 번만 하면 되는
  /// 일이라 static Future로 세션 전체에서 공유함 — 여러 곳에서 동시에
  /// 불러도 `??=`가 먼저 시작된 하나의 Future를 그대로 돌려줌.
  static Future<int>? _deviceIdFuture;

  Future<int> _deviceId() => _deviceIdFuture ??= _resolveDeviceId();

  Future<int> _resolveDeviceId() async {
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

  // 2026-09-27: 이 앱은 로그인이 없어서 알림 설정이 오직 "이 기기"에만
  // 묶여있음(다른 기기/브라우저에서 바꿀 방법 자체가 없음) — 그러면
  // 서버가 매번 다시 물어봐야 할 이유가 없음. 화면 열 때마다 네트워크
  // 왕복하는 대신, 로컬(SharedPreferences)을 먼저 보고 있으면 그걸
  // 즉시 돌려주고, 바꿀 때만(set*) 로컬에 먼저 쓰고 서버에도 반영
  // (write-through)함. 로컬이 서버보다 앞서나갈 일이 없는 게, 이
  // DeviceRegistry를 거치지 않고 이 설정을 바꿀 방법이 없기 때문임.
  static const _digestHourCachedKey = 'digest_hour_cached_v1';
  static const _digestHourValueKey = 'digest_hour_value_v1'; // -1이면 null(꺼짐)
  static const _digestMinuteValueKey = 'digest_minute_value_v1';

  Future<DigestSettings> getDigest() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_digestHourCachedKey) ?? false) {
      final v = prefs.getInt(_digestHourValueKey) ?? -1;
      return DigestSettings(hour: v == -1 ? null : v, minute: prefs.getInt(_digestMinuteValueKey) ?? 0);
    }
    final id = await _deviceId();
    final settings = await api.getDigest(id);
    await _cacheDigest(prefs, settings);
    return settings;
  }

  Future<void> setDigest(DigestSettings settings) async {
    await _cacheDigest(await SharedPreferences.getInstance(), settings);
    final id = await _deviceId();
    await api.setDigest(id, settings);
  }

  Future<void> _cacheDigest(SharedPreferences prefs, DigestSettings settings) async {
    await prefs.setBool(_digestHourCachedKey, true);
    await prefs.setInt(_digestHourValueKey, settings.hour ?? -1);
    await prefs.setInt(_digestMinuteValueKey, settings.minute);
  }

  static const _keywordAlertCachedKey = 'keyword_alert_cached_v1';
  static const _keywordAlertEnabledKey = 'keyword_alert_enabled_v1';
  static const _keywordAlertStartKey = 'keyword_alert_quiet_start_v1';
  static const _keywordAlertEndKey = 'keyword_alert_quiet_end_v1';

  Future<KeywordAlertSettings> getKeywordAlert() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keywordAlertCachedKey) ?? false) {
      return KeywordAlertSettings(
        enabled: prefs.getBool(_keywordAlertEnabledKey) ?? false,
        quietStart: prefs.getInt(_keywordAlertStartKey) ?? 23,
        quietEnd: prefs.getInt(_keywordAlertEndKey) ?? 7,
      );
    }
    final id = await _deviceId();
    final settings = await api.getKeywordAlert(id);
    await _cacheKeywordAlert(prefs, settings);
    return settings;
  }

  Future<KeywordAlertSettings> setKeywordAlert(KeywordAlertSettings settings) async {
    await _cacheKeywordAlert(await SharedPreferences.getInstance(), settings);
    final id = await _deviceId();
    return api.setKeywordAlert(id, settings);
  }

  Future<void> _cacheKeywordAlert(SharedPreferences prefs, KeywordAlertSettings settings) async {
    await prefs.setBool(_keywordAlertCachedKey, true);
    await prefs.setBool(_keywordAlertEnabledKey, settings.enabled);
    await prefs.setInt(_keywordAlertStartKey, settings.quietStart);
    await prefs.setInt(_keywordAlertEndKey, settings.quietEnd);
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

  static const _wordOfDayCachedKey = 'word_of_day_cached_v1';
  static const _wordOfDayEnabledKey = 'word_of_day_enabled_v1';
  static const _wordOfDayHourKey = 'word_of_day_hour_v1';
  static const _wordOfDayMinuteKey = 'word_of_day_minute_v1';

  Future<WordOfDayAlertSettings> getWordOfDayAlert() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_wordOfDayCachedKey) ?? false) {
      return WordOfDayAlertSettings(
        enabled: prefs.getBool(_wordOfDayEnabledKey) ?? false,
        hour: prefs.getInt(_wordOfDayHourKey) ?? 9,
        minute: prefs.getInt(_wordOfDayMinuteKey) ?? 0,
      );
    }
    final id = await _deviceId();
    final settings = await api.getWordOfDayAlert(id);
    await _cacheWordOfDayAlert(prefs, settings);
    return settings;
  }

  Future<WordOfDayAlertSettings> setWordOfDayAlert(WordOfDayAlertSettings settings) async {
    await _cacheWordOfDayAlert(await SharedPreferences.getInstance(), settings);
    final id = await _deviceId();
    return api.setWordOfDayAlert(id, settings);
  }

  Future<void> _cacheWordOfDayAlert(SharedPreferences prefs, WordOfDayAlertSettings settings) async {
    await prefs.setBool(_wordOfDayCachedKey, true);
    await prefs.setBool(_wordOfDayEnabledKey, settings.enabled);
    await prefs.setInt(_wordOfDayHourKey, settings.hour);
    await prefs.setInt(_wordOfDayMinuteKey, settings.minute);
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
