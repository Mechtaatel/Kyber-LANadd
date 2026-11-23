import 'dart:io';

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

  static Directory getGameModuleDirectory({required bool lanOnly}) {
    if (!lanOnly) return getOfficialModuleDirectory();
    final bundled = getLanModuleDirectory();
    // Portable builds keep the LAN module next to the launcher.
    if (!Platform.isWindows ||
        File('${bundled.path}/LAN-MODULE').existsSync()) {
      return bundled;
    }
    return Directory('${getOfficialModuleDirectory().parent.path}/LAN-Modules');
  }

  static const modulePayloadFiles = OfficialModuleUpdater.requiredFiles;

  static Directory getModsDirectory() {
    final baseDir = Directory(
      Platform.isWindows
          ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers\\Kyber\\Mods'
          : '${Platform.environment['HOME']}/.local/share/kyber/mods',
    );

    return baseDir;
  }

  static Directory getCollectionDirectory() => getModsDirectory();
}
