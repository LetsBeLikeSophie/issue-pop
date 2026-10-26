import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:issue_pop/api_client.dart';
import 'package:issue_pop/favorites_store.dart';
import 'package:issue_pop/models/issue.dart';
import 'package:issue_pop/widgets/expandable_issue_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-10-26(출시 전 점검 IP-14): 카드 상세를 한 번 못 받아도 다시 받을 수 있어야 함.
IssueSummary _summary() => IssueSummary(
      id: 'iss1',
      keyword: '추미애',
      keywords: ['추미애', '재정'],
      category: '정치',
      representativeTitle: '추미애 대표 기사 제목',
      articleCount: 2,
      outletCount: 2,
    );

Map<String, dynamic> _detailJson() => {
      'id': 'iss1',
      'keyword': '추미애',
      'keywords': ['추미애', '재정'],
      'category': '정치',
      'representative_title': '추미애 대표 기사 제목',
      'article_count': 2,
      'outlet_count': 2,
      'outlets': [
        {'outlet': '연합뉴스', 'count': 1}
      ],
      'articles': [
        {'outlet': '연합뉴스', 'title': '추미애 기사 하나', 'link': 'https://example.com/1', 'published': null, 'image': null},
      ],
    };

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FavoritesStore.instance.resetForTest();
  });

  testWidgets('상세를 못 받으면 "다시 시도"로 다시 받고, 접었다 펴도 다시 받는다', (tester) async {
    var gets = 0;
    final client = MockClient((req) async {
      gets++;
      if (gets <= 2) throw http.ClientException('연결 안 됨');
      return http.Response.bytes(utf8.encode(jsonEncode(_detailJson())), 200, headers: {'content-type': 'application/json'});
    });
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: ExpandableIssueCard(issue: _summary(), api: api))),
    ));

    // 1) 펼치기 → 첫 요청 실패
    await tester.tap(find.text('추미애').first);
    await tester.pumpAndSettle();
    expect(find.text('불러오지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(gets, 1);

    // 2) 접었다 다시 펴면 새로 받음(두 번째 요청도 실패 → 같은 안내)
    await tester.tap(find.text('추미애').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('추미애').first);
    await tester.pumpAndSettle();
    expect(gets, 2);
    expect(find.text('불러오지 못했어요'), findsOneWidget);

    // 3) "다시 시도" → 이번엔 성공해서 기사가 보임
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(gets, 3);
    expect(find.text('불러오지 못했어요'), findsNothing);
    expect(find.text('추미애 기사 하나'), findsOneWidget);
  });
}
