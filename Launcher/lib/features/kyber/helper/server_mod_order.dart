import 'dart:io';

import 'package:kyber_collection/kyber_collection.dart';
import 'package:path/path.dart' as path;

String _modPathKey(String filename, bool windows) {
  final context = path.Context(
    style: windows ? path.Style.windows : path.Style.posix,
  );
  final key = context.normalize(filename);
  return windows ? key.toLowerCase() : key;
}

/// Inputs must have their .fbcollection members expanded in collection order.
List<CollectionMod> mergeServerModOrder(
  Iterable<CollectionMod> requiredMods,
  Iterable<CollectionMod> extraMods, {
  bool? windowsPaths,
}) {
  final windows = windowsPaths ?? Platform.isWindows;
  final ordered = <CollectionMod>[];
  final seen = <String>{};
  for (final mod in [...requiredMods, ...extraMods]) {
    var key = mod.filename == null
        ? '${mod.name} (${mod.version})'
        : _modPathKey(mod.filename!, windows);
    if (windows) key = key.toLowerCase();
    if (seen.add(key)) ordered.add(mod);
  }
  return ordered;
}

/// Compare the expanded selection with the snapshot taken at game launch.
/// Server requirements and the selected client cosmetics are both included.
bool hasSameModLoadOrder(
  Iterable<CollectionMod> loadedMods,
  Iterable<CollectionMod> requestedMods, {
  bool? windowsPaths,
}) {
  final windows = windowsPaths ?? Platform.isWindows;
  final loaded = loadedMods.toList();
  final requested = requestedMods.toList();
  if (loaded.length != requested.length) return false;
  for (var i = 0; i < loaded.length; i++) {
    final a = loaded[i];
    final b = requested[i];
    if (a.filename == null ||
        b.filename == null ||
        _modPathKey(a.filename!, windows) !=
            _modPathKey(b.filename!, windows) ||
        a.name != b.name ||
        a.version != b.version) {
      return false;
    }
  }
  return true;
}
