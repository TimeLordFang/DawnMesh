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
            'adminListeningSupported': true,
          }),
          200,
          headers: const {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    final info = await api.info();
    expect(info.instanceId, 'instance-1');
    expect(info.maxRoomParticipants, 50);
    expect(info.adminListeningSupported, isTrue);
    api.close();
  });

  test('room creation sends monitoring key only when host opts in', () async {
    final api = InternetRoomApi(
      profile,
      client: MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['monitoringKey'], 'escrowed-room-key');
        return http.Response(
          jsonEncode({
            'room': {
              'id': 'room',
              'name': 'Room',
              'memberCount': 1,
              'maxParticipants': 25,
              'hostNickname': 'Host',
              'adminListeningAvailable': true,
            },
            'memberId': 'member',
            'livekitUrl': 'wss://rtc.example.test',
            'livekitToken': 'token',
            'resumeToken': 'resume',
            'eventsUrl': 'wss://talk.example.test/api/v1/events',
          }),
          201,
        );
      }),
    );
    final grant = await api.createRoom(
      name: 'Room',
      nickname: 'Host',
      deviceId: '123456789012345678901234',
      maxParticipants: 25,
      hostDisconnectTimeoutMinutes: 10,
      monitoringKey: 'escrowed-room-key',
    );
    expect(grant.room.adminListeningAvailable, isTrue);
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
