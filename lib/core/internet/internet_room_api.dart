import 'dart:convert';

import 'package:http/http.dart' as http;

import 'internet_models.dart';

class InternetApiException implements Exception {
  const InternetApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class InternetRoomApi {
  InternetRoomApi(this.profile, {http.Client? client})
    : _client = client ?? _NoRedirectClient(http.Client());

  final ServerProfile profile;
  final http.Client _client;

  Uri _uri(String path) {
    final base = Uri.parse(profile.baseUrl);
    final prefix = base.path.endsWith('/')
        ? base.path.substring(0, base.path.length - 1)
        : base.path;
    return base.replace(path: '$prefix$path', query: null, fragment: null);
  }

  Map<String, String> get _headers => {
    'accept': 'application/json',
    'content-type': 'application/json',
    if (profile.accessToken.isNotEmpty)
      'authorization': 'Bearer ${profile.accessToken}',
  };

  Map<String, String> _sessionHeaders(String sessionToken) => {
    ..._headers,
    'x-dawn-session': sessionToken,
  };

  Future<Map<String, dynamic>> _decode(Future<http.Response> request) async {
    final response = await request.timeout(const Duration(seconds: 12));
    Map<String, dynamic> body = const {};
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw InternetApiException(
          '服务器返回了无法识别的数据',
          statusCode: response.statusCode,
        );
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw InternetApiException(
        body['error'] as String? ?? '服务器请求失败（${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
    return body;
  }

  Future<InternetServerInfo> info() async => InternetServerInfo.fromJson(
    await _decode(_client.get(_uri('/api/v1/info'), headers: _headers)),
  );

  Future<List<InternetRoomSummary>> rooms() async {
    final body = await _decode(
      _client.get(_uri('/api/v1/rooms'), headers: _headers),
    );
    return (body['rooms'] as List<dynamic>? ?? const [])
        .map(
          (item) => InternetRoomSummary.fromJson(item as Map<String, dynamic>),
        )
        .toList(growable: false);
  }

  Future<InternetConnectionGrant> createRoom({
    required String name,
    required String nickname,
    required String deviceId,
    required int maxParticipants,
    required int hostDisconnectTimeoutMinutes,
  }) async => InternetConnectionGrant.fromJson(
    await _decode(
      _client.post(
        _uri('/api/v1/rooms'),
        headers: _headers,
        body: jsonEncode({
          'name': name,
          'nickname': nickname,
          'deviceId': deviceId,
          'maxParticipants': maxParticipants,
          'hostDisconnectTimeoutMinutes': hostDisconnectTimeoutMinutes,
        }),
      ),
    ),
  );

  Future<InternetAdmissionGrant> beginAdmission({
    required String roomId,
    required String nickname,
    required String deviceId,
  }) async => InternetAdmissionGrant.fromJson(
    await _decode(
      _client.post(
        _uri('/api/v1/rooms/$roomId/admissions'),
        headers: _headers,
        body: jsonEncode({'nickname': nickname, 'deviceId': deviceId}),
      ),
    ),
  );

  Future<InternetConnectionGrant> resume({
    required String roomId,
    required String memberId,
    required String resumeToken,
  }) async => InternetConnectionGrant.fromJson(
    await _decode(
      _client.post(
        _uri('/api/v1/rooms/$roomId/resume'),
        headers: _headers,
        body: jsonEncode({'memberId': memberId, 'resumeToken': resumeToken}),
      ),
    ),
  );

  Future<void> renameRoom(
    String roomId,
    String name,
    String sessionToken,
  ) async {
    await _decode(
      _client.patch(
        _uri('/api/v1/rooms/$roomId'),
        headers: _sessionHeaders(sessionToken),
        body: jsonEncode({'name': name}),
      ),
    );
  }

  Future<void> setVoicePolicy(
    String roomId,
    String memberId,
    bool canSpeak,
    String sessionToken,
  ) async {
    await _decode(
      _client.put(
        _uri('/api/v1/rooms/$roomId/members/$memberId/voice-policy'),
        headers: _sessionHeaders(sessionToken),
        body: jsonEncode({'canSpeak': canSpeak}),
      ),
    );
  }

  Future<void> handover(
    String roomId,
    String memberId,
    String sessionToken,
  ) async {
    await _decode(
      _client.post(
        _uri('/api/v1/rooms/$roomId/handover'),
        headers: _sessionHeaders(sessionToken),
        body: jsonEncode({'memberId': memberId}),
      ),
    );
  }

  Future<void> leave(
    String roomId,
    String memberId,
    String resumeToken, {
    required bool endRoom,
  }) async {
    final path = endRoom
        ? '/api/v1/rooms/$roomId'
        : '/api/v1/rooms/$roomId/members/$memberId';
    await _decode(
      _client.delete(
        _uri(path),
        headers: _sessionHeaders(resumeToken),
        body: jsonEncode({'resumeToken': resumeToken}),
      ),
    );
  }

  void close() => _client.close();
}

class _NoRedirectClient extends http.BaseClient {
  _NoRedirectClient(this._inner);
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.followRedirects = false;
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
}
