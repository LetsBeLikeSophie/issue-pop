import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-10-13: 서버가 죽었거나(재시작 중 502) 지하철 터널처럼 네트워크가 없을 때
/// 에러 화면 대신 "마지막으로 받은 이슈 목록"을 보여주려고 마지막 성공 응답을
/// 기기에 남겨둠(ApiClient의 trending/index만 씀 — 알림 설정처럼 서버가
/// 진실의 원천인 건 대상 아님).
class OfflineCache {
  OfflineCache._();

  /// 지금 화면이 새 데이터가 아니라 기기에 남겨둔 데이터로 그려지고 있으면
  /// 그 데이터를 받아둔 시각, 아니면 null. 홈 화면의 "오프라인" 배너가 구독함.
  static final ValueNotifier<DateTime?> staleSince = ValueNotifier(null);

  static Future<void> save(String key, String body) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('offline_$key', body);
      await prefs.setInt('offline_${key}_at', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {
      // 저장 실패(용량 등)는 조용히 넘어감 — 캐시는 있으면 좋은 정도라 앱 동작과 무관.
    }
  }

  static Future<({String body, DateTime savedAt})?> load(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final body = prefs.getString('offline_$key');
      final at = prefs.getInt('offline_${key}_at');
      if (body == null || at == null) return null;
      return (body: body, savedAt: DateTime.fromMillisecondsSinceEpoch(at));
    } catch (_) {
      return null;
    }
  }
}
