import 'dart:async';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

/// Keeps official releases separate from both the stock launcher and LAN DLLs.
class OfficialModuleUpdater {
  OfficialModuleUpdater({required this.root});

  final Directory root;
  static final _pending = <String, Future<Directory>>{};
  static const requiredFiles = [
    'Kyber.dll',
    'vivoxsdk.dll',
    'ca_root.pem',
    'VanillaBundleAggregation.kb',
  ];

  static bool validVersion(String value) =>
      RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$').hasMatch(value);

  Directory get activeDirectory {
    final pointer = File(p.join(root.path, 'ACTIVE'));
    if (!pointer.existsSync())
      return Directory(p.join(root.path, 'uninstalled'));
    final version = pointer.readAsStringSync().trim();
    if (!validVersion(version)) {
      return Directory(p.join(root.path, 'uninstalled'));
    }
    return Directory(p.join(root.path, version));
  }

  static Future<bool> complete(Directory directory, String version) async {
    final marker = File(p.join(directory.path, 'VERSION'));
    if (!await marker.exists() ||
        (await marker.readAsString()).trim() != version)
      return false;
    for (final name in requiredFiles) {
      final file = File(p.join(directory.path, name));
      if (!await file.exists() || await file.length() == 0) return false;
    }
    return true;
  }

  Future<Directory> install({
    required String version,
    required Uri downloadUrl,
    int? expectedSize,
    void Function(int, int)? onProgress,
  }) {
    if (!validVersion(version)) {
      throw ArgumentError.value(version, 'version', 'Invalid module version');
    }
    final key = root.absolute.path;
    final pending = _pending[key];
    if (pending != null) {
      return pending.then(
        (_) => install(
          version: version,
          downloadUrl: downloadUrl,
          expectedSize: expectedSize,
          onProgress: onProgress,
        ),
      );
    }
    return _pending.putIfAbsent(
      key,
      () => _install(version, downloadUrl, expectedSize, onProgress)
          .whenComplete(() {
            _pending.remove(key);
          }),
    );
  }

  Future<Directory> _install(
    String version,
    Uri url,
    int? expectedSize,
    void Function(int, int)? onProgress,
  ) async {
    await root.create(recursive: true);
    final lock = await File(
      p.join(root.path, 'update.lock'),
    ).open(mode: FileMode.append);
    Directory? staging;
    try {
      await lock.lock(FileLock.blockingExclusive);
      final destination = Directory(p.join(root.path, version));
      if (!await complete(destination, version)) {
        staging = await root.createTemp('.download-');
        final zip = File(p.join(staging.path, 'module.zip'));
        await _download(url, zip, expectedSize, onProgress);
        final payload = await Directory(
          p.join(staging.path, 'payload'),
        ).create();
        final archive = ZipDecoder().decodeBytes(
          await zip.readAsBytes(),
          verify: true,
        );
        final extracted = <String>{};
        for (final entry in archive) {
          if (!entry.isFile || entry.isSymbolicLink) continue;
          // The upstream archive is flat. Ignore scripts and unrelated files.
          if (!requiredFiles.contains(entry.name)) continue;
          if (!extracted.add(entry.name)) {
            throw FormatException('Duplicate module file: ${entry.name}');
          }
          await File(
            p.join(payload.path, entry.name),
          ).writeAsBytes(entry.content, flush: true);
        }
        await File(p.join(payload.path, 'VERSION')).writeAsString(version);
        if (!await complete(payload, version)) {
          throw const FormatException('Official module archive is incomplete');
        }

        Directory? previous;
        if (await destination.exists()) {
          previous = await destination.rename(p.join(staging.path, 'previous'));
        }
        try {
          await payload.rename(destination.path);
        } on Object {
          if (previous != null) await previous.rename(destination.path);
          rethrow;
        }
      }
      // Publish only after every payload file and its CRC has been verified.
      // A failed transfer never changes the active, usable release.
      final pointerStage = await root.createTemp('.activate-');
      try {
        final pointer = await File(
          p.join(pointerStage.path, 'ACTIVE'),
        ).writeAsString(version, flush: true);
        await pointer.rename(p.join(root.path, 'ACTIVE'));
      } finally {
        await pointerStage.delete(recursive: true);
      }
      return destination;
    } finally {
      try {
        if (staging != null) await staging.delete(recursive: true);
      } finally {
        await lock.close();
      }
    }
  }

  Future<void> _download(
    Uri url,
    File file,
    int? expectedSize,
    void Function(int, int)? onProgress,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    RandomAccessFile? output;
    try {
      final request = await client
          .getUrl(url)
          .timeout(const Duration(seconds: 30));
      request.headers.set(HttpHeaders.userAgentHeader, 'Kyber-LAN-ADD-Updater');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Module download failed (${response.statusCode})');
      }
      final total = expectedSize != null && expectedSize > 0
          ? expectedSize
          : response.contentLength;
      var received = 0;
      output = await file.open(mode: FileMode.write);
      await for (final bytes in response.timeout(const Duration(seconds: 60))) {
        received += bytes.length;
        if (total > 0 && received > total) {
          throw const FormatException('Module download exceeds expected size');
        }
        await output.writeFrom(bytes);
        onProgress?.call(received, total);
      }
      await output.flush();
      if (received == 0 || total > 0 && received != total) {
        throw const FormatException('Module download is incomplete');
      }
    } finally {
      try {
        await output?.close();
      } finally {
        client.close(force: true);
      }
    }
  }
}
