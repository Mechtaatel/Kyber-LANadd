import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

const lanAddRepository = 'Mechtaatel/Kyber-LANadd';
const lanAddReleasesUrl = 'https://github.com/$lanAddRepository/releases';

enum LanAddComponent { launcher, module }

const lanModuleTagPrefix = 'lan-module-v';

class LanAddRelease {
  const LanAddRelease({
    required this.version,
    required this.assetName,
    required this.downloadUrl,
    required this.size,
    required this.sha256Digest,
  });

  final Version version;
  final String assetName;
  final Uri downloadUrl;
  final int size;
  final String sha256Digest;

  static LanAddRelease? select(
    List<dynamic> releases, {
    required String channel,
    LanAddComponent component = LanAddComponent.launcher,
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
        if (component == LanAddComponent.module) {
          if (!tag.startsWith(lanModuleTagPrefix)) continue;
          version = Version.parse(tag.substring(lanModuleTagPrefix.length));
        } else {
          version = Version.parse(tag.replaceFirst(RegExp('^v'), ''));
        }
      } on FormatException {
        continue;
      }
      if (channel == 'stable' &&
          (entry['prerelease'] == true || version.isPreRelease)) {
        continue;
      }
      final assets = entry['assets'];
      if (assets is! List) continue;
      final matchingAssets = assets.whereType<Map<String, dynamic>>().where((
        asset,
      ) {
        final filename = asset['name'];
        return filename is String &&
            (component == LanAddComponent.module
                ? filename == 'Kyber.dll'
                : RegExp(
                    r'^Kyber-LAN-ADD-[A-Za-z0-9._-]+-Setup\.exe$',
                  ).hasMatch(filename)) &&
            asset['state'] == 'uploaded';
      }).toList();
      if (matchingAssets.length != 1) continue;
      final asset = matchingAssets.single;
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
          uri.path !=
              '/$lanAddRepository/releases/download/$tag/${asset['name']}') {
        continue;
      }
      final release = LanAddRelease(
        version: version,
        assetName: asset['name'] as String,
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
  static List<dynamic> _releases = [];
  static DateTime? _cachedAt;
  static DateTime? _retryAfter;
  static Future<List<dynamic>>? _pending;

  Future<LanAddRelease?> latest({
    String channel = 'beta',
    bool refresh = false,
    LanAddComponent component = LanAddComponent.launcher,
  }) async {
    final now = DateTime.now();
    final fresh =
        _cachedAt != null &&
        now.difference(_cachedAt!) < const Duration(minutes: 5);
    final backedOff = _retryAfter != null && now.isBefore(_retryAfter!);
    final releases = backedOff || (!refresh && fresh)
        ? _releases
        : await (_pending ??= _fetchReleases().whenComplete(() {
            _pending = null;
          }));
    return LanAddRelease.select(
      releases,
      channel: channel,
      component: component,
    );
  }

  Future<List<dynamic>> _fetchReleases() async {
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    try {
      final releases = <dynamic>[];
      for (var page = 1; ; page++) {
        final request = await client
            .getUrl(
              Uri.https('api.github.com', '/repos/$lanAddRepository/releases', {
                'per_page': '100',
                'page': page.toString(),
              }),
            )
            .timeout(_requestTimeout);
        request.headers
          ..set(HttpHeaders.userAgentHeader, 'Kyber-LAN-ADD-Updater')
          ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
          ..set('X-GitHub-Api-Version', '2022-11-28');
        final response = await request.close().timeout(_requestTimeout);
        if (response.statusCode != HttpStatus.ok) {
          if (response.statusCode == HttpStatus.forbidden ||
              response.statusCode == HttpStatus.tooManyRequests) {
            final reset = int.tryParse(
              response.headers.value('x-ratelimit-reset') ?? '',
            );
            final now = DateTime.now();
            final wait = reset == null
                ? const Duration(minutes: 10)
                : DateTime.fromMillisecondsSinceEpoch(
                        reset * 1000,
                      ).difference(now) +
                      const Duration(seconds: 15);
            _retryAfter = now.add(
              wait < const Duration(minutes: 1)
                  ? const Duration(minutes: 1)
                  : wait > const Duration(hours: 1)
                  ? const Duration(hours: 1)
                  : wait,
            );
          }
          throw HttpException(
            'GitHub release check failed (${response.statusCode})',
          );
        }
        final body = await response
            .timeout(_requestTimeout)
            .transform(utf8.decoder)
            .join();
        final decoded = jsonDecode(body);
        if (decoded is! List)
          throw const FormatException('Invalid release list');
        releases.addAll(decoded);
        if (decoded.length < 100) break;
      }
      _releases = releases;
      _cachedAt = DateTime.now();
      _retryAfter = null;
      return releases;
    } on Object {
      if (_retryAfter == null || !_retryAfter!.isAfter(DateTime.now())) {
        _retryAfter = DateTime.now().add(const Duration(minutes: 2));
      }
      rethrow;
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
    final file = File(p.join(destination.path, release.assetName));
    final client = HttpClient()..connectionTimeout = _requestTimeout;
    RandomAccessFile? output;
    try {
      final request = await client
          .getUrl(
            release.downloadUrl.replace(
              queryParameters: {
                ...release.downloadUrl.queryParameters,
                'download': '1',
              },
            ),
          )
          .timeout(_requestTimeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'Kyber-LAN-ADD-Updater');
      final response = await request.close().timeout(_requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Asset download failed (${response.statusCode})',
        );
      }
      var received = 0;
      output = await file.open(mode: FileMode.write);
      await for (final bytes in response.timeout(const Duration(seconds: 60))) {
        received += bytes.length;
        if (received > release.size) {
          throw const FormatException('Asset exceeds the published size');
        }
        await output.writeFrom(bytes);
        onProgress?.call(received, release.size);
      }
      await output.flush();
      await output.close();
      output = null;
      if (received != release.size) {
        throw const FormatException('Asset download is incomplete');
      }
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != release.sha256Digest) {
        throw const FormatException('Asset SHA-256 verification failed');
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
