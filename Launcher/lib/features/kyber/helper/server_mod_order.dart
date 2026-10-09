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

/// Extra client cosmetics are allowed; only the host's required files/order
/// must match the files already loaded into this game process.
bool hasRequiredServerModOrder(
  Iterable<String> loadedPaths,
  Iterable<String> requiredPaths, {
  bool? windowsPaths,
}) {
  final windows = windowsPaths ?? Platform.isWindows;
  final required = requiredPaths.map((p) => _modPathKey(p, windows)).toList();
  final requiredSet = required.toSet();
  final loadedRequired = loadedPaths
      .map((p) => _modPathKey(p, windows))
      .where(requiredSet.contains)
      .toList();
  if (required.length != loadedRequired.length) return false;
  for (var i = 0; i < required.length; i++) {
    if (required[i] != loadedRequired[i]) return false;
  }
  return true;
}
