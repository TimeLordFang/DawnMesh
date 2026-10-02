import 'dart:convert';
import 'dart:io';

import 'package:dawn_mesh/core/fusion/fusion_server_api.dart';
import 'package:dawn_mesh/core/internet/internet_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'old server and bad credentials are not reported as an Internet outage',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final client = HttpClient();
      addTearDown(() async {
        client.close(force: true);
        await server.close(force: true);
      });
      var code = 404;
      server.listen((request) async {
        expect(request.uri.path, '/prefix/api/v1/fusion/rooms');
        expect(request.headers.value('authorization'), 'Bearer test');
        request.response.statusCode = code;
        if (code == 200) {
          request.response.write(
            jsonEncode({
              'protocolVersion': 1,
              'rooms': [
                {
                  'id': 'a' * 43,
                  'name': '融合房',
                  'members': [{}],
                },
                {'id': 'b' * 43, 'name': 123},
              ],
            }),
          );
        }
        await request.response.close();
      });
      final profile = ServerProfile(
        id: 'test',
        name: 'test',
        baseUrl: 'http://127.0.0.1:${server.port}/prefix/',
        accessToken: 'test',
      );
      await expectLater(
        FusionServerApi.rooms(client, profile),
        throwsA(
          isA<FusionServerException>().having(
            (e) => e.message,
            'message',
            contains('更新服务端'),
          ),
        ),
      );
      code = 401;
      await expectLater(
        FusionServerApi.rooms(client, profile),
        throwsA(
          isA<FusionServerException>().having(
            (e) => e.message,
            'message',
            contains('访问凭证'),
          ),
        ),
      );
      code = 200;
      expect(await FusionServerApi.rooms(client, profile), hasLength(1));
    },
  );
}
