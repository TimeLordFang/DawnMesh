import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dawn_mesh/core/audio/audio_io.dart';
import 'package:dawn_mesh/core/fusion/fusion_identity.dart';
import 'package:dawn_mesh/core/fusion/fusion_transport.dart';
import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:dawn_mesh/core/security/room_invite.dart';
import 'package:dawn_mesh/core/session/member.dart';
import 'package:dawn_mesh/core/session/room_session.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _until(bool Function() done) async {
  final deadline = DateTime.now().add(const Duration(seconds: 8));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('fusion state');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _Node {
  _Node(this.session, this.link, this.audio);
  final RoomSession session;
  final FusionTransport link;
  final MockAudioIo audio;
}

Future<_Node> _node(
  FusionIdentity room,
  RoomInvite invite,
  int installation, {
  bool host = false,
  ServerProfile? server,
}) async {
  final audio = MockAudioIo();
  final proof = base64Encode(List.filled(32, installation));
  final session = RoomSession(
    audioIo: audio,
    selfNickname: 'member$installation',
    mode: RoomMode.fusion,
    sessionToken: FusionIdentity.memberToken(proof, room.roomId),
  );
  final link = FusionTransport(
    roomId: room.roomId,
    roomName: room.name,
    identity: host ? room : null,
    profile: server,
    localPort: 0,
    advertise: false,
  );
  await session.protectWithInvite(invite);
  session.attachTransport(link, reconnect: link.reconnect);
  addTearDown(session.dispose);
  await link.start(session);
  if (host) await session.createRoom(startAudio: false);
  return _Node(session, link, audio);
}

Future<void> _joinLocal(_Node guest, _Node neighbor) async {
  expect(
    await guest.link.connectLocal('127.0.0.1', port: neighbor.link.boundPort),
    true,
  );
  await guest.session.joinRoom(startAudio: false);
  await _until(() => guest.session.state == RoomState.inRoom);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // These tests exercise loopback sockets and the optional real Go relay.
  HttpOverrides.global = null;

  test('room identity, signed member state and installation identity resist tampering', () async {
    final room = await FusionIdentity.create('离线融合房');
    final admitted = await FusionIdentity.openBootstrap(
      room.bootstrap,
      room.roomId,
    );
    expect(admitted, isNotNull);
    expect(admitted!.canSign, false);
    final other = await FusionIdentity.create('另一房间');
    expect(
      await FusionIdentity.openBootstrap(room.bootstrap, other.roomId),
      isNull,
    );
    final corrupted = Uint8List.fromList(room.bootstrap)..[40] ^= 1;
    expect(await FusionIdentity.openBootstrap(corrupted, room.roomId), isNull);
    final proof = base64Encode(List.filled(32, 5));
    final id = FusionIdentity.memberToken(proof, room.roomId);
    expect(id, FusionIdentity.memberToken(proof, room.roomId));
    expect(id, isNot(FusionIdentity.memberToken(proof, other.roomId)));
    final state = await room.signState([
      Member(memberId: 1, nickname: '房主', sessionToken: id),
    ], 123);
    expect(await admitted.verifyState(state), true);
    expect(await other.verifyState(state), false);
    state[20] ^= 1;
    expect(await admitted.verifyState(state), false);
  });

  test('offline admission through any local member; cyclic paths deliver once and PTT stays closed', () async {
    final room = await FusionIdentity.create('全员离线');
    final invite = RoomInvite.parse('1234');
    final host = await _node(room, invite, 1, host: true);
    final a = await _node(room, invite, 2);
    final b = await _node(room, invite, 3);
    await _joinLocal(a, host);
    await _joinLocal(
      b,
      a,
    ); // B cannot contact a server and joins via non-host A.
    expect(host.session.members.length, 3);
    await host.link.synchronize();
    await _until(() => b.link.signedState != null);
    expect(b.link.identity!.roomId, room.roomId);
    expect(a.link.cloudConnected, false);
    // A real TCP triangle exercises duplicate/loop prevention.
    expect(
      await b.link.connectLocal('127.0.0.1', port: host.link.boundPort),
      true,
    );
    await a.session.sendChat('离线入房成功');
    await _until(
      () =>
          host.session.chatMessages.length == 1 &&
          b.session.chatMessages.length == 1,
    );
    await a.session.startAudio();
    expect(a.session.voiceMode, VoiceMode.pushToTalk);
    a.audio.emitEncodedFrame(Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(host.audio.submittedFrames, isEmpty);
    a.session.setPtt(true);
    a.audio.emitEncodedFrame(Uint8List.fromList([4, 5, 6]));
    await _until(
      () =>
          host.audio.submittedFrames.isNotEmpty &&
          b.audio.submittedFrames.isNotEmpty,
    );
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(host.audio.submittedFrames.length, 1);
    expect(b.audio.submittedFrames.length, 1);
    a.session.setPtt(false);
    a.session.triggerDisconnect();
    await _until(() => a.session.state == RoomState.inRoom);
    expect(a.session.isPttPressed, false);
    expect(host.session.members.length, 3);
    a.audio.emitEncodedFrame(Uint8List.fromList([7, 8, 9]));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(host.audio.submittedFrames.length, 1);
    await host.session.endRoom();
    await _until(() => a.session.roomEnded && b.session.roomEnded);
  }, timeout: const Timeout(Duration(seconds: 40)));

  test('wrong four-digit code cannot join the local fusion room', () async {
    final room = await FusionIdentity.create('验证');
    final host = await _node(room, RoomInvite.parse('1234'), 1, host: true);
    final bad = await _node(room, RoomInvite.parse('5678'), 2);
    expect(
      await bad.link.connectLocal('127.0.0.1', port: host.link.boundPort),
      true,
    );
    await bad.session.joinRoom(startAudio: false);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(bad.session.state, RoomState.connecting);
    expect(bad.session.secureCodec, isNull);
    expect(host.session.members.length, 1);
  });

  final integrationURL = Platform.environment['DAWNMESH_FUSION_TEST_URL'];
  test(
    'real Go relay: offline host, online gateways, remote admission and uplink loss',
    () async {
      final server = ServerProfile(
        id: 'test',
        name: 'test',
        baseUrl: integrationURL!,
        accessToken: 'fusion-test-access',
      );
      final room = await FusionIdentity.create('跨端融合验证');
      final invite = RoomInvite.parse('2134');
      final host = await _node(
        room,
        invite,
        1,
        host: true,
      ); // No server configuration.
      final a = await _node(room, invite, 2, server: server);
      final b = await _node(room, invite, 3, server: server);
      await _joinLocal(a, host);
      await _joinLocal(b, host);
      await host.link.synchronize();
      await _until(
        () => a.link.signedState != null && b.link.signedState != null,
      );
      await a.link.synchronize();
      await b.link.synchronize();
      expect(a.link.cloudConnected, true, reason: a.link.lastConnectionError);
      expect(b.link.cloudConnected, true, reason: b.link.lastConnectionError);
      final remote = await _node(room, invite, 4, server: server);
      expect(await remote.link.connectCloud(), true);
      await remote.session.joinRoom(startAudio: false);
      await _until(() => remote.session.state == RoomState.inRoom);
      await host.link.synchronize();
      await _until(() => remote.link.identity != null);
      expect(host.session.members.length, 4);
      await remote.session.startAudio();
      remote.session.setPtt(true);
      remote.audio.emitEncodedFrame(Uint8List.fromList([2, 8, 9]));
      await _until(() => host.audio.submittedFrames.isNotEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        host.audio.submittedFrames.length,
        1,
      ); // Two online gateways, one playback.
      await a.session
          .dispose(); // B becomes the remaining uplink without election.
      remote.audio.emitEncodedFrame(Uint8List.fromList([3, 7, 9]));
      await _until(() => host.audio.submittedFrames.length == 2);
      await host.session.sendChat('房主不联网，也能和远程成员通话');
      await _until(() => remote.session.chatMessages.length == 1);
      await host.session.endRoom();
      await _until(() => remote.session.roomEnded);
    },
    skip: integrationURL == null
        ? 'Set DAWNMESH_FUSION_TEST_URL to run against the Go relay'
        : false,
    timeout: const Timeout(Duration(seconds: 45)),
  );
}
