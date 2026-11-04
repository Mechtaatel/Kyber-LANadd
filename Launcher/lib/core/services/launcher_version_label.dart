import 'package:flutter/services.dart';

Future<String> getLauncherVersionLabel() async {
  final version = (await rootBundle.loadString(
    'assets/lan_add_version.txt',
  )).trim();
  final displayVersion = version.replaceFirstMapped(
    RegExp(r'^(\d+\.\d+)\.0(?=-|$)'),
    (match) => match[1]!,
  );
  return 'KYBER Launcher LANadd $displayVersion';
}
