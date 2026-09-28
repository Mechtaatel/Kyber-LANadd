import 'dart:io';

import 'package:kyber_collection/kyber_collection.dart';
import 'package:path/path.dart';

class ModHelper {
  ModHelper._();

  static List<FrostyMod> filterGameplayMods(List<FrostyMod> mods) {
    return mods
        .where(
          (mod) => [
            'gameplay',
            'maps',
            'map',
          ].contains(mod.details.category.toLowerCase()),
        )
        .toList();
  }

  static List<FrostyMod> expandMods(List<FrostyMod> mods) {
    final expanded = <FrostyMod>[];
    for (final mod in mods) {
      if (!mod.isCollection) {
        expanded.add(mod);
      } else {
        for (final modPath in getCollectionMods(mod)) {
          final mod = File(modPath);
          if (!mod.existsSync()) {
            continue;
          }

          final frostyMod = ModReader(mod.openSync(), modPath).readMod();
          if (frostyMod == null) {
            continue;
          }

          expanded.add(frostyMod);
        }
      }
    }

    return expanded;
  }

  static List<String> getCollectionMods(FrostyMod mod) {
    final collectionDirName = dirname(mod.filename);
    if (collectionDirName == '.') {
      return mod.mods ?? [];
    }

    return mod.mods
            ?.map(
              (path) => normalize(
                join(dirname(mod.filename), path.replaceAll('\\', '/')),
              ),
            )
            .toList() ??
        [];
  }

  static List<FrostyMod> readFrostyMods(List<String> modPaths) {
    final fbMods = <FrostyMod>[];
    for (final mod in modPaths) {
      final modFile = File(mod);
      if (!modFile.existsSync()) {
        continue;
      }

      final modExtension = extension(mod);
      late FrostyMod? frostyMod;
      if (modExtension == '.fbmod') {
        frostyMod = ModReader(modFile.openSync(), mod).readMod();
      } else if (modExtension == '.fbcollection') {
        frostyMod = FrostyCollectionReader(modFile.openSync(), mod).readMod();
      } else {
        continue;
      }

      if (frostyMod == null) {
        continue;
      }

      fbMods.add(frostyMod);
    }

    return fbMods;
  }
}
