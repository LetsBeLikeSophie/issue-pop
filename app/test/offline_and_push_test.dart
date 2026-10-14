import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:issue_pop/api_client.dart';
import 'package:issue_pop/offline_cache.dart';
import 'package:issue_pop/screens/issue_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _issue(String id, String keyword, int articles) => {
      'id': id,
      'keyword': keyword,
      'keywords': [keyword, '보조'],
      'category': '정치',
      'representative_title': '$keyword 관련 대표 기사 제목',
      'article_count': articles,
      'outlet_count': 3,
      'first_seen_at': null,
      'trend': 'surge',
      'trend_delta': 5,
      'outlets': [
        {'outlet': '연합뉴스', 'count': 1},
      ],
      'articles': [
        {'outlet': '연합뉴스', 'title': '$keyword 기사 1', 'link': 'https://example.com/1', 'published': null, 'image': null},
      ],
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfflineCache.staleSince.value = null;
    OfflineCache.serverBusy.value = false;
  });

  test('네트워크가 끊기면 마지막으로 받은 trending을 돌려주고 staleSince를 채운다', () async {
    var online = true;
    final client = MockClient((req) async {
      if (!online) throw http.ClientException('연결 안 됨');
      return _json([_issue('a1', '추미애', 13)]);
    });
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);

    final first = await api.getTrending();
    expect(first.single.keyword, '추미애');
    expect(first.single.trend, 'surge');
    expect(first.single.trendDelta, 5);
    expect(OfflineCache.staleSince.value, isNull);

    // 저장(비동기)이 끝날 때까지 한 박자 기다림
    await Future<void>.delayed(const Duration(milliseconds: 50));

    online = false;
    final offline = await api.getTrending();
    expect(offline.single.keyword, '추미애');
    expect(OfflineCache.staleSince.value, isNotNull);

    online = true;
    await api.getTrending();
    expect(OfflineCache.staleSince.value, isNull, reason: '다시 연결되면 배너 상태가 지워져야 함');
  });

  test('서버가 502를 주는데 저장해둔 캐시도 없으면 예외를 그대로 던진다', () async {
    final client = MockClient((req) async => _json({'detail': 'bad gateway'}, 502));
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);
    await expectLater(api.getTrending(), throwsA(isA<ApiException>()));
  });

  test('서버가 502를 주면 받아둔 목록을 보여주면서 serverBusy를 켠다 — 빈 목록(첫 갱신 전)도 마찬가지', () async {
    var mode = 'ok';
    final client = MockClient((req) async {
      if (mode == '502') return _json({'detail': 'bad gateway'}, 502);
      if (mode == 'empty') return _json([]);
      return _json([_issue('a1', '추미애', 13)]);
    });
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);

    await api.getTrending();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(OfflineCache.serverBusy.value, isFalse);

    mode = '502';
    expect((await api.getTrending()).single.keyword, '추미애');
    expect(OfflineCache.serverBusy.value, isTrue);
    expect(OfflineCache.staleSince.value, isNotNull);

    mode = 'ok';
    await api.getTrending();
    expect(OfflineCache.serverBusy.value, isFalse);
    expect(OfflineCache.staleSince.value, isNull);

    mode = 'empty';
    expect((await api.getTrending()).single.keyword, '추미애', reason: '서버가 빈 목록을 주면 받아둔 걸 보여줘야 함');
    expect(OfflineCache.serverBusy.value, isTrue);
  });

  test('네트워크가 끊긴 거면 serverBusy는 꺼져 있다("연결이 안 돼요")', () async {
    var online = true;
    final client = MockClient((req) async {
      if (!online) throw http.ClientException('연결 안 됨');
      return _json([_issue('a1', '추미애', 13)]);
    });
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);
    await api.getTrending();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    online = false;
    await api.getTrending();
    expect(OfflineCache.staleSince.value, isNotNull);
    expect(OfflineCache.serverBusy.value, isFalse);
  });

  testWidgets('알림으로 연 이슈 id가 404면 키워드로 지금 목록에서 찾아 펼친 채로 보여준다', (tester) async {
    final client = MockClient((req) async {
      final path = req.url.path;
      if (path == '/issues/old-id') return _json({'detail': 'issue not found'}, 404);
      if (path == '/search') {
        return _json([
          _issue('new-small', '추미애', 5),
          _issue('new-big', '추미애', 13),
          _issue('other', '다른이슈', 99),
        ]);
      }
      if (path == '/issues/new-big') return _json(_issue('new-big', '추미애', 13));
      return _json({'detail': 'unexpected ${req.url}'}, 500);
    });
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);

    await tester.pumpWidget(MaterialApp(home: IssueScreen(api: api, issueId: 'old-id', keyword: '추미애')));
    await tester.pumpAndSettle();

    expect(find.text('추미애'), findsWidgets);
    expect(find.text('추미애 기사 1'), findsOneWidget, reason: 'initiallyExpanded라 기사 목록이 바로 보여야 함');
    expect(find.text('이 이슈는 지금 목록에 더 이상 없어요.\n홈에서 최신 이슈를 확인해보세요.'), findsNothing);
  });

  testWidgets('id도 키워드도 못 찾으면 안내 문구를 보여준다', (tester) async {
    final client = MockClient((req) async {
      if (req.url.path == '/search') return _json([_issue('x', '무관', 1)]);
      return _json({'detail': 'issue not found'}, 404);
    });
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);

    await tester.pumpWidget(MaterialApp(home: IssueScreen(api: api, issueId: 'gone', keyword: '추미애')));
    await tester.pumpAndSettle();

    expect(find.textContaining('더 이상 없어요'), findsOneWidget);
  });
}
