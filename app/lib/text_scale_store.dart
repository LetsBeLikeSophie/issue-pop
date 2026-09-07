import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 설정 화면의 "글자 크기" 옵션. FavoritesStore와 같은 패턴 —
/// 싱글턴 ChangeNotifier + main()에서 load() 한 번 불러서 그 뒤로는
/// 동기적으로 읽음. main.dart의 MaterialApp.builder에서 이 값으로
/// MediaQuery textScaler를 전체 앱에 적용함.
class TextScaleStore extends ChangeNotifier {
  TextScaleStore._();
  static final TextScaleStore instance = TextScaleStore._();

  static const _key = 'text_scale_v1';
  // 2026-08-30: 기본값이 이미 충분히 작다는 피드백으로 "작게" 단계는
  // 뺌 — 기본(보통)보다 더 작게 갈 이유가 없다고 판단.
  static const List<double> steps = [1.0, 1.15, 1.3];
  static const List<String> labels = ['보통', '크게', '아주 크게'];

  double _scale = 1.0;
  double get scale => _scale;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getDouble(_key);
    if (saved != null && steps.contains(saved)) {
      _scale = saved;
    }
  }

  Future<void> setScale(double value) async {
    if (value == _scale) return;
    _scale = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_key, value);
  }
}
