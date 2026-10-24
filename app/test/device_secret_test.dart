import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:issue_pop/api_client.dart';
import 'package:issue_pop/device_registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 2026-10-23: 기기 비밀값 — 기기 번호만으로 남의 설정을 못 보게 서버가 기기마다 발급하고, 앱이 받아 저장해서 기기별 요청마다 실어 보냄.
http.Response _json(Object body, [int status = 200]) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status, headers: {'content-type': 'application/json; charset=utf-8'});

const _token = 'a-long-push-token-over-24-chars-xxxxx';

void main() {
  setUp(() => DeviceRegistry.resetForTest());

  test('비밀값 도입 전에 등록한 기기는 업데이트 후 첫 요청 전에 비밀값을 넘겨받고, 이후 요청에 실어 보낸다', () async {
    SharedPreferences.setMockInitialValues({'device_id_v1': 7, 'device_push_token_v1': _token});
    final seen = <String>[];
    var secretOnDigest = '';
    final client = MockClient((req) async {
      seen.add('${req.method} ${req.url.path}');
      if (req.method == 'POST' && req.url.path == '/devices') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['push_token'], _token);
        expect(body['claim'], isTrue);
        return _json({'device_id': 7, 'device_secret': 'S1'});
      }
      if (req.url.path == '/devices/7/digest') {
        secretOnDigest = req.headers['X-Device-Secret'] ?? '';
        if (secretOnDigest != 'S1') return _json({'detail': 'invalid device secret'}, 403);
        return _json({'device_id': 7, 'digest_hour': 8, 'digest_minute': 30});
      }
      return _json({}, 404);
    });
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);

    final settings = await DeviceRegistry(api).getDigest();

    expect(settings.hour, 8);
    expect(seen, ['POST /devices', 'GET /devices/7/digest']);
    expect(secretOnDigest, 'S1');
    expect((await SharedPreferences.getInstance()).getString('device_secret_v1'), 'S1');
  });

  test('이미 비밀값이 있으면 다시 넘겨받지 않고 바로 실어 보낸다', () async {
    SharedPreferences.setMockInitialValues({
      'device_id_v1': 7,
      'device_push_token_v1': _token,
      'device_secret_v1': 'S9',
    });
    final seen = <String>[];
    final client = MockClient((req) async {
      seen.add('${req.method} ${req.url.path}');
      expect(req.headers['X-Device-Secret'], 'S9');
      return _json({'device_id': 7, 'digest_hour': null, 'digest_minute': 0});
    });
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);

    await DeviceRegistry(api).getDigest();

    expect(seen, ['GET /devices/7/digest']);
  });

  test('넘겨받기에 실패(오프라인)해도 앱은 예전처럼 계속 동작한다', () async {
    SharedPreferences.setMockInitialValues({'device_id_v1': 7, 'device_push_token_v1': _token});
    final client = MockClient((req) async {
      if (req.method == 'POST') throw http.ClientException('연결 안 됨');
      expect(req.headers.containsKey('X-Device-Secret'), isFalse);
      return _json({'device_id': 7, 'digest_hour': 6, 'digest_minute': 0});
    });
    final api = http.runWithClient(() => ApiClient(baseUrl: 'http://fake'), () => client);

    final settings = await DeviceRegistry(api).getDigest();

    expect(settings.hour, 6);
    expect((await SharedPreferences.getInstance()).getString('device_secret_v1'), isNull);
  });
}
