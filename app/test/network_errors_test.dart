import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:issue_pop/api_client.dart';
import 'package:issue_pop/widgets/error_retry.dart';

/// 2026-10-26(출시 전 점검 IP-13): 모든 요청에 제한 시간 + 사용자에게는 한국어 안내.
void main() {
  test('이슈 상세 같은 요청도 응답이 안 오면 제한 시간 뒤 실패한다(로딩만 계속 돌지 않음)', () async {
    final saved = ApiClient.requestTimeout;
    ApiClient.requestTimeout = const Duration(milliseconds: 100);
    addTearDown(() => ApiClient.requestTimeout = saved);
    final client = MockClient((req) => Completer<http.Response>().future); // 응답이 오지 않음
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);

    await expectLater(api.getIssue('abc'), throwsA(isA<TimeoutException>()));
    await expectLater(api.listWatches(1), throwsA(isA<TimeoutException>()));
  });

  test('오류 문구는 영어 예외 대신 한국어 안내로 바꾼다', () {
    expect(friendlyErrorText('ClientException with SocketException: Failed host lookup: api.issue-pop.com'), '인터넷 연결을 확인해 주세요.');
    expect(friendlyErrorText(TimeoutException('x')), '인터넷 연결을 확인해 주세요.');
    expect(friendlyErrorText('ClientException: XMLHttpRequest error.'), '인터넷 연결을 확인해 주세요.');
    expect(friendlyErrorText('ApiException(404): not found'), '요청을 처리하지 못했어요. 잠시 후 다시 시도해 주세요.');
    expect(friendlyErrorText('FormatException: Unexpected character'), '잠시 후 다시 시도해 주세요.');
    for (final raw in ['ClientException: Failed host lookup', 'ApiException(404): x', 'FormatException: y']) {
      expect(RegExp('[A-Za-z]{6,}').hasMatch(friendlyErrorText(raw)), isFalse, reason: '영어 문구가 그대로 보이면 안 됨: $raw');
    }
  });
}
