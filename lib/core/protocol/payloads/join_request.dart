import 'dart:convert';
import 'dart:typed_data';

import '../bounded_utf8.dart';

/// JOIN_REQ (0x02) Payload
/// Format: [1 byte nickname length][UTF-8 nickname][16 bytes session token]
class JoinRequestPayload {
  final String nickname;
  final Uint8List sessionToken;
  final bool textOnly;

  JoinRequestPayload({
    required this.nickname,
    required this.sessionToken,
    this.textOnly = false,
  });

  Uint8List encode() {
    final nickSub = boundedUtf8(nickname, 64);
    final clampedNickLen = nickSub.length;

    final tokenBytes = Uint8List(16);
    final copyLen = sessionToken.length.clamp(0, 16);
    tokenBytes.setRange(0, copyLen, sessionToken);

    final out = Uint8List(1 + clampedNickLen + 16 + (textOnly ? 1 : 0));
    out[0] = clampedNickLen;
    out.setRange(1, 1 + clampedNickLen, nickSub);
    out.setRange(1 + clampedNickLen, 1 + clampedNickLen + 16, tokenBytes);
    if (textOnly) out[out.length - 1] = 1;
    return out;
  }

  static JoinRequestPayload? decode(Uint8List bytes) {
    if (bytes.length < 17) return null;
    final nickLen = bytes[0];
    if (nickLen > 64 ||
        (bytes.length != 17 + nickLen &&
            !(bytes.length == 18 + nickLen && bytes.last == 1))) {
      return null;
    }

    String nick;
    try {
      nick = utf8.decode(bytes.sublist(1, 1 + nickLen));
    } on FormatException {
      return null;
    }
    final token = Uint8List(16);
    token.setRange(0, 16, bytes.sublist(1 + nickLen, 1 + nickLen + 16));

    return JoinRequestPayload(
      nickname: nick,
      sessionToken: token,
      textOnly: bytes.length == nickLen + 18,
    );
  }
}
