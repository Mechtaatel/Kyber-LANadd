import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

const lanAddRepository = 'Mechtaatel/Kyber-LANadd';
const lanAddReleasesUrl = 'https://github.com/$lanAddRepository/releases';

class LanAddRelease {
  const LanAddRelease({
    required this.version,
    required this.installerName,
    required this.downloadUrl,
    required this.size,
    required this.sha256Digest,
  });

  final Version version;
  final String installerName;
  final Uri downloadUrl;
  final int size;
  final String sha256Digest;

  static LanAddRelease? select(
    List<dynamic> releases, {
    required String channel,
  }) {
    if (channel != 'stable' && channel != 'beta') {
      throw ArgumentError.value(channel, 'channel', 'Use stable or beta');
    }
    LanAddRelease? latest;
    for (final entry in releases) {
      if (entry is! Map<String, dynamic> || entry['draft'] != false) continue;
      final name = (entry['name'] as String? ?? '').trim();
      final body = entry['body'] as String? ?? '';
      if (RegExp(r'^\[?BROKEN\b', caseSensitive: false).hasMatch(name) ||
          body.contains('<!-- lan-add-update: disabled -->')) {
        continue;
      }
      final tag = entry['tag_name'];
      if (tag is! String) continue;
      final Version version;
      try {
        version = Version.parse(tag.replaceFirst(RegExp('^v'), ''));
      } on FormatException {
        continue;
      }
      if (channel == 'stable' &&
          (entry['prerelease'] == true || version.isPreRelease)) {
        continue;
      }
      final assets = entry['assets'];
      if (assets is! List) continue;
      final installers = assets.whereType<Map<String, dynamic>>().where((
        asset,
      ) {
        final filename = asset['name'];
        return filename is String &&
            RegExp(
              r'^Kyber-LAN-ADD-[A-Za-z0-9._-]+-Setup\.exe$',
            ).hasMatch(filename) &&
            asset['state'] == 'uploaded';
      }).toList();
      // A release must identify one Windows installer unambiguously.
      if (installers.length != 1) continue;
      final asset = installers.single;
      final digest = asset['digest'];
      final size = asset['size'];
      final url = asset['browser_download_url'];
      if (digest is! String ||
          !RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest) ||
          size is! int ||
          size <= 0 ||
          url is! String) {
        continue;
      }
      final uri = Uri.tryParse(url);
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host != 'github.com' ||
          uri.userInfo.isNotEmpty ||
          !uri.path.startsWith('/$lanAddRepository/releases/download/$tag/')) {
        continue;
      }
      final release = LanAddRelease(
        version: version,
        installerName: asset['name'] as String,
        downloadUrl: uri,
        size: size,
        sha256Digest: digest.substring('sha256:'.length).toLowerCase(),
      );
      if (latest == null || release.version > latest.version) latest = release;
    }
    return latest;
  }

  bool isNewerThan(String installed) => version > Version.parse(installed);
}

class LanAddUpdateService {
  static const _requestTimeout = Duration(seconds: 20);
  static final _cache = <String, (DateTime, LanAddRelease?)>{};

  Future<LanAddRelease?> latest({
    String channel = 'beta',
    bool refresh = false,
  }) async {
    final cached = _cache[channel];
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.$1) < const Duration(minutes: 5)) {
      return cached.$2;
    }
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    try {
      final request = await client
          .getUrl(
            Uri.parse(
              'https://api.github.com/repos/$lanAddRepository/releases?per_page=100',
            ),
          )
          .timeout(_requestTimeout);
      request.headers
        ..set(HttpHeaders.userAgentHeader, 'Kyber-LAN-ADD-Updater')
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set('X-GitHub-Api-Version', '2022-11-28');
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'GitHub release check failed (${response.statusCode})',
        );
      }
      final body = await response
          .timeout(_requestTimeout)
          .transform(utf8.decoder)
          .join();
      final decoded = jsonDecode(body);
      if (decoded is! List) throw const FormatException('Invalid release list');
      final release = LanAddRelease.select(decoded, channel: channel);
      _cache[channel] = (DateTime.now(), release);
      return release;
    } finally {
      client.close(force: true);
    }
  }

  Future<File> download(
    LanAddRelease release,
    Directory destination, {
    void Function(int, int)? onProgress,
  }) async {
    await destination.create(recursive: true);
    final file = File(p.join(destination.path, release.installerName));
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    RandomAccessFile? output;
    try {
      final request = await client
          .getUrl(release.downloadUrl)
          .timeout(_requestTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'Kyber-LAN-ADD-Updater');
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Installer download failed (${response.statusCode})',
        );
      }
      var received = 0;
      output = await file.open(mode: FileMode.write);
      await for (final bytes in response.timeout(const Duration(seconds: 60))) {
        received += bytes.length;
        if (received > release.size) {
          throw const FormatException('Installer exceeds the published size');
        }
        await output.writeFrom(bytes);
        onProgress?.call(received, release.size);
      }
      await output.flush();
      await output.close();
      output = null;
      if (received != release.size) {
        throw const FormatException('Installer download is incomplete');
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != release.sha256Digest) {
        throw const FormatException('Installer SHA-256 verification failed');
      }
      return file;
    } catch (_) {
      await output?.close();
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}
