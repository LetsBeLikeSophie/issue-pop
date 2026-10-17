import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-10-17: 홈 화면 "관심 종목" 위젯(안드로이드, StockWidget*.kt)에 보일 종목 설정.
///
/// 관심 종목 화면 위쪽의 "위젯에 표시" 칸에 끌어다 놓은 종목(최대 [maxPicks]개)을 저장하고,
/// 위젯이 읽을 수 있게 네이티브에도 전달함(MethodChannel). 한 번도 안 정했으면(null) 관심 종목
/// 맨 앞 [maxPicks]개가 기본 — 처음 깔아두는 시총 상위 10개 순서 그대로라 곧 시총 상위 3개.
///
/// 네이티브 쪽은 이 호출이 실패하거나 없어도(웹/iOS/구버전) 앱에 영향이 없도록 전부 삼킴.
class StockWidgetStore {
  StockWidgetStore._();

  static const maxPicks = 5;
  static const _picksKey = 'stock_widget_picks_v1';
  static const _deviceIdKey = 'device_id_v1'; // device_registry.dart의 _idKey
  static const _channel = MethodChannel('issuepop/stock_widget');

  static bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 사용자가 정한 종목. 한 번도 안 정했으면 null(=기본값 사용).
  static Future<List<String>?> loadPicks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_picksKey);
    if (raw == null) return null;
    return raw.split(',').where((t) => t.isNotEmpty).toList();
  }

  static Future<void> savePicks(List<String> tickers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_picksKey, tickers.join(','));
  }

  /// 화면에 보여줄/위젯에 쓸 실제 종목: 정해둔 게 있으면 그중 지금 관심 종목에 아직 있는 것만,
  /// 없으면(한 번도 안 정함) 관심 종목 앞에서부터 [maxPicks]개.
  static List<String> effective(List<String>? saved, List<String> watchedTickers) {
    if (saved == null) return watchedTickers.take(maxPicks).toList();
    return saved.where(watchedTickers.contains).take(maxPicks).toList();
  }

  /// 기기 id와 위젯 종목을 네이티브(위젯)에 전달하고 위젯을 바로 갱신시킴.
  static Future<void> syncToWidget({required int deviceId, required List<String> tickers}) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>('sync', {'deviceId': deviceId, 'tickers': tickers});
    } catch (_) {
      // 위젯은 부가 기능 — 실패해도 앱 동작과 무관.
    }
  }

  /// 위젯을 눌러 앱이 열렸을 때 이동할 화면. 앱이 꺼져 있다 켜진 경우(콜드 스타트)는 네이티브가 들고 있다가
  /// 여기서 한 번 가져가고, 이미 떠 있던 경우는 네이티브가 "route"로 바로 알려줌. 지금은 "stocks"(관심 종목)만 있음.
  static void listenForRoute(void Function(String route) onRoute) {
    if (!_supported) return;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'route' && call.arguments is String) onRoute(call.arguments as String);
        return null;
      });
      _channel.invokeMethod<String>('takeLaunchRoute').then((route) {
        if (route != null) onRoute(route);
      }).catchError((_) {});
    } catch (_) {}
  }

  /// 앱을 켤 때: 이미 등록된 기기 id가 있으면 위젯에 알려줌(위젯만 먼저 추가한 경우에도 종목이 나오게).
  static Future<void> syncKnownDeviceId() async {
    if (!_supported) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getInt(_deviceIdKey);
      if (id == null) return;
      final saved = await loadPicks();
      await syncToWidget(deviceId: id, tickers: saved ?? const []);
    } catch (_) {}
  }
}
