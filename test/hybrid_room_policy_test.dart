import 'dart:convert';

import 'package:dawn_mesh/core/internet/hybrid_audio.dart';
import 'package:dawn_mesh/core/internet/internet_features.dart';

import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/internet/internet_room_api.dart';
import 'package:dawn_mesh/core/internet/internet_room_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class _Hybrid extends Fake implements HybridAudio {
  bool closed = false;
  @override
  bool cloudAvailable = true;
  @override
  InternetFeatures features = const InternetFeatures();
  @override
  int get connectedCount => 1;
  @override
  Set<String> get connectedIds => {'host'};
  @override
  String get status => '直连已连接 1';
  @override
  Future<void> setSending(bool value) async {}
  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('public room ignores legacy hybrid flags across hot refresh and host changes', () async {
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
    expect(applied.last, isFalse);
    expect(hosts.last, 'host');
    expect(session.hybridEnabled, isFalse);
    await expectLater(session.setHybridEnabled(false), throwsStateError);
    expect(writes, 0);
    available = false;
    await session.refreshFeaturesForTesting();
    expect(applied.last, isFalse);
    expect(
      session.hybridEnabled,
      isFalse,
    ); // Public mode stays isolated from legacy room preferences.
    available = true;
    await session.refreshFeaturesForTesting();
    expect(applied.last, isFalse);
    await session.receiveManagementForTesting({
      'type': 'room_updated',
      'room': room(false),
    });
    expect(applied.last, isFalse);
    await session.receiveManagementForTesting({
      'type': 'room_updated',
      'room': room(true),
    });
    expect(applied.last, isFalse);
    await session.receiveManagementForTesting({
      'type': 'role_changed',
      'hostMemberId': 'new-host',
      'members': <dynamic>[],
    });
    expect(hosts.last, 'new-host');
  });
  test('public room tears down a legacy direct link on refresh', () async {
    const profile = ServerProfile(
      id: 's',
      name: 's',
      baseUrl: 'https://example.test',
    );
    final api = InternetRoomApi(
      profile,
      client: MockClient(
        (_) async => http.Response(
          '{"instanceId":"s","features":{"schemaVersion":1,"hybridAudio":true}}',
          200,
        ),
      ),
    );
    final session = InternetRoomSession.forTesting(
      api: api,
      profile: profile,
      nickname: 'guest',
      roomId: 'room',
      memberId: 'guest',
      microphoneForTesting: (_) async {},
      summary: const InternetRoomSummary(
        id: 'room',
        name: 'room',
        memberCount: 2,
        maxParticipants: 25,
        hostNickname: 'host',
      ),
    );
    addTearDown(session.disposeSession);
    await session.refreshFeaturesForTesting();
    await session.receiveManagementForTesting({
      'type': 'snapshot',
      'hostMemberId': 'host',
      'room': {
        'id': 'room',
        'hybridAudioSupported': true,
        'hybridAudioEnabled': true,
      },
      'members': [
        {'id': 'host', 'canSpeak': true},
        {'id': 'guest', 'canSpeak': true},
      ],
    });
    final hybrid = _Hybrid();
    session.attachHybridForTesting(hybrid, 'host');
    session.receiveMediaRosterForTesting({}, connected: false);
    await session.refreshFeaturesForTesting();
    expect(hybrid.closed, true);
    expect(hybrid.cloudAvailable, false);
    expect(session.hybridEnabled, false);
    expect(session.hybridAvailable, false);
    await session.receiveMediaPermissionForTesting(false);
    expect(session.canSpeak, false);
    // A recovered SFU initially denies publishing until policy sync completes.
    // A public-only room obeys the SFU permission until it is restored.
    session.receiveMediaRosterForTesting({'host', 'guest'}, connected: true);
    expect(session.canSpeak, false);
    await session.receiveVoicePolicyForTesting(false);
    expect(session.canSpeak, false);
    await session.receiveManagementForTesting({
      'type': 'room_updated',
      'room': {
        'id': 'room',
        'hybridAudioSupported': true,
        'hybridAudioEnabled': false,
      },
    });
    expect(hybrid.closed, true);
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
