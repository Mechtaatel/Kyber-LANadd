import 'dart:io';

import 'package:kyber_cli/utils/windows_env.dart';
import 'package:kyber_collection/kyber_collection.dart';

class EnvHelper {
  EnvHelper._();

  static void setPath([String? customPath]) {
    final path = Platform.environment['PATH'];
    if (path == null) {
      throw Exception('PATH environment variable is not set');
    }

    final separator = Platform.isWindows ? ';' : ':';
    final newPath =
        '$path$separator${customPath ?? FileHelper.getModuleDirectory().path}';
    Env.set('PATH', newPath);
  }
}
