import 'package:dawn_mesh/core/internet/hybrid_ice.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> candidate(
    String ip, {
    int port = 1234,
    String type = 'host',
  }) => {
    'candidate': 'candidate:1 1 udp 2122260223 $ip $port typ $type',
    'sdpMid': '0',
    'sdpMLineIndex': 0,
  };

  test('late private candidates are delivered after matching SDP; early ones are buffered', () async {
    final ice = HybridIceInbox();
    final added = <String>[];
    await ice.receive('peer', 'session', candidate('192.168.49.1'));
    expect(added, isEmpty);
    await ice.activate('peer', 'session', (c) async => added.add(c.candidate!));
    expect(added, hasLength(1));
    // The P2P interface appeared after the original 800 ms gathering window.
    await ice.receive('peer', 'session', candidate('192.168.49.2'));
    expect(added, hasLength(2));
    await ice.receive('peer', 'session', candidate('192.168.49.2'));
    expect(added, hasLength(2));
  });

  test('candidate generations do not cross peers or reconnects', () async {
    final ice = HybridIceInbox();
    final added = <String>[];
    await ice.receive('peer', 'old', candidate('192.168.49.1'));
    await ice.receive('other', 'new', candidate('192.168.49.3'));
    await ice.activate('peer', 'new', (c) async => added.add(c.candidate!));
    expect(added, isEmpty);
    await ice.receive('peer', 'new', candidate('192.168.49.2'));
    expect(added.single, contains('192.168.49.2'));
    ice.forget('peer');
    await ice.receive('peer', 'new', candidate('192.168.49.4'));
    expect(added, hasLength(1));
    ice.clear();
    await ice.activate('peer', 'new', (c) async => added.add(c.candidate!));
    expect(added, hasLength(1));
  });

  test('untrusted candidates stay private, well-formed and bounded', () async {
    final ice = HybridIceInbox();
    var added = 0;
    await ice.activate('peer', 'session', (_) async => added++);
    for (final data in [
      candidate('8.8.8.8'),
      candidate('192.168.49.1', type: 'relay'),
      candidate('192.168.999.1'),
      {...candidate('192.168.49.1'), 'sdpMLineIndex': -1},
      {...candidate('192.168.49.1'), 'sdpMid': 2},
    ]) {
      await ice.receive('peer', 'session', data);
    }
    expect(added, 0);
    for (var i = 0; i < 100; i++) {
      await ice.receive(
        'peer',
        'session',
        candidate('192.168.49.1', port: 1234 + i),
      );
    }
    expect(added, 64);
  });
}
