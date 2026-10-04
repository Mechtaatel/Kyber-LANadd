import 'dart:io';

import 'package:kyber_collection/kyber_collection.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Show the version of the selected module, not a hard-coded fork release.
Future<String> getLauncherVersionLabel() async {
  final info = await PackageInfo.fromPlatform();
  final directory = FileHelper.getLanModuleDirectory();
  var moduleVersion = '—';
  try {
    if (await File('${directory.path}/LAN-MODULE').exists()) {
      final version = await File('${directory.path}/VERSION').readAsString();
      final number = RegExp(r'\d+(?:[.-]\d+)*$').firstMatch(version.trim());
      if (number != null) moduleVersion = number.group(0)!;
    }
  } on FileSystemException {
    // A missing/unreadable version marker must not hide the launcher version.
  }
  return 'VERSION: ${info.version}#CL${info.buildNumber}\nLAN ADD $moduleVersion';
}
