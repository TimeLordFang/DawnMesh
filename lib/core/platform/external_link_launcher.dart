import 'package:flutter/services.dart';

class ExternalLinkLauncher {
  ExternalLinkLauncher._();

  static const privacyPolicyUrl =
      'https://dawnmesh.timelord.info/privacy/';

  static const MethodChannel _channel = MethodChannel(
    'dev.dawnmesh.intercom/external_links',
  );

  static Future<bool> openGithubRelease(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.toLowerCase() != 'github.com' ||
        !uri.path.startsWith('/TimeLordFang/DawnMesh/releases')) {
      return false;
    }
    return _open(uri.toString());
  }

  static Future<bool> openPrivacyPolicy() => _open(privacyPolicyUrl);

  static Future<bool> _open(String url) async {
    try {
      return await _channel.invokeMethod<bool>('openUrl', <String, String>{
            'url': url,
          }) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
