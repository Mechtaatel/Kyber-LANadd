import 'package:collection/collection.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/kyber/models/mode.dart';
import 'package:kyber_launcher/features/map_rotation/services/custom_rotation_service.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';

class MapHelper {
  static Map<String, String> getServerMap(Server server) {
    final level = server.levelSetup;
    final modeMap = getMode(level.mode)?.mapOverrides?.firstWhereOrNull(
      (entry) => entry.map.toLowerCase() == level.map.toLowerCase(),
    );
    final knownMap = KyberMapService.maps.firstWhereOrNull(
      (entry) => entry['map']?.toLowerCase() == level.map.toLowerCase(),
    );
    return {
      'map': level.map,
      'name': level.mapName.isNotEmpty
          ? level.mapName
          : modeMap?.name ??
                knownMap?['name'] ??
                (level.map.isEmpty ? 'Loading map' : level.map),
    };
  }

  static KyberMap? getMap(String mode, String map) {
    final kMap = getMapsForMode(mode).where((x) => x.map == map).firstOrNull;
    /*if (kMap == null) {
      final kMap = maps.firstWhereOrNull((e) => e['map'] == map);
      if (kMap != null) {
        return KyberMap(map: kMap['map']!, name: kMap['name']!);
      }
    }*/

    return kMap;
  }

  static Mode? getMode(String mode) {
    return KyberMapService.gameModes
        .where((element) => element.mode == mode)
        .firstOrNull;
  }

  static AssetGenImage? getImageForMap(String map) {
    if (map.isEmpty) {
      return Assets.images.kyberNoImage;
    }

    final image = Assets.images.maps.values.firstWhereOrNull(
      (x) =>
          x.path.toLowerCase().contains(map.replaceAll('/', '-').toLowerCase()),
    );
    if (image != null) {
      return image;
    }

    return Assets.images.kyberNoImage;
  }

  static List<KyberMap> getMapsForMode(String x) {
    final mode = KyberMapService.gameModes
        .where((element) => element.mode == x)
        .firstOrNull;
    if (mode == null) {
      return [];
    }

    return mode.maps.map((e) {
      final override = mode.mapOverrides?.firstWhere(
        (x) => x.map == e,
        orElse: () => MapOverride(map: '', name: ''),
      );
      if (override != null && override.name != '') {
        return KyberMap(map: override.map, name: override.name);
      }
      return KyberMap(
        map: e,
        name:
            KyberMapService.maps.firstWhere(
              (element) => element['map'] == e,
            )['name'] ??
            '',
      );
    }).toList();
  }

  static String getMapName(Mode mode, String map) {
    if (mode.mapOverrides != null &&
        mode.mapOverrides!.where((x) => x.map == map).isNotEmpty) {
      return mode.mapOverrides!.firstWhere((x) => x.map == map).name;
    }

    return KyberMapService.maps.firstWhere((x) => x['map'] == map)['name']!;
  }
}
