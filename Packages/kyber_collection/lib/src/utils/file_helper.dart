import 'dart:io';

class FileHelper {
  FileHelper._();

  static Directory getLauncherDirectory() {
    final baseDir = Directory(
      Platform.isWindows ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers\\Kyber\\Launcher' : '${Platform.environment['HOME']}/.local/share/kyber/launcher',
    );

    return baseDir;
  }

  static Directory getArmchairDirectory() {
    final baseDir = Directory(
      Platform.isWindows ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers' : '${Platform.environment['HOME']}/.local/share/kyber',
    );

    return baseDir;
  }

  static Directory getModuleDirectory() {
    // A fork bundle has an isolated module; upstream updates must not replace it.
    final bundled = Directory('${File(Platform.resolvedExecutable).parent.path}/lan-module');
    if (File('${bundled.path}/LAN-MODULE').existsSync()) return bundled;
    final baseDir = Directory(
      Platform.isWindows ? '${Platform.environment['ProgramData']}\\Kyber\\Module' : '${Platform.environment['HOME']}/.local/share/kyber/module',
    );

    return baseDir;
  }

  static bool get hasPinnedLanModule =>
      File('${getModuleDirectory().path}/LAN-MODULE').existsSync();

  static Directory getModsDirectory() {
    final baseDir = Directory(
      Platform.isWindows ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers\\Kyber\\Mods' : '${Platform.environment['HOME']}/.local/share/kyber/mods',
    );

    return baseDir;
  }

  static Directory getCollectionDirectory() {
    final baseDir = Directory(
      Platform.isWindows ? '${Platform.environment['APPDATA']}\\ArmchairDevelopers\\Kyber\\Mods' : '${Platform.environment['HOME']}/.local/share/kyber/mods',
    );

    return baseDir;
  }
}
