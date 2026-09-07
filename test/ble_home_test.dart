import 'dart:typed_data';
import 'package:sunset_ripple/core/security/room_invite.dart';
import 'package:sunset_ripple/core/security/session_handshake.dart';
import 'package:sunset_ripple/core/protocol/frame.dart';
import 'package:sunset_ripple/core/protocol/frame_type.dart';
import 'package:sunset_ripple/core/protocol/payloads/join_request.dart';
import 'package:sunset_ripple/core/protocol/payloads/roster.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunset_ripple/core/audio/audio_io.dart';
import 'package:sunset_ripple/core/session/room_session.dart';
import 'package:sunset_ripple/ui/pages/home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('host.msknet.sunsetripple/ble_l2cap');
  const scanChannel = 'host.msknet.sunsetripple/ble_l2cap_scan';
  final calls = <MethodCall>[];
  bool advertisingWorks = true;
  late RoomInvite invite;
  late SecureFrameCodec hostCodec;
  RoomSession? entered;
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() async {
    invite = RoomInvite.generate();
    hostCodec = await invite.createCodec();
    calls.clear();
    advertisingWorks = true;
    entered = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'startAdvertising') return advertisingWorks;
      if (call.method == 'sendL2capData') {
        final sealed = Frame.decode(call.arguments['data'] as Uint8List)!;
        expect(sealed.type, FrameType.sealed);
        final plain = await hostCodec.open(sealed);
        if (plain.type == FrameType.joinReq) {
          final join = JoinRequestPayload.decode(plain.payload)!;
          final response = await hostCodec.seal(
            Frame(
              type: FrameType.roster,
              senderId: 1,
              seq: 1,
              payload:
                  RosterPayload(
                    hostId: 1,
                    members: [
                      RosterMember(memberId: 1, flags: 1, nickname: 'Host'),
                      RosterMember(memberId: 2, nickname: join.nickname),
                    ],
                  ).encode(),
            ),
          );
          await messenger.handlePlatformMessage(
            'host.msknet.sunsetripple/ble_l2cap_data',
            const StandardMethodCodec().encodeSuccessEnvelope({
              'data': response.encode(),
              'peerAddress': 'host',
            }),
            (_) {},
          );
        }
      }
      return true;
    });
    for (final name in [
      scanChannel,
      'host.msknet.sunsetripple/ble_l2cap_data',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        calls.add(call);
        return null;
      });
    }
  });
  tearDown(() async {
    await entered?.dispose();
    messenger.setMockMethodCallHandler(channel, null);
    for (final name in [
      scanChannel,
      'host.msknet.sunsetripple/ble_l2cap_data',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  Future<void> pumpUntil(WidgetTester tester, bool Function() ready) async {
    for (var i = 0; i < 100 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 10));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(
      ready(),
      isTrue,
      reason:
          'asynchronous BLE operation must complete: ${calls.map((c) => c.method)}',
    );
  }

  Future<void> showHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HomeContent(
            isNight: false,
            stage: const AlwaysStoppedAnimation(0),
            audioIo: MockAudioIo(),
            onEnterRoom: (session, _) => entered = session,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Bluetooth Talk'));
    await tester.pump();
  }

  testWidgets(
    'BLE mode scans, renders a discovered room, and connects to its PSM',
    (tester) async {
      await showHome(tester);
      expect(calls.any((c) => c.method == 'startScan'), isTrue);
      messenger.handlePlatformMessage(
        scanChannel,
        const StandardMethodCodec().encodeSuccessEnvelope({
          'address': 'AA:BB:CC:DD:EE:FF',
          'psm': 129,
          'roomName': '测试蓝牙房',
          'memberCount': 1,
          'rssi': -40,
        }),
        (_) {},
      );
      await tester.pump();
      expect(find.text('测试蓝牙房'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Join chat'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('room-invite-input')),
        invite.code,
      );
      await tester.tap(find.text('验证并加入'));
      await pumpUntil(tester, () => entered != null);
      expect(
        calls.where((c) => c.method == 'connectL2cap').single.arguments['psm'],
        129,
      );
      expect(entered?.mode, RoomMode.bluetoothPtt);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    },
  );

  testWidgets('advertising failure never enters a phantom room', (
    tester,
  ) async {
    advertisingWorks = false;
    await showHome(tester);
    await tester.tap(find.text('Start Bluetooth Talk'));
    await tester.pump();
    await pumpUntil(
      tester,
      () => find.textContaining('蓝牙广播未能开启').evaluate().isNotEmpty,
    );
    expect(calls.any((c) => c.method == 'startAdvertising'), isTrue);
    expect(entered, isNull);
    expect(find.textContaining('蓝牙广播未能开启'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
  });
}
