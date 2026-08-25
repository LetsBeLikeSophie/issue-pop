import 'dart:convert';
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

class FavoritesStore {
  static const _key = 'saved_issues_v1';

  Future<List<SavedIssue>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final items = raw.map((s) => SavedIssue.fromJson(jsonDecode(s) as Map<String, dynamic>)).toList();
    items.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return items;
  }

  Future<bool> isSaved(String issueId) async {
    final all = await getAll();
    return all.any((i) => i.issue.id == issueId);
  }

  Future<void> toggle(IssueDetail issue) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_key) ?? [];
    final idx = raw.indexWhere(
      (s) => (jsonDecode(s) as Map<String, dynamic>)['issue']['id'] == issue.id,
    );
    if (idx >= 0) {
      raw.removeAt(idx);
    } else {
      raw.add(jsonEncode(SavedIssue(issue: issue, savedAt: DateTime.now()).toJson()));
    }
    await prefs.setStringList(_key, raw);
  }
}
