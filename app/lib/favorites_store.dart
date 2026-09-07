import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models/issue.dart';

/// 저장한 이슈(아카이브) 로컬 저장소. 계정/로그인이 아직 없어서(메모:
/// project_infra_deployment) v0는 기기 로컬 저장만 씀 — 여러 기기 동기화는
/// 로그인 기능이 생기면 그때 서버 쪽(user_favorites 테이블/POST
/// /favorites)으로 옮기면 됨.
///
/// 이슈 id뿐 아니라 전체 IssueDetail(기사 목록 포함)을 저장해둠 — 캐시가 30분마다
/// 갈아엎이면서 같은 이슈라도 id가 바뀔 수 있다는 알려진 한계가 있어서
/// (backend/README.md 참고), 저장 시점의 스냅샷을 그대로 보여주는 쪽을
/// 택함. id로 다시 조회해서 최신화하는 건 나중 과제.
class SavedIssue {
  final IssueDetail issue;
  final DateTime savedAt;

  SavedIssue({required this.issue, required this.savedAt});

  factory SavedIssue.fromJson(Map<String, dynamic> json) => SavedIssue(
        issue: IssueDetail.fromJson(json['issue'] as Map<String, dynamic>),
        savedAt: DateTime.parse(json['saved_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'issue': issue.toJson(),
        'saved_at': savedAt.toIso8601String(),
      };
}

/// 2026-08-28: 예전엔 화면마다 SharedPreferences를 매번 새로 읽고
/// (getAll/isSaved 둘 다 Future), 뭔가 바뀌면 콜백(onFavoriteChanged)으로
/// 부모 화면에게 "너도 새로고침 해"라고 일일이 알려주는 구조였음. 이러면
/// 콜백을 안 받는 다른 화면의 카드는 상태가 안 바뀐 채로 남는 버그가
/// 생김(아카이브 화면에서 즐겨찾기를 해제해도, 이미 떠 있던 홈 화면의
/// 카드는 북마크 표시가 여전히 켜진 채로 남아있던 버그가 실제로 있었음).
///
/// 그래서 앱 전체가 이 싱글턴 하나만 보고, `ChangeNotifier`를 구독해서
/// 어디서 바뀌든 모든 화면이 즉시 반영되게 바꿈. `load()`를 main()에서
/// runApp 전에 한 번 불러서, 그 뒤로는 전부 동기적으로(Future 없이)
/// 읽을 수 있게 함 — 매번 await 안 해도 되니 화면 쪽 코드도 단순해짐.
class FavoritesStore extends ChangeNotifier {
  FavoritesStore._();
  static final FavoritesStore instance = FavoritesStore._();

  static const _key = 'saved_issues_v1';

  final Map<String, SavedIssue> _byId = {};
  bool _loaded = false;
  bool get isLoaded => _loaded;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    for (final s in raw) {
      final saved = SavedIssue.fromJson(jsonDecode(s) as Map<String, dynamic>);
      _byId[saved.issue.id] = saved;
    }
    _loaded = true;
  }

  List<SavedIssue> get all {
    final items = _byId.values.toList();
    items.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return items;
  }

  bool isSaved(String issueId) => _byId.containsKey(issueId);

  /// 화면에는 즉시 반영(notifyListeners 먼저)하고, 디스크 저장은 뒤이어
  /// 함 — 로컬 저장이라 실패할 일이 거의 없어서 낙관적 업데이트로 충분함.
  /// 반환값은 토글 후 "저장된 상태인지"(true=저장됨, false=해제됨) —
  /// 호출한 쪽에서 스낵바 문구를 고를 때 씀.
  Future<bool> toggle(IssueDetail issue) async {
    final bool nowSaved;
    if (_byId.containsKey(issue.id)) {
      _byId.remove(issue.id);
      nowSaved = false;
    } else {
      _byId[issue.id] = SavedIssue(issue: issue, savedAt: DateTime.now());
      nowSaved = true;
    }
    notifyListeners();
    await _persist();
    return nowSaved;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = _byId.values.map((s) => jsonEncode(s.toJson())).toList();
    await prefs.setStringList(_key, raw);
  }
}
