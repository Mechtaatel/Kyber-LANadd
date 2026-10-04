import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/services/lan_add_update_service.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/core/services/windows_utils.dart';
import 'package:kyber_launcher/features/maxima/services/maxima_instance_service.dart';
import 'package:kyber_launcher/gen/rust/api/archive.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/main.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:rhttp/rhttp.dart';

enum VersionModule {
  //launcher,
  module,
  installer,
}

extension VersionModuleExtension on VersionModule {
  Future<String?> getCurrentVersion() async {
    switch (this) {
      case VersionModule.module:
        final x = File(
          join(FileHelper.getOfficialModuleDirectory().path, 'VERSION'),
        );

        if (!x.existsSync()) {
          return null;
        }

        return x.readAsStringSync().trim();
      case VersionModule.installer:
        return (await rootBundle.loadString(
          'assets/lan_add_version.txt',
        )).trim();
    }
  }

  Future<String> getDownloadDir() async {
    switch (this) {
      case VersionModule.installer:
        final tmpDir = await getTemporaryDirectory();

        return join(
          tmpDir.path,
          'kyber_launcher_${DateTime.now().millisecondsSinceEpoch}',
        );
      case VersionModule.module:
        return FileHelper.getOfficialModuleDirectory().path;
    }
  }

  Future<void> setReleaseChannel(String channel) async {
    await box.put('${name}_release_channel', channel);
  }

  String get releaseChannel {
    return box.get('${name}_release_channel') as String? ??
        (this == VersionModule.installer ? 'beta' : 'stable');
  }

  List<String> get requiredFiles {
    switch (this) {
      case VersionModule.installer:
        return [];
      case VersionModule.module:
        final modulePath = FileHelper.getOfficialModuleDirectory().path;
        return [
          '$modulePath/ca_root.pem',
          '$modulePath/vivoxsdk.dll',
          '$modulePath/VanillaBundleAggregation.kb',
          '$modulePath/Kyber.dll',
        ];
    }
  }

  String get name {
    switch (this) {
      case VersionModule.installer:
        return 'kyber-lan-add-installer-win64';
      case VersionModule.module:
        return 'kyber-module';
    }
  }
}

class ModuleVersionService {
  final _logger = Logger('version_service');

  Future<bool> checkChannel({
    required VersionModule module,
    required String channel,
  }) async {
    if (module == VersionModule.installer) {
      return channel == 'stable' || channel == 'beta';
    }

    final rq = ServiceVersionsRequest(id: module.name, channel: channel);
    final versions = await sl.get<KyberGRPCService>().launcherClient.versions(
      rq,
    );
    return versions.versions.isNotEmpty &&
        versions.versions.firstWhereOrNull((x) => x.isLatest) != null;
  }

  Future<bool> updateAvailable({
    required VersionModule module,
    String? channel,
    KyberGRPCService? service,
  }) async {
    if (module == VersionModule.installer) {
      if (!Platform.isWindows) return false;
      try {
        final latest = await LanAddUpdateService().latest(
          channel: channel ?? module.releaseChannel,
        );
        final current = await module.getCurrentVersion();
        return latest != null && current != null && latest.isNewerThan(current);
      } on Object catch (error, stack) {
        _logger.warning('LAN ADD update check failed', error, stack);
        return false;
      }
    }
    channel ??= module.releaseChannel;
    final rq = ServiceVersionsRequest(id: module.name, channel: channel);
    final versions = await (service ?? sl.get<KyberGRPCService>())
        .launcherClient
        .versions(rq);

    final currentVersion = await module.getCurrentVersion();
    final latestVersion = versions.versions.firstWhereOrNull((x) => x.isLatest);
    if (currentVersion == null) {
      _logger.info('No version found for ${module.name}.');
      return true;
    }

    if (latestVersion == null) {
      _logger.info(
        'No latest version found for ${module.name}. Switching to stable.',
      );
      await module.setReleaseChannel('stable');
      return true;
    }

    final updateAvailable = latestVersion.version != currentVersion;

    if (updateAvailable) {
      _logger.info(
        'New version available for ${module.name}: ${latestVersion.version}',
      );
      return true;
    }

    if (module.requiredFiles.any((x) => !File(x).existsSync())) {
      _logger.info('Required files missing for ${module.name}.');
      return true;
    }

    return false;
  }

  Future<void> updateVersion({
    required VersionModule module,
    String? channel,
    String? token,
    KyberGRPCService? service,
    void Function(int, int)? onProgress,
  }) async {
    if (module == VersionModule.installer) {
      await _updateLanAdd(channel: channel, onProgress: onProgress);
      return;
    }

    final x = service ?? sl.get<KyberGRPCService>();
    channel ??= module.releaseChannel;
    final versions = await x.launcherClient.versions(
      ServiceVersionsRequest(id: module.name, channel: channel),
    );
    final latestVersion = versions.versions
        .where((x) => x.isLatest)
        .firstOrNull;

    if (latestVersion == null) {
      NotificationService.showNotification(
        message:
            'No latest version found for "${module.name}" on channel "$channel".',
      );
      _logger.warning('No latest version found for ${module.name}');
      return;
    }

    _logger.info('Updating ${module.name} to version ${latestVersion.version}');

    final download = await x.launcherClient.downloadUrl(
      ServiceVersionDownloadUrlRequest(
        id: module.name,
        version: latestVersion.version,
        channel: channel,
      ),
    );
    final filename = basename(download.url).split('?').first;
    final downloadDir = await module.getDownloadDir();
    final downloadPath = join(downloadDir, filename);

    _logger.fine('Downloading to $downloadPath');

    final file = File(downloadPath);
    if (file.existsSync()) {
      file.deleteSync();
    }

    file.createSync(recursive: true);

    final raf = file.openSync(mode: FileMode.write);

    try {
      final stream = await Rhttp.getStream(
        download.url,
        onReceiveProgress: onProgress,
      );

      await stream.body.forEach(raf.writeFromSync);
    } finally {
      raf.closeSync();
    }

    if (!Directory(downloadDir).existsSync()) {
      Directory(downloadDir).createSync();
    }

    _logger.fine('Extracting artifact...');

    await extract(filePath: downloadPath, targetDir: downloadDir);

    if (module == VersionModule.module) {
      // Kyber updates replace the stock DLL; restore our localization and LAN
      // support after refreshing the official module's remaining files.
      await FileHelper.installLanAddDllForOnline();
    }

    File(downloadPath).deleteSync();

    await box.put(module.name, latestVersion.version);
    File(
      join(FileHelper.getOfficialModuleDirectory().path, 'VERSION'),
    ).writeAsStringSync(latestVersion.version);

    _logger.info('Updated ${module.name} to version ${latestVersion.version}');
  }

  Future<String?> getLatestLauncherVersion([String? releaseChannel]) async {
    try {
      final release = await LanAddUpdateService().latest(
        channel: releaseChannel ?? VersionModule.installer.releaseChannel,
      );
      return release?.version.toString();
    } on Object catch (error, stack) {
      _logger.warning('LAN ADD update check failed', error, stack);
      return null;
    }
  }

  Future<void> _updateLanAdd({
    String? channel,
    void Function(int, int)? onProgress,
  }) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('LAN ADD automatic installation is Windows-only');
    }
    void checkGameClosed() {
      if (sl.isRegistered<MaximaInstanceService>() &&
          sl.get<MaximaInstanceService>().instances.isNotEmpty) {
        throw StateError('Close Battlefront II before updating LAN ADD.');
      }
    }

    checkGameClosed();
    final updater = LanAddUpdateService();
    final release = await updater.latest(
      channel: channel ?? VersionModule.installer.releaseChannel,
      refresh: true,
    );
    final current = await VersionModule.installer.getCurrentVersion();
    if (release == null || current == null || !release.isNewerThan(current)) {
      throw StateError(
        'No newer LAN ADD release is available on this channel.',
      );
    }
    final directory = Directory(await VersionModule.installer.getDownloadDir());
    _logger.info('Downloading LAN ADD ${release.version} from GitHub');
    final installer = await updater.download(
      release,
      directory,
      onProgress: onProgress,
    );
    checkGameClosed();
    _logger.info('Verified LAN ADD installer SHA-256: ${release.sha256Digest}');
    WindowsUtils.startUpdateInstaller(installer.path);
    // ShellExecuteEx has completed the UAC prompt and started the installer.
    // Close our files before Inno Setup replaces the application.
    try {
      await box.close();
      await collectionBox.close();
      await mapRotationBox.close();
    } finally {
      exit(0);
    }
  }
}
