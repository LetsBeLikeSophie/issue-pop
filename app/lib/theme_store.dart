import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-09-09: 색 테마 프리셋 — 예전부터 "나중에 테마 고를 수 있게" 자리를
/// 남겨두기로 했던 것. 처음부터 완전히 자유로운 커스텀 컬러피커 대신
/// 프리셋 3개(현재/흰색·회색/다크)만 골라서 누르면 바로 바뀌는 정도로
/// 시작함 — text_scale_store.dart와 같은 패턴(ChangeNotifier +
/// shared_preferences 저장).
enum ColorPreset { current, neutral, dark }

class ThemeStore extends ChangeNotifier {
  ThemeStore._();

  static final ThemeStore instance = ThemeStore._();

  static const _key = 'color_preset_v1';

  ColorPreset _preset = ColorPreset.current;
  ColorPreset get preset => _preset;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    _preset = ColorPreset.values.firstWhere(
      (p) => p.name == saved,
      orElse: () => ColorPreset.current,
    );
    notifyListeners();
  }

  Future<void> setPreset(ColorPreset preset) async {
    if (preset == _preset) return;
    _preset = preset;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, preset.name);
  }
}
