import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:kyber_collection/src/utils/official_module_updater.dart';

class FileHelper {
  FileHelper._();

  static Directory getLauncherDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers\\Kyber\\Launcher'
          : '${Platform.environment['HOME']}/.local/share/kyber/launcher',
    );

    return baseDir;
  }

  static Directory getArmchairDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers'
          : '${Platform.environment['HOME']}/.local/share/kyber',
    );

    return baseDir;
  }

  static Directory getModuleDirectory() {
    // Preserve the CLI's bundle-first lookup. The launcher selects explicitly.
    final bundled = getLanModuleDirectory();
    if (File('${bundled.path}/LAN-MODULE').existsSync()) return bundled;
    return getOfficialModuleDirectory();
  }

  static Directory getLanModuleDirectory() =>
      Directory('${File(Platform.resolvedExecutable).parent.path}/lan-module');

  static Directory getOfficialModuleDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['ProgramData']}\\Kyber\\Module'
          : '${Platform.environment['HOME']}/.local/share/kyber/module',
    );

    return baseDir;
  }

  static bool get hasPinnedLanModule =>
      File('${getModuleDirectory().path}/LAN-MODULE').existsSync();

  static Directory getOnlineModuleRoot() => Directory(
    '${getOfficialModuleDirectory().parent.path}/LAN-Modules/online',
  );

  static Directory getOnlineModuleDirectory() =>
      OfficialModuleUpdater(root: getOnlineModuleRoot()).activeDirectory;

  static Directory getGameModuleDirectory({required bool lanOnly}) {
    if (!lanOnly) return getOnlineModuleDirectory();
    final bundled = getLanModuleDirectory();
    if (!File('${bundled.path}/LAN-MODULE').existsSync()) {
      throw StateError(
        'LAN module is missing. Restore the complete LAN ADD package: ${bundled.path}',
      );
    }
    return bundled;
  }

  static const modulePayloadFiles = [
    'Kyber.dll',
    'vivoxsdk.dll',
    'ca_root.pem',
    'VanillaBundleAggregation.kb',
  ];

  static Future<void> validateBundledModule() async {
    final bundled = getLanModuleDirectory();
    for (final name in ['LAN-MODULE', 'VERSION', ...modulePayloadFiles]) {
      final file = File('${bundled.path}/$name');
      if (!await file.exists() || await file.length() == 0) {
        throw StateError(
          'LAN ADD module file is missing or empty: ${file.path}. '
          'Reinstall the complete LAN ADD package.',
        );
      }
    }
  }

  /// Use the Unicode-enabled DLL only for its verified upstream release.
  /// Future official updates automatically use the newer official DLL.
  static Future<Directory> prepareOnlineModule({
    Directory? bundledDirectory,
    Directory? officialDirectory,
    Directory? cacheDirectory,
  }) async {
    final bundled = bundledDirectory ?? getLanModuleDirectory();
    final official = officialDirectory ?? getOnlineModuleDirectory();
    final compatibility = File('${bundled.path}/ONLINE-COMPATIBILITY.json');
    if (!await compatibility.exists()) return official;
    final Object? data;
    try {
      data = jsonDecode(await compatibility.readAsString());
    } on FormatException {
      return official;
    } on FileSystemException {
      return official;
    }
    if (data is! Map<String, dynamic>) return official;
    final version = File('${official.path}/VERSION');
    if (!await version.exists() ||
        (await version.readAsString()).trim() != data['officialVersion']) {
      return official;
    }
    final original = File('${official.path}/Kyber.dll');
    final source = File('${bundled.path}/Kyber.dll');
    if (!await source.exists() || !await original.exists()) return official;
    final originalHash = (await sha256.bind(original.openRead()).first)
        .toString();
    final sourceHash = (await sha256.bind(source.openRead()).first).toString();
    if (originalHash != data['officialDllSha256'] ||
        sourceHash != data['bundledDllSha256'])
      return official;

    final root = cacheDirectory ?? getOnlineModuleRoot();
    final target = Directory(
      '${root.path}/localized-$originalHash-$sourceHash',
    );
    await target.create(recursive: true);
    for (final name in [...modulePayloadFiles, 'VERSION']) {
      final input = name == 'Kyber.dll'
          ? source
          : File('${official.path}/$name');
      final output = File('${target.path}/$name');
      if (!await output.exists() ||
          await sha256.bind(input.openRead()).first !=
              await sha256.bind(output.openRead()).first) {
        await _copyVerified(input, output);
      }
    }
    for (final name in [
      'msvcp140.dll',
      'vcruntime140.dll',
      'vcruntime140_1.dll',
    ]) {
      final runtime = File('${bundled.path}/$name');
      if (await runtime.exists() &&
          !File('${target.path}/$name').existsSync()) {
        await _copyVerified(runtime, File('${target.path}/$name'));
      }
    }
    return target;
  }

  static Future<void> _copyVerified(File source, File target) async {
    final staging = await target.parent.createTemp('.lan-add-');
    try {
      final copy = await source.copy('${staging.path}/payload');
      if (await sha256.bind(copy.openRead()).first !=
          await sha256.bind(source.openRead()).first) {
        throw StateError(
          'LAN ADD module copy verification failed: ${target.path}',
        );
      }
      await copy.rename(target.path);
    } finally {
      await staging.delete(recursive: true);
    }
  }

  static Directory getModsDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers\\Kyber\\Mods'
          : '${Platform.environment['HOME']}/.local/share/kyber/mods',
    );

    return baseDir;
  }

  static Directory getCollectionDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers\\Kyber\\Mods'
          : '${Platform.environment['HOME']}/.local/share/kyber/mods',
    );

    return baseDir;
  }
}
