import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'lan_add_update_service.dart';

class LanModuleUpdater {
  LanModuleUpdater(this.releases);

  final LanAddUpdateService releases;

  Future<void> update(Directory root, {required String channel}) async {
    // Update an existing LAN distribution, which supplies the companion files.
    if (!await File(p.join(root.path, 'LAN-MODULE')).exists()) return;
    final release = await releases
        .latest(channel: channel, component: LanAddComponent.module)
        .timeout(const Duration(seconds: 4));
    if (release == null) return;

    final lock = await File(
      p.join(root.path, 'update.lock'),
    ).open(mode: FileMode.append);
    Directory? staging;
    try {
      await lock.lock(FileLock.exclusive);
      final dll = File(p.join(root.path, 'Kyber.dll'));
      final versionFile = File(p.join(root.path, 'VERSION'));
      final tag = '$lanModuleTagPrefix${release.version}';
      final current = await versionFile.exists()
          ? (await versionFile.readAsString()).trim()
          : '';
      if (current.startsWith(lanModuleTagPrefix) &&
          Version.parse(current.substring(lanModuleTagPrefix.length)) >
              release.version)
        return;

      // A retry can finish publishing VERSION if the process exited after replacing the DLL.
      final matches =
          await dll.exists() &&
          await dll.length() == release.size &&
          (await sha256.bind(dll.openRead()).first).toString() ==
              release.sha256Digest;
      if (matches && current == tag) return;
      staging = await root.createTemp('.lan-update-');
      final nextVersion = await File(
        p.join(staging.path, 'VERSION'),
      ).writeAsString(tag, flush: true);
      if (!matches) {
        final verified = await releases.download(release, staging);
        await verified.rename(dll.path);
      }
      await nextVersion.rename(versionFile.path);
    } finally {
      try {
        if (staging != null) await staging.delete(recursive: true);
      } finally {
        await lock.close();
      }
    }
  }
}
