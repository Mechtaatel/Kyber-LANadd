import 'dart:async';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:kyber_cli/command_runner.dart';
import 'package:kyber_cli/gen/frb_generated.dart';
import 'package:path/path.dart' as p;
import 'package:sentry/sentry.dart';

Future<void> main(List<String> args) async {
  // Resolve the packaged ABI partner next to the executable, independent of
  // the working directory and LD_LIBRARY_PATH (e.g. when started by systemd).
  final executableDirectory = File(Platform.resolvedExecutable).parent.path;
  final libraryName = Platform.isWindows ? 'rust_lib.dll' : 'librust_lib.so';
  // Release archives are flat; `dart build cli` uses bin/ and lib/.
  final bundledLibrary = [
    File(p.join(executableDirectory, libraryName)),
    File(p.join(executableDirectory, '..', 'lib', libraryName)),
  ].where((file) => file.existsSync()).firstOrNull;
  await RustLib.init(
    externalLibrary: bundledLibrary != null
        ? ExternalLibrary.open(bundledLibrary.path)
        : null,
  );
  await runZonedGuarded(
    () async {
      await Sentry.init((options) {
        options.dsn =
            'https://6908d6215588b605347d1d446f0bb5ce@sentry.kyber.gg/5';
      });

      await _flushThenExit(await KyberCliCommandRunner().run(args));
    },
    (exception, stackTrace) async {
      await Sentry.captureException(exception, stackTrace: stackTrace);
      print(
        'An error occurred. Please try again later.\n${exception.toString()}\n${stackTrace.toString()}',
      );
      exit(1);
    },
  );
}

Future<void> _flushThenExit(int status) {
  return Future.wait<void>([
    stdout.close(),
    stderr.close(),
  ]).then<void>((_) => exit(status));
}
