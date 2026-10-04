import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Keep the upstream launcher version separate from the LAN ADD release.
Future<String> getLauncherVersionLabel() async {
  final info = await PackageInfo.fromPlatform();
  final version = (await rootBundle.loadString(
    'assets/lan_add_version.txt',
  )).trim();
  return 'VERSION: ${info.version}#CL${info.buildNumber}\nLAN ADD $version';
}
