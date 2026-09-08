import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:dawn_mesh/core/security/spake2.dart';

void main() {
  test('RFC 9382 Appendix B P-256 vector: messages, key and confirmations', () {
    BigInt scalar(String hex) => BigInt.parse(hex, radix: 16);
    final w = scalar(
      '2ee57912099d31560b3a44b1184b9b4866e904c49d12ac5042c97dca461b1a5f',
    );
    final a = Spake2(
      isA: true,
      passwordScalar: w,
      testSecret: scalar(
        '43dd0fd7215bdcb482879fca3220c6a968e66d70b1356cac18bb26c84a78d729',
      ),
    );
    final b = Spake2(
      isA: false,
      passwordScalar: w,
      testSecret: scalar(
        'dcb60106f276b02606d8ef0a328c02e4b629f84f89786af5befb0bc75b6e66be',
      ),
    );
    expect(
      a.message,
      Spake2.hexBytes(
        '04a56fa807caaa53a4d28dbb9853b9815c61a411118a6fe516a8798434751470f9010153ac33d0d5f2047ffdb1a3e42c9b4e6be662766e1eeb4116988ede5f912c',
      ),
    );
    expect(
      b.message,
      Spake2.hexBytes(
        '0406557e482bd03097ad0cbaa5df82115460d951e3451962f1eaf4367a420676d09857ccbc522686c83d1852abfa8ed6e4a1155cf8f1543ceca528afb591a1e0b7',
      ),
    );
    final server = Uint8List.fromList(ascii.encode('server'));
    final client = Uint8List.fromList(ascii.encode('client'));
    final ak = a.finish(b.message, a: server, b: client);
    final bk = b.finish(a.message, a: server, b: client);
    expect(ak.sharedKey, Spake2.hexBytes('0e0672dc86f8e45565d338b0540abe69'));
    expect(bk.sharedKey, ak.sharedKey);
    expect(
      ak.confirmA,
      Spake2.hexBytes(
        '58ad4aa88e0b60d5061eb6b5dd93e80d9c4f00d127c65b3b35b1b5281fee38f0',
      ),
    );
    expect(
      bk.confirmB,
      Spake2.hexBytes(
        'd3e2e547f1ae04f2dbdbf0fc4b79f8ecff2dff314b5d32fe9fcef2fb26dc459b',
      ),
    );
    expect(() => a.finish(b.message, a: server, b: client), throwsStateError);
  });

  test('wrong PIN and off-curve public point fail authentication', () {
    final a = Spake2(isA: true, passwordScalar: BigInt.from(1));
    final b = Spake2(isA: false, passwordScalar: BigInt.from(2));
    final ak = a.finish(b.message, a: Uint8List(0), b: Uint8List(0));
    final bk = b.finish(a.message, a: Uint8List(0), b: Uint8List(0));
    expect(Spake2Keys.equal(ak.confirmA, bk.confirmA), isFalse);
    final c = Spake2(isA: true, passwordScalar: BigInt.one);
    expect(
      () => c.finish(Uint8List(65)..[0] = 4, a: Uint8List(0), b: Uint8List(0)),
      throwsFormatException,
    );
  });
}
