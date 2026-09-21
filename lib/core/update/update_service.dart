import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../diagnostics/app_log.dart';

sealed class UpdateState {
  const UpdateState();
}

class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate();
}

class UpdateAvailable extends UpdateState {
  final String versionName;
  final String releaseNotes;
  final String downloadUrl;

  const UpdateAvailable({
    required this.versionName,
    required this.releaseNotes,
    required this.downloadUrl,
  });
}

class UpdateFailed extends UpdateState {
  final String message;

  const UpdateFailed(this.message);
}

/// 语义化版本解析与比较（遵循 SemVer 2.0.0 规范）。
class SemVer implements Comparable<SemVer> {
  final int major;
  final int minor;
  final int patch;
  final List<String> preRelease;

  const SemVer({
    required this.major,
    required this.minor,
    required this.patch,
    this.preRelease = const [],
  });

  static SemVer? parse(String raw) {
    var v = raw.trim();
    if (v.startsWith('v') || v.startsWith('V')) {
      v = v.substring(1).trim();
    }
    if (v.isEmpty) return null;

    final buildIdx = v.indexOf('+');
    if (buildIdx != -1) v = v.substring(0, buildIdx);

    final dashIdx = v.indexOf('-');
    String mainPart = v;
    List<String> pre = [];
    if (dashIdx != -1) {
      mainPart = v.substring(0, dashIdx);
      final prePart = v.substring(dashIdx + 1);
      if (prePart.isNotEmpty) pre = prePart.split('.');
    }

    final segments = mainPart.split('.');
    if (segments.isEmpty || segments.length > 3) return null;
    final major = int.tryParse(segments[0]);
    final minor = segments.length > 1 ? int.tryParse(segments[1]) : 0;
    final patch = segments.length > 2 ? int.tryParse(segments[2]) : 0;
    if (major == null ||
        minor == null ||
        patch == null ||
        major < 0 ||
        minor < 0 ||
        patch < 0) {
      return null;
    }
    return SemVer(major: major, minor: minor, patch: patch, preRelease: pre);
  }

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    if (preRelease.isEmpty && other.preRelease.isNotEmpty) return 1;
    if (preRelease.isNotEmpty && other.preRelease.isEmpty) return -1;
    if (preRelease.isEmpty && other.preRelease.isEmpty) return 0;

    final maxLen = preRelease.length > other.preRelease.length
        ? preRelease.length
        : other.preRelease.length;
    for (int i = 0; i < maxLen; i++) {
      if (i >= preRelease.length) return -1;
      if (i >= other.preRelease.length) return 1;
      final a = preRelease[i];
      final b = other.preRelease[i];
      final aNum = int.tryParse(a);
      final bNum = int.tryParse(b);
      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else if (aNum != null) {
        return -1;
      } else if (bNum != null) {
        return 1;
      } else {
        final cmp = a.compareTo(b);
        if (cmp != 0) return cmp;
      }
    }
    return 0;
  }
}

class UpdateService {
  static const String currentVersion = '1.0.0-beta.12';
  static const String releasesPage =
      'https://github.com/TimeLordFang/DawnMesh/releases';
  static const String _releasesApi =
      'https://api.github.com/repos/TimeLordFang/DawnMesh/releases?per_page=20';
  static const Duration _timeout = Duration(seconds: 10);
  static const int _maxResponseBytes = 1024 * 1024;

  Future<UpdateState> checkUpdate() async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client
          .getUrl(Uri.parse(_releasesApi))
          .timeout(_timeout);
      request.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'DawnMesh/$currentVersion');
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        AppLog.warn('更新', 'GitHub Releases 返回 HTTP ${response.statusCode}');
        return UpdateFailed('HTTP ${response.statusCode}');
      }
      if (response.contentLength > _maxResponseBytes) {
        return const UpdateFailed('响应内容过大');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(_timeout)) {
        bytes.addAll(chunk);
        if (bytes.length > _maxResponseBytes) {
          return const UpdateFailed('响应内容过大');
        }
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      return stateFromGithubResponse(decoded, currentVersion: currentVersion);
    } on TimeoutException catch (error) {
      AppLog.warn('更新', '连接 GitHub 超时', error);
      return const UpdateFailed('连接超时');
    } on SocketException catch (error) {
      AppLog.warn('更新', '无法连接 GitHub', error);
      return const UpdateFailed('网络不可用');
    } on FormatException catch (error) {
      AppLog.warn('更新', 'GitHub 返回的数据格式无效', error);
      return const UpdateFailed('响应格式无效');
    } catch (error) {
      AppLog.warn('更新', '检查更新失败', error);
      return const UpdateFailed('未知错误');
    } finally {
      client.close(force: true);
    }
  }

  /// GitHub 的 latest API 不包含 prerelease，因此从 Releases 列表中选择
  /// 最高的非草稿版本，让 dev/beta 用户也能收到更新。
  static UpdateState stateFromGithubResponse(
    Object? decoded, {
    required String currentVersion,
  }) {
    if (decoded is! List) return const UpdateFailed('响应格式无效');

    SemVer? newest;
    String? newestTag;
    String newestNotes = '';
    String? newestUrl;
    for (final item in decoded) {
      if (item is! Map || item['draft'] == true) continue;
      final tag = item['tag_name'];
      final url = item['html_url'];
      if (tag is! String || url is! String || !_isAllowedReleaseUrl(url)) {
        continue;
      }
      final version = SemVer.parse(tag);
      if (version == null ||
          (newest != null && version.compareTo(newest) <= 0)) {
        continue;
      }
      newest = version;
      newestTag = tag.startsWith(RegExp(r'[vV]')) ? tag.substring(1) : tag;
      newestNotes = item['body'] is String ? item['body'] as String : '';
      newestUrl = url;
    }

    if (newest == null || newestTag == null || newestUrl == null) {
      return const UpdateUpToDate();
    }
    if (!isNewer(newestTag, currentVersion)) return const UpdateUpToDate();
    return UpdateAvailable(
      versionName: newestTag,
      releaseNotes: newestNotes,
      downloadUrl: newestUrl,
    );
  }

  static bool _isAllowedReleaseUrl(String raw) {
    final uri = Uri.tryParse(raw);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.toLowerCase() == 'github.com' &&
        uri.path.startsWith('/TimeLordFang/DawnMesh/releases/');
  }

  static bool isNewer(String remote, String current) {
    final remoteVer = SemVer.parse(remote);
    final currentVer = SemVer.parse(current);
    return remoteVer != null &&
        currentVer != null &&
        remoteVer.compareTo(currentVer) > 0;
  }
}
