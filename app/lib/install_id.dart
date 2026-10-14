import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-10-13: 앱을 처음 실행할 때 한 번 만들어 두는 임의의 설치 식별자(32자 hex).
/// 이모지 반응이 한 설치당 중복되지 않게 하고 "최근 N명이 봤어요"를 세는 데만 씀.
/// 로그인/푸시 토큰/기기 정보와 무관한 값이라 개인 식별 정보가 아님(개인정보처리방침에
/// 명시). 앱을 지웠다 다시 깔면 새 값이 만들어짐.
class InstallId {
  InstallId._();

  static const _key = 'install_id_v1';
  static final _valid = RegExp(r'^[0-9a-f]{32}$');
  static Future<String>? _future;

  static Future<String> get() => _future ??= _load();

  /// 테스트마다 따로 돌아가는 가짜 시간 영역에서 캐시된 Future가 다음 테스트로 새지 않게 비움.
  @visibleForTesting
  static void resetForTest() => _future = null;

  static Future<String> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null && _valid.hasMatch(saved)) return saved;
    final rand = Random.secure();
    final id = List.generate(32, (_) => rand.nextInt(16).toRadixString(16)).join();
    await prefs.setString(_key, id);
    return id;
  }
}
