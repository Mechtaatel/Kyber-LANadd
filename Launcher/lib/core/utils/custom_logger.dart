import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/core/utils/log_archive.dart';
import 'package:kyber_launcher/gen/rust/api/maxima.dart' as mx;
import 'package:kyber_launcher/main.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class CustomLogger {
  static late File _logFile;

  static void initialize({bool isIsolate = false}) {
    _logFile = File(join(applicationDocumentsDirectory, 'log.txt'));
    if (!isIsolate) {
      _createLogFile();
    }

    Logger.root.level = Level.INFO;
    Logger.root.onRecord.listen(
      (record) async {
        final loggerName = record.loggerName.isEmpty
            ? 'root'
            : record.loggerName;

        final errorMessage = record.error != null
            ? ' - ${record.error}${record.stackTrace != null ? ' \n\nStackTrace:\n${record.stackTrace}' : ''}'
            : '';
        final message =
            '${record.level.name} - [$loggerName] - ${record.message}$errorMessage';

        if (kDebugMode) {
          print(message);
        }

        if (!isIsolate) {
          _logToFile(
            "[${DateTime.now().toString().split('.').first}] $message",
          );
        }
      },
    );

    FlutterError.onError = (details) {
      Logger.root.severe(
        'Uncaught exception: ${details.exception}\n${details.stack}',
      );
      Sentry.captureException(details.exception, stackTrace: details.stack);
    };
  }

  static void setupRustLogs() {
    final debugLogsEnabled = Preferences.debug.frbDebugLogs;
    if (debugLogsEnabled) {
      PlatformInAppWebViewController.debugLoggingSettings.enabled = true;
      PlatformInAppWebViewController.debugLoggingSettings.usePrint = true;
      Logger.root.level = Level.ALL;
    }

    mx.setupLogStream().listen((event) {
      final Level level = switch (event.logLevel) {
        mx.Level.debug => .FINE,
        mx.Level.error => .SEVERE,
        mx.Level.info => .INFO,
        mx.Level.trace => .ALL,
        mx.Level.warn => .WARNING,
      };

      final loggerName = event.lbl.isEmpty ? 'root' : event.lbl;
      Logger(loggerName).log(level, event.msg);
    });
  }

  static bool _logExportInProgress = false;

  static Future<void> requestLogExport() async {
    if (_logExportInProgress) return;
    _logExportInProgress = true;
    try {
      Directory? downloads;
      try {
        downloads = await getDownloadsDirectory();
      } catch (_) {
        // The native save dialog can still work without this optional location.
      }
      final name =
          'logs_${DateTime.now().toString().split('.').first.replaceAll(':', '-').replaceAll(' ', '_')}.zip';
      final file = await getSaveLocation(
        suggestedName: name,
        initialDirectory: downloads?.path,
        acceptedTypeGroups: const [
          XTypeGroup(label: 'Zip-Archive', extensions: ['zip']),
        ],
      );
      if (file == null) return;
      final outputPath = file.path;

      String? crashDumpsDirectory;
      try {
        final documents = await getApplicationDocumentsDirectory();
        crashDumpsDirectory = join(
          documents.path,
          'STAR WARS Battlefront II',
          'CrashDumps',
        );
      } catch (error, stack) {
        Logger(
          'log_export',
        ).warning('Could not locate crash dumps', error, stack);
      }

      final request = LogArchiveRequest(
        outputPath: outputPath,
        launcherLog: join(applicationDocumentsDirectory, 'log.txt'),
        maximaLog: join(
          Platform.environment['ProgramData'] ?? 'C:/ProgramData',
          'Maxima',
          'Logs',
          'MaximaBackgroundService.log',
        ),
        gameLogsDirectory: join(
          Platform.environment['APPDATA'] ??
              dirname(applicationDocumentsDirectory),
          'ArmchairDevelopers',
          'Kyber',
          'Logs',
        ),
        crashDumpsDirectory: crashDumpsDirectory,
        buildInfoPath: join(
          dirname(Platform.resolvedExecutable),
          'BUILD-INFO.json',
        ),
      );
      final warnings = await compute(createLogArchive, request);
      if (warnings.isEmpty) {
        NotificationService.success(message: 'Logs exported to $outputPath');
      } else {
        NotificationService.warning(
          message:
              'Logs exported to $outputPath. Some files were unavailable; see export-info.txt.',
        );
      }
    } catch (error, stack) {
      Logger('log_export').severe('Log export failed', error, stack);
      NotificationService.error(message: 'Could not export logs: $error');
    } finally {
      _logExportInProgress = false;
    }
  }

  static String getLogs() {
    return _logFile.readAsStringSync();
  }

  static void _logToFile(String message) {
    if (kDebugMode) {
      return;
    }

    try {
      _logFile.writeAsStringSync(
        '$message${Platform.lineTerminator}',
        mode: FileMode.writeOnlyAppend,
        flush: true,
      );
    } on FileSystemException catch (_) {}
  }

  static void clearLogFile() {
    _logFile.writeAsStringSync('');
  }

  static void _createLogFile() {
    if (!_logFile.existsSync()) {
      _logFile.createSync();
    }

    if (_logFile.lengthSync() > 1024 * 1024 * 5) {
      _logFile
        ..deleteSync()
        ..createSync();
    }
  }
}
