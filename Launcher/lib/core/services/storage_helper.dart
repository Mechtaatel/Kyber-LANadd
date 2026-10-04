import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:graphql_flutter/graphql_flutter.dart';
import 'package:hive_ce/hive.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/module_version_service.dart';
import 'package:kyber_launcher/features/map_rotation/models/map_rotation_entry.dart';
import 'package:kyber_launcher/main.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class StorageHelper {
  static String getCacheDir() {
    final systemTempDir = Directory.systemTemp;
    return join(systemTempDir.path, 'kyber_launcher');
  }

  static Future<void> initializeHive() async {
    Logger('bootstrap').info('Initializing Hive');
    Hive.init(applicationDocumentsDirectory);
    await initHiveForFlutter(subDir: applicationDocumentsDirectory);
    Hive
      ..registerAdapter(MapRotationEntryAdapter(), override: true)
      ..registerAdapter(ModCollectionMetaDataAdapter(), override: true)
      ..registerAdapter(CollectionModAdapter(), override: true);

    box = await _openBox('data');
    try {
      if (Preferences.general.sentryOptedOut) {
        await Sentry.close();
      }
    } catch (e) {}

    mapRotationBox = await _openBox('mapRotation');
    collectionBox = await _openBox<ModCollectionMetaData>('collections');

    //CachedNetworkImageProvider.defaultCacheManager = KyberImageCacheManager();
  }

  static Future<void> saveCurrentVersion() async {
    await box.put(
      VersionModule.installer.name,
      await VersionModule.installer.getCurrentVersion(),
    );
  }

  static Future<Box<T>> _openBox<T>(String name) async {
    return Hive.openBox<T>(name).catchError((e) {
      if (kDebugMode) {
        return null;
      }

      Logger('bootstrap').severe('Error opening box: $e');
      exit(1);
    });
  }
}
