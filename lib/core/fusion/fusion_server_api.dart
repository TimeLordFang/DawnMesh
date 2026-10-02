import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../internet/internet_models.dart';

/// A failed fusion endpoint does not mean the phone has lost Internet access.
class FusionServerException implements Exception {
  const FusionServerException(this.message);
  final String message;
  @override
  String toString() => message;

  static void checkStatus(int status, {bool uploading = false}) {
    if (status == HttpStatus.ok) return;
    throw FusionServerException(switch (status) {
      401 => '服务器访问凭证无效，请检查服务器设置',
      403 when uploading => '服务器拒绝房间同步，请检查凭证及手机和服务器时间',
      403 => '服务器拒绝访问，请检查访问凭证',
      404 || 405 => '服务器未提供融合房接口，请更新服务端或检查地址',
      409 => '服务器房间状态已更新，正在重新同步',
      429 => '服务器繁忙，稍后自动重试',
      _ => '融合房服务器请求失败（HTTP $status），自动重试中',
    });
  }

  static String describe(Object error) => switch (error) {
    FusionServerException() => error.message,
    HandshakeException() => '服务器安全连接失败，请检查证书',
    TimeoutException() => '连接融合房服务器超时，自动重试中',
    WebSocketException() => '公网中继未接通，请检查服务端及 WebSocket 转发',
    FormatException() => '服务器返回的数据不兼容，请检查服务端版本及地址',
    SocketException() => '暂时无法连接融合房服务器，自动重试中',
    _ => '融合房同步未完成，自动重试中',
  };
}

class FusionServerApi {
  static Uri endpoint(ServerProfile profile, String suffix) {
    final base = Uri.parse(profile.baseUrl);
    return base.replace(
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/api/v1/fusion$suffix',
      query: null,
      fragment: null,
    );
  }

  static Future<List<Map<String, dynamic>>> rooms(
    HttpClient client,
    ServerProfile profile,
  ) async {
    const timeout = Duration(seconds: 4);
    final request = await client
        .getUrl(endpoint(profile, '/rooms'))
        .timeout(timeout);
    request.followRedirects = false;
    if (profile.accessToken.isNotEmpty) {
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${profile.accessToken}',
      );
    }
    final response = await request.close().timeout(timeout);
    if (response.statusCode != 200) {
      await response.drain<void>().timeout(timeout);
      FusionServerException.checkStatus(response.statusCode);
    }
    final text = await response.transform(utf8.decoder).join().timeout(timeout);
    final data = jsonDecode(text) as Map<String, dynamic>;
    if (data['protocolVersion'] != 1 || data['rooms'] is! List) {
      throw const FormatException('Unsupported fusion directory');
    }
    return (data['rooms'] as List)
        .whereType<Map<String, dynamic>>()
        .where(
          (room) =>
              validFusionRoomId(room['id']) &&
              (room['name'] == null || room['name'] is String) &&
              (room['members'] == null || room['members'] is List),
        )
        .take(256)
        .toList();
  }
}

bool validFusionRoomId(Object? value) =>
    value is String && RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(value);
