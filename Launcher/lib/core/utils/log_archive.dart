import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;

class LogArchiveRequest {
  const LogArchiveRequest({
    required this.outputPath,
    required this.launcherLog,
    required this.maximaLog,
    required this.gameLogsDirectory,
    this.crashDumpsDirectory,
    this.buildInfoPath,
  });

  final String outputPath;
  final String launcherLog;
  final String maximaLog;
  final String gameLogsDirectory;
  final String? crashDumpsDirectory;
  final String? buildInfoPath;
}

// Runs in a worker isolate: compressing a large game log must not freeze UI.
Future<List<String>> createLogArchive(LogArchiveRequest request) async {
  final warnings = <String>[];
  final files = <String, File>{
    'launcher-log.txt': File(request.launcherLog),
    'maxima-log.txt': File(request.maximaLog),
    if (request.buildInfoPath != null)
      'BUILD-INFO.json': File(request.buildInfoPath!),
  };

  Future<void> addLatest(
    String directory,
    bool Function(String) matches,
  ) async {
    File? newest;
    DateTime? modified;
    try {
      final dir = Directory(directory);
      if (!await dir.exists()) return;
      await for (final entry in dir.list(followLinks: false)) {
        if (entry is! File || !matches(p.basename(entry.path))) continue;
        try {
          final date = await entry.lastModified();
          if (modified == null || date.isAfter(modified)) {
            newest = entry;
            modified = date;
          }
        } on FileSystemException catch (error) {
          warnings.add('Cannot inspect ${entry.path}: $error');
        }
      }
      if (newest != null) files[p.basename(newest.path)] = newest;
    } on FileSystemException catch (error) {
      warnings.add('Cannot read $directory: $error');
    }
  }

  await addLatest(
    request.gameLogsDirectory,
    (name) => name.startsWith('kyber_'),
  );
  await addLatest(
    request.gameLogsDirectory,
    (name) => name.startsWith('kyber-server'),
  );
  if (request.crashDumpsDirectory != null) {
    await addLatest(
      request.crashDumpsDirectory!,
      (name) => name.endsWith('.mdmp') || name.endsWith('.dmp'),
    );
  }

  final staging = await Directory(
    p.dirname(request.outputPath),
  ).createTemp('.kyber-log-export-');
  final encoder = ZipFileEncoder();
  try {
    encoder.create(request.outputPath);
    try {
      for (final entry in files.entries) {
        try {
          if (!await entry.value.exists()) {
            if (await FileSystemEntity.type(entry.value.path) !=
                FileSystemEntityType.notFound) {
              warnings.add('Skipped ${entry.key}: the source is not a file');
            }
            continue;
          }
          // Snapshot a live log before encoding it; a missing/locked file must
          // not prevent exporting all the other diagnostic files.
          final snapshot = await entry.value.copy(
            p.join(staging.path, entry.key),
          );
          await encoder.addFile(snapshot, entry.key);
        } on FileSystemException catch (error) {
          warnings.add('Skipped ${entry.key}: $error');
        }
      }
      encoder.addArchiveFile(
        ArchiveFile.string(
          'export-info.txt',
          'Exported at ${DateTime.now().toUtc().toIso8601String()}\n'
              '${warnings.isEmpty ? 'All available log files collected.' : warnings.join('\n')}\n',
        ),
      );
    } finally {
      await encoder.close();
    }
  } finally {
    try {
      await staging.delete(recursive: true);
    } on FileSystemException catch (error) {
      warnings.add('Could not remove temporary snapshots: $error');
    }
  }
  return warnings;
}
