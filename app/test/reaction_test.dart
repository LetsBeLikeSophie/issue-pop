import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:issue_pop/api_client.dart';
import 'package:issue_pop/install_id.dart';
import 'package:issue_pop/models/issue.dart';
import 'package:issue_pop/models/reaction.dart';
import 'package:issue_pop/reaction_store.dart';
import 'package:issue_pop/widgets/expandable_issue_card.dart';
import 'package:issue_pop/widgets/reaction_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 서버(backend/api.py)의 반응 동작을 흉내 내는 가짜 서버: 한 설치는 한 키워드에 하나만.
class _FakeServer {
  final Map<String, Map<String, String>> byKeyword = {}; // 키워드 → {설치 id: 반응}
  final List<Map<String, dynamic>> sets = [];
  Set<String> knownKeywords;

  _FakeServer(this.knownKeywords);

  Map<String, dynamic> summary(String keyword, String? clientId) {
    final votes = byKeyword[keyword] ?? {};
    final counts = <String, int>{};
    for (final v in votes.values) {
      counts[v] = (counts[v] ?? 0) + 1;
    }
    String? top;
    for (final k in kReactionKinds.map((e) => e.key)) {
      if ((counts[k] ?? 0) > (top == null ? 0 : counts[top]!)) top = k;
    }
    return {'counts': counts, 'people': votes.length, 'top': top, 'mine': clientId == null ? null : votes[clientId]};
  }

  http.Response handle(http.Request req) {
    http.Response ok(Object body) =>
        http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
    if (req.method == 'GET' && req.url.path == '/reactions') {
      final cid = req.url.queryParameters['client_id'];
      return ok({for (final k in req.url.queryParametersAll['keywords'] ?? <String>[]) k: summary(k, cid)});
    }
    if (req.method == 'POST' && req.url.path == '/reactions/set') {
      final body = jsonDecode(req.body) as Map<String, dynamic>;
      sets.add(body);
      final kw = body['keyword'] as String;
      if (!knownKeywords.contains(kw)) return http.Response('{"detail":"keyword not found"}', 404);
      final votes = byKeyword.putIfAbsent(kw, () => {});
      final reaction = body['reaction'] as String?;
      if (reaction == null) {
        votes.remove(body['client_id']);
      } else {
        votes[body['client_id'] as String] = reaction;
      }
      return ok(summary(kw, body['client_id'] as String));
    }
    return http.Response('unexpected ${req.method} ${req.url}', 500);
  }
}

Future<_FakeServer> _setUp(Set<String> known, {Map<String, Map<String, String>> seed = const {}}) async {
  SharedPreferences.setMockInitialValues({});
  InstallId.resetForTest();
  final server = _FakeServer(known)..byKeyword.addAll({for (final e in seed.entries) e.key: Map.of(e.value)});
  final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => MockClient((r) async => server.handle(r)));
  ReactionStore.instance
    ..resetForTest()
    ..init(api);
  return server;
}

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: child)));

Future<void> _pumpLoaded(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 150));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('가장 많이 눌린 반응 하나만 아이콘+수로 보이고, 반응이 없으면 추가 아이콘만 보인다', (tester) async {
    await _setUp({'busy', 'empty'}, seed: {
      'busy': {'u1': 'angry', 'u2': 'angry', 'u3': 'like'},
    });

    await tester.pumpWidget(_host(const ReactionButton(keyword: 'busy')));
    await _pumpLoaded(tester);
    expect(find.byIcon(Icons.sentiment_very_dissatisfied), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.byIcon(Icons.sentiment_satisfied_alt), findsNothing, reason: '1등만 보여야 함');

    await tester.pumpWidget(_host(const ReactionButton(keyword: 'empty')));
    await _pumpLoaded(tester);
    expect(find.byIcon(Icons.add_reaction_outlined), findsOneWidget);
  });

  testWidgets('누르면 5개가 떠오르고, 하나 고르면 반영되고, 같은 걸 또 고르면 취소된다', (tester) async {
    final server = await _setUp({'k1'}, seed: {
      'k1': {'u1': 'angry', 'u2': 'like'},
    });

    await tester.pumpWidget(_host(const ReactionButton(keyword: 'k1')));
    await _pumpLoaded(tester);

    await tester.tap(find.byType(ReactionButton));
    await tester.pumpAndSettle();
    expect(find.text('이 소식에 대한 내 반응'), findsOneWidget);
    for (final kind in kReactionKinds) {
      expect(find.text(kind.label), findsOneWidget, reason: kind.label);
    }

    // 화나요 선택 → 서버로 angry 전송, 버튼의 대표 반응 수가 1 -> 2
    await tester.tap(find.text('화나요'));
    await tester.pumpAndSettle();
    expect(server.sets.last['reaction'], 'angry');
    expect(find.text('이 소식에 대한 내 반응'), findsNothing, reason: '고르면 팝업이 닫힘');
    expect(find.text('2'), findsOneWidget);

    // 같은 걸 다시 고르면 취소(null) → 수가 1로 돌아옴
    await tester.tap(find.byType(ReactionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('화나요'));
    await tester.pumpAndSettle();
    expect(server.sets.last['reaction'], isNull);
    expect(server.byKeyword['k1']!.length, 2);

    // 다른 걸 고르면 바뀜(한 카드에 하나)
    await tester.tap(find.byType(ReactionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('걱정돼요'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ReactionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('안타까워요'));
    await tester.pumpAndSettle();
    expect(server.byKeyword['k1']!.values.where((v) => v == 'worried'), isEmpty, reason: '걱정돼요는 안타까워요로 바뀌었어야 함');
    expect(server.byKeyword['k1']!.values.where((v) => v == 'sorry').length, 1);
  });

  testWidgets('지금 목록에 없는 키워드면 안내 문구를 보여준다', (tester) async {
    await _setUp({'other'});
    await tester.pumpWidget(_host(const ReactionButton(keyword: 'gone')));
    await _pumpLoaded(tester);

    await tester.tap(find.byType(ReactionButton));
    await tester.pumpAndSettle();
    await tester.tap(find.text('좋아요'));
    await tester.pumpAndSettle();
    expect(find.text('지금 목록에 없는 이슈예요'), findsOneWidget);
  });

  testWidgets('이슈 카드에는 반응 버튼이 있고, 저장한 이슈(보관함) 카드에는 없다', (tester) async {
    await _setUp({'추미애'});
    final issue = IssueSummary(
      id: 'a1',
      keyword: '추미애',
      keywords: const ['추미애'],
      category: '정치',
      representativeTitle: '대표 기사 제목',
      articleCount: 5,
      outletCount: 3,
    );

    await tester.pumpWidget(_host(SizedBox(width: 380, child: ExpandableIssueCard(issue: issue))));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(ReactionButton), findsOneWidget);

    await tester.pumpWidget(_host(SizedBox(width: 380, child: ExpandableIssueCard(issue: issue, archiveMode: true))));
    await tester.pump(const Duration(milliseconds: 150));
    expect(find.byType(ReactionButton), findsNothing);
  });
}
