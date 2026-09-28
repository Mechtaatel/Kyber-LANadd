import 'dart:io';

import 'package:kyber_collection/kyber_collection.dart';
import 'package:mason_logger/mason_logger.dart';
import 'package:path/path.dart';

class CollectionHelper {
  final _logger = Logger();

  List<String> getModsList(
    ModCollectionMetaData metaData, {
    bool listFrostyCollectionMods = true,
  }) => [
    for (final mod in metaData.mods)
      if (mod.isCollection && listFrostyCollectionMods)
        ...mod.mods!
      else
        mod.filename!,
  ].map((file) => normalize(file.replaceAll(r'\', '/'))).toList();

  String getModsDirectory() => FileHelper.getCollectionDirectory().path;

  Future<void> useCollection(File collectionFile) async {
    if (!collectionFile.existsSync()) {
      throw Exception('Collection file not found');
    }

    final metaData = await ModCollection.readCollection(collectionFile);
    _logger.info(
      'Loading Mod Collection "${metaData.title}" with ${metaData.mods.length} mods',
    );

    if (await ModCollection.hasFileData(collectionFile)) {
      _logger.info('Extracting Collection');
      await ModCollection.extractCollection(collectionFile);
      _logger.info('Extracting done.');
    }
  }
}
