import 'dart:convert';

import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/internet/internet_room_api.dart';
import 'package:dawn_mesh/core/internet/internet_room_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('guest follows persisted room policy; hot disable and re-enable apply without rejoin', () async {
    var available = true;
    final applied = <bool>[];
    final hosts = <String?>[];
    var writes = 0;
    const profile = ServerProfile(
      id: 's',
      name: 's',
      baseUrl: 'https://example.test',
    );
    final api = InternetRoomApi(
      profile,
      client: MockClient((r) async {
        if (r.method != 'GET') writes++;
        return http.Response(
          jsonEncode({
            'instanceId': 's',
            'features': {'schemaVersion': 1, 'hybridAudio': available},
          }),
          200,
        );
      }),
    );
    final session = InternetRoomSession.forTesting(
      api: api,
      profile: profile,
      nickname: 'guest',
      roomId: 'room',
      memberId: 'guest',
      summary: const InternetRoomSummary(
        id: 'room',
        name: 'room',
        memberCount: 2,
        maxParticipants: 25,
        hostNickname: 'host',
      ),
      hybridActiveForTesting: (active, host) async {
        applied.add(active);
        hosts.add(host);
      },
    );
    addTearDown(session.disposeSession);
    Map<String, dynamic> room(bool enabled) => {
      'id': 'room',
      'hybridAudioSupported': true,
      'hybridAudioEnabled': enabled,
    };
    await session.refreshFeaturesForTesting();
    await session.receiveManagementForTesting({
      'type': 'snapshot',
      'hostMemberId': 'host',
      'room': room(true),
      'members': <dynamic>[],
    });
    expect(applied.last, isTrue);
    expect(hosts.last, 'host');
    expect(session.hybridEnabled, isTrue);
    await expectLater(session.setHybridEnabled(false), throwsStateError);
    expect(writes, 0);
    available = false;
    await session.refreshFeaturesForTesting();
    expect(applied.last, isFalse);
    expect(
      session.hybridEnabled,
      isTrue,
    ); // Owner preference survives global capability disable.
    available = true;
    await session.refreshFeaturesForTesting();
    expect(applied.last, isTrue);
    await session.receiveManagementForTesting({
      'type': 'room_updated',
      'room': room(false),
    });
    expect(applied.last, isFalse);
    await session.receiveManagementForTesting({
      'type': 'room_updated',
      'room': room(true),
    });
    expect(applied.last, isTrue);
    await session.receiveManagementForTesting({
      'type': 'role_changed',
      'hostMemberId': 'new-host',
      'members': <dynamic>[],
    });
    expect(hosts.last, 'new-host');
  });
  test('host policy API carries the authenticated session and parses durable room state', () async {
    const profile = ServerProfile(
      id: 's',
      name: 's',
      baseUrl: 'https://example.test',
    );
    final api = InternetRoomApi(
      profile,
      client: MockClient((r) async {
        expect(r.method, 'PUT');
        expect(r.url.path, '/api/v1/rooms/r/hybrid-audio');
        expect(r.headers['x-dawn-session'], 'host-token');
        expect(jsonDecode(r.body), {'enabled': true});
        return http.Response(
          jsonEncode({
            'room': {
              'id': 'r',
              'hybridAudioSupported': true,
              'hybridAudioEnabled': true,
            },
          }),
          200,
        );
      }),
    );
    final room = await api.setHybridAudio('r', true, 'host-token');
    expect(room.hybridAudioEnabled, isTrue);
    api.close();
  });
}
