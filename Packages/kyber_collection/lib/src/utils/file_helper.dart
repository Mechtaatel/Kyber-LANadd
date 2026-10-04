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

  /// Install the fork's localization/LAN DLL over the stock DLL for online use.
  /// Save the original once so uninstalling LAN ADD can restore it.
  static Future<File> installLanAddDllForOnline() async {
    final bundled = getLanModuleDirectory();
    if (!File('${bundled.path}/LAN-MODULE').existsSync()) {
      throw StateError('LAN ADD module marker is missing: ${bundled.path}');
    }
    final source = File('${bundled.path}/Kyber.dll');
    if (!await source.exists() || await source.length() == 0) {
      throw StateError('LAN ADD Kyber.dll is missing or empty: ${source.path}');
    }

    final moduleDirectory = getOfficialModuleDirectory();
    await moduleDirectory.create(recursive: true);
    final target = File('${moduleDirectory.path}/Kyber.dll');
    final sourceHash = await sha256.bind(source.openRead()).first;
    if (await target.exists() &&
        await sha256.bind(target.openRead()).first == sourceHash) {
      return target;
    }

    final backup = File('${target.path}.lan-add-original');
    if (await target.exists() && !await backup.exists()) {
      await target.copy(backup.path);
    }
    await source.copy(target.path);
    if (await sha256.bind(target.openRead()).first != sourceHash) {
      throw StateError(
        'LAN ADD Kyber.dll copy verification failed: ${target.path}',
      );
    }
    return target;
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
