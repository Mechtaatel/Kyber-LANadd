import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/services.dart';
import 'package:grpc/grpc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/services/lan_add_update_service.dart';
import 'package:kyber_launcher/core/services/windows_utils.dart';
import 'package:kyber_launcher/features/maxima/services/maxima_instance_service.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/main.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

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
          join(FileHelper.getOnlineModuleDirectory().path, 'VERSION'),
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
        return FileHelper.getOnlineModuleRoot().path;
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
        final modulePath = FileHelper.getOnlineModuleDirectory().path;
        return [
          for (final name in FileHelper.modulePayloadFiles) '$modulePath/$name',
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

    final response = await sl.get<KyberGRPCService>().launcherClient.versions(
      ServiceVersionsRequest(id: module.name, channel: channel),
      options: CallOptions(timeout: const Duration(seconds: 20)),
    );
    return response.versions.any((version) => version.isLatest);
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
    if (LanMode.enabled) return false;
    final latest = await _latestModule(channel: channel, service: service);
    return !await OfficialModuleUpdater.complete(
      FileHelper.getOnlineModuleDirectory(),
      latest.version.version,
    );
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

    final api = service ?? sl.get<KyberGRPCService>();
    final latest = await _latestModule(channel: channel, service: api);
    final download = await api.launcherClient.downloadUrl(
      ServiceVersionDownloadUrlRequest(
        id: module.name,
        channel: latest.channel,
        version: latest.version.version,
      ),
      options: CallOptions(timeout: const Duration(seconds: 20)),
    );
    _logger.info('Updating official Kyber module to ${latest.version.version}');
    await OfficialModuleUpdater(root: FileHelper.getOnlineModuleRoot()).install(
      version: latest.version.version,
      downloadUrl: Uri.parse(download.url),
      expectedSize: latest.version.size,
      onProgress: onProgress,
    );
    _logger.info('Official Kyber module ready: ${latest.version.version}');
  }

  Future<({String channel, ServiceVersion version})> _latestModule({
    String? channel,
    KyberGRPCService? service,
  }) async {
    final api = service ?? sl.get<KyberGRPCService>();
    var selected = channel ?? VersionModule.module.releaseChannel;
    for (var attempt = 0; attempt < 2; attempt++) {
      final response = await api.launcherClient.versions(
        ServiceVersionsRequest(
          id: VersionModule.module.name,
          channel: selected,
        ),
        options: CallOptions(timeout: const Duration(seconds: 20)),
      );
      final latest = response.versions.firstWhereOrNull(
        (entry) => entry.isLatest,
      );
      if (latest != null) return (channel: selected, version: latest);
      if (selected == 'stable') break;
      selected = 'stable';
      await VersionModule.module.setReleaseChannel(selected);
    }
    throw StateError('No official Kyber module is available on this channel.');
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
