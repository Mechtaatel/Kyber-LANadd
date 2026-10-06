import 'dart:io';

import 'package:crypto/crypto.dart';

/// Maxima's Windows service passes UTF-8 bytes to LoadLibraryA. Keep its
/// injection path ASCII until the service supports LoadLibraryW.
Future<Directory> prepareModuleLaunchDirectory(
  Directory source, {
  Directory? cacheRoot,
}) async {
  bool isAscii(String path) => path.codeUnits.every((unit) => unit < 128);
  if (isAscii(source.absolute.path)) return source;

  final root =
      cacheRoot ??
      Directory(
        '${Platform.environment['ProgramData'] ?? 'C:/ProgramData'}/Kyber/LAN-Modules',
      );
  if (!isAscii(root.absolute.path)) {
    throw StateError(
      'The Kyber module needs a folder without non-ASCII characters.',
    );
  }
  final hash = await sha256
      .bind(File('${source.path}/Kyber.dll').openRead())
      .first;
  final target = Directory('${root.path}/$hash');
  await target.create(recursive: true);
  // Copy only module payload, never game files, mods or account data.
  await for (final entry in source.list()) {
    if (entry is! File) continue;
    final name = entry.uri.pathSegments.last;
    if (!name.toLowerCase().endsWith('.dll') &&
        !const {
          'ca_root.pem',
          'VanillaBundleAggregation.kb',
          'VERSION',
          'LAN-ADD-VERSION',
          'LAN-MODULE',
        }.contains(name)) {
      continue;
    }
    final destination = File('${target.path}/$name');
    final expected = await sha256.bind(entry.openRead()).first;
    if (await destination.exists() &&
        await sha256.bind(destination.openRead()).first == expected) {
      continue;
    }
    await entry.copy(destination.path);
    if (await sha256.bind(destination.openRead()).first != expected) {
      throw StateError('Kyber module copy verification failed: $name');
    }
  }
  return target;
}
