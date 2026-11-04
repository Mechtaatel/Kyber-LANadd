import 'dart:async';

import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/features/mods/constants/categories.dart';

class MaximaGameInstance {
  MaximaGameInstance({
    required this.pid,
    required this.isDedicated,
    required this.clientService,
    this.mods = const [],
    this.loadedModPaths = const [],
    this.loadedMods,
    this.voipSettings,
    this.lanOnly = false,
  }) {
    _eventStreamController = StreamController<String>.broadcast();
  }

  int pid;
  bool isDedicated;
  final bool lanOnly;
  ClientGRPCService clientService;
  List<FrostyMod> mods;
  final List<String> loadedModPaths;
  // Expanded user selection at launch, before automatic Kyber preloads.
  final List<CollectionMod>? loadedMods;
  VoipSettings? voipSettings;

  late StreamController<String> _eventStreamController;

  void addEvent(String event) {
    _eventStreamController.add(event);
  }

  Future<void> closeStream() async {
    await _eventStreamController.close();
  }

  Stream<String> get eventStream => _eventStreamController.stream;

  List<FrostyMod> get gameplayMods => mods
      .where(
        (m) => kRequiredCategories.contains(m.details.category.toLowerCase()),
      )
      .toList(growable: false);

  MaximaGameInstance copyWith({
    int? pid,
    bool? isDedicated,
    ClientGRPCService? clientService,
    List<FrostyMod>? mods,
    VoipSettings? voipSettings,
  }) {
    return MaximaGameInstance(
      pid: pid ?? this.pid,
      isDedicated: isDedicated ?? this.isDedicated,
      lanOnly: lanOnly,
      clientService: clientService ?? this.clientService,
      mods: mods ?? this.mods,
      loadedModPaths: loadedModPaths,
      loadedMods: loadedMods,
      voipSettings: voipSettings ?? this.voipSettings,
    );
  }
}
