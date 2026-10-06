import 'dart:io';

import 'package:crypto/crypto.dart';

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

  static Directory getGameModuleDirectory({required bool lanOnly}) {
    if (!lanOnly) return getOfficialModuleDirectory();
    final bundled = getLanModuleDirectory();
    if (!File('${bundled.path}/LAN-MODULE').existsSync()) {
      throw StateError(
          'LAN module is missing. Restore the complete LAN ADD package: ${bundled.path}');
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

  static Future<bool> isLanAddModuleInstalledForOnline() async {
    await validateBundledModule();
    final target = getOfficialModuleDirectory();
    for (final name in modulePayloadFiles) {
      final file = File('${target.path}/$name');
      if (!await file.exists() || await file.length() == 0) return false;
    }
    final bundled = getLanModuleDirectory();
    final version = File('${target.path}/LAN-ADD-VERSION');
    if (!await version.exists() ||
        (await version.readAsString()).trim() !=
            (await File('${bundled.path}/VERSION').readAsString()).trim()) {
      return false;
    }
    return await sha256
            .bind(File('${target.path}/Kyber.dll').openRead())
            .first ==
        await sha256.bind(File('${bundled.path}/Kyber.dll').openRead()).first;
  }

  /// Install the fork's localization/LAN DLL over the stock DLL for online use.
  /// Bootstrap missing dependencies locally, without an upstream download.
  /// Save the original once so uninstalling LAN ADD can restore it.
  static Future<File> installLanAddDllForOnline() =>
      _onlineInstall ??= _installLanAddDllForOnline().whenComplete(() {
        _onlineInstall = null;
      });

  static Future<File>? _onlineInstall;

  static Future<File> _installLanAddDllForOnline() async {
    await validateBundledModule();
    final bundled = getLanModuleDirectory();
    final source = File('${bundled.path}/Kyber.dll');

    final moduleDirectory = getOfficialModuleDirectory();
    await moduleDirectory.create(recursive: true);
    for (final name in [
      ...modulePayloadFiles.skip(1),
      'msvcp140.dll',
      'vcruntime140.dll',
      'vcruntime140_1.dll',
    ]) {
      final dependency = File('${bundled.path}/$name');
      final installed = File('${moduleDirectory.path}/$name');
      if (await dependency.exists() &&
          (!await installed.exists() || await installed.length() == 0)) {
        await _copyVerified(dependency, installed);
      }
    }
    final target = File('${moduleDirectory.path}/Kyber.dll');
    final sourceHash = await sha256.bind(source.openRead()).first;
    if (!await target.exists() ||
        await sha256.bind(target.openRead()).first != sourceHash) {
      final backup = File('${target.path}.lan-add-original');
      if (await target.exists() && !await backup.exists()) {
        await _copyVerified(target, backup);
      }
      await _copyVerified(source, target);
    }
    // Keep upstream VERSION intact: its UUID does not identify the fork DLL.
    await _copyVerified(File('${bundled.path}/VERSION'),
        File('${moduleDirectory.path}/LAN-ADD-VERSION'));
    return target;
  }

  static Future<void> _copyVerified(File source, File target) async {
    final staging = await target.parent.createTemp('.lan-add-');
    try {
      final copy = await source.copy('${staging.path}/payload');
      if (await sha256.bind(copy.openRead()).first !=
          await sha256.bind(source.openRead()).first) {
        throw StateError(
            'LAN ADD module copy verification failed: ${target.path}');
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
