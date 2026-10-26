import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:issue_pop/favorites_store.dart';
import 'package:issue_pop/models/issue.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-10-26(출시 전 점검 IP-10): 저장한 이슈 하나가 깨져 있어도 나머지와 앱이 그대로 떠야 함.
String _saved(String id, String keyword) => jsonEncode({
      'issue': {
        'id': id,
        'keyword': keyword,
        'keywords': [keyword],
        'category': '정치',
        'representative_title': '$keyword 제목',
        'article_count': 3,
        'outlet_count': 2,
        'outlets': [],
        'articles': [],
      },
      'saved_at': '2026-10-20T09:00:00.000',
    });

void main() {
  setUp(() => FavoritesStore.instance.resetForTest());

  test('손상된 항목은 건너뛰고 나머지 즐겨찾기는 그대로 읽는다', () async {
    SharedPreferences.setMockInitialValues({
      'saved_issues_v1': [
        _saved('a', '추미애'),
        '{이건 JSON이 아님',
        jsonEncode({'issue': {'id': 'x'}, 'saved_at': '2026-10-20'}), // 필수 필드가 없음
        jsonEncode({'issue': 'not-a-map', 'saved_at': '2026-10-20'}),
        _saved('b', '카카오'),
      ],
    });

    await FavoritesStore.instance.load(); // 예외가 새면 여기서 테스트가 실패함

    expect(FavoritesStore.instance.isLoaded, isTrue);
    expect(FavoritesStore.instance.all.map((s) => s.issue.id).toSet(), {'a', 'b'});
    expect(FavoritesStore.instance.isSaved('a'), isTrue);
    expect(FavoritesStore.instance.isSaved('x'), isFalse);
  });

  test('저장된 값이 리스트가 아니어도 빈 목록으로 시작한다', () async {
    SharedPreferences.setMockInitialValues({'saved_issues_v1': 'not-a-list'});

    await FavoritesStore.instance.load();

    expect(FavoritesStore.instance.isLoaded, isTrue);
    expect(FavoritesStore.instance.all, isEmpty);
  });

  test('정상 데이터는 예전과 똑같이 읽힌다', () async {
    SharedPreferences.setMockInitialValues({
      'saved_issues_v1': [_saved('a', '추미애')],
    });

    await FavoritesStore.instance.load();

    final item = FavoritesStore.instance.all.single;
    expect(item.issue, isA<IssueDetail>());
    expect(item.issue.keyword, '추미애');
  });
}
