import 'dart:convert';

import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/internet/internet_room_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const profile = ServerProfile(
    id: 'server-1',
    name: 'Test',
    baseUrl: 'https://talk.example.test',
    accessToken: 'access-secret',
  );

  test('parses server capabilities and sends access credential', () async {
    final api = InternetRoomApi(
      profile,
      client: MockClient((request) async {
        expect(request.url.toString(), 'https://talk.example.test/api/v1/info');
        expect(request.headers['authorization'], 'Bearer access-secret');
        return http.Response(
          jsonEncode({
            'instanceId': 'instance-1',
            'name': 'Dawn server',
            'protocolVersion': 1,
            'maxRoomParticipants': 50,
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final info = await api.info();
    expect(info.instanceId, 'instance-1');
    expect(info.maxRoomParticipants, 50);
    api.close();
  });

  test('management request carries the member session separately', () async {
    final api = InternetRoomApi(
      profile,
      client: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.headers['authorization'], 'Bearer access-secret');
        expect(request.headers['x-dawn-session'], 'member-session');
        expect(jsonDecode(request.body), {'canSpeak': false});
        return http.Response('{}', 200);
      }),
    );
    await api.setVoicePolicy('room', 'member', false, 'member-session');
    api.close();
  });

  test('surfaces bounded server errors without leaking credentials', () async {
    final api = InternetRoomApi(
      profile,
      client: MockClient(
        (_) async => http.Response(
          '{"error":"房间已满"}',
          409,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
    await expectLater(
      api.rooms(),
      throwsA(
        isA<InternetApiException>().having((e) => e.message, 'message', '房间已满'),
      ),
    );
    api.close();
  });
}
