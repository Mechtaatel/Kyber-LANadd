import 'dart:async';
import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/kyber/models/modes.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/injection_container.dart';

Server KyberDummyServer({
  String? title,
  String? creator,
  bool? requiredPassword,
  bool? isOfficial,
  int? playerCount,
}) {
  //final x = modes[Random().nextInt(modes.length)];
  final x = modes.first;
  final randomMap = x.maps[Random().nextInt(x.maps.length)];
  return Server(
    id: '-',
    official: isOfficial ?? false,
    maxPlayerCount: 40,
    playerCount: playerCount ?? Random().nextInt(40),
    name: title,
    levelSetup: LevelSetup(map: randomMap, mode: x.mode),
    requiresPassword: requiredPassword ?? false,
    creator: creator ?? 'Unknown',
    mods: [
      ServerMod(
        name: 'IOI - Instant Online Improvements V5',
        version: '5.0',
        link: 'https://www.nexusmods.com/starwarsbattlefront22017/mods/3658',
        fileSize: Int64(1700000),
      ),
      ServerMod(name: "IOI Addon - No Boundaries", version: '1.0'),
      ServerMod(name: "IOI Addon - Heroes Unrestricted", version: '1.0'),
    ],
  );
}

class ModerationServersCubit extends Cubit<ModerationServersState> {
  ModerationServersCubit() : super(const ModerationServersInitial()) {
    emit(const ModerationServersLoading());
    loadServers();
    _updateTimer = Timer.periodic(
      const Duration(minutes: 1, seconds: 30),
      (_) => loadServers(),
    );
  }

  @override
  Future<void> close() async {
    _updateTimer?.cancel();
    await super.close();
  }

  Timer? _updateTimer;
  int _loadGeneration = 0;

  Future<Server?> _hostedLanServer() async {
    if (!sl.isRegistered<MaximaGameInstance>()) return null;
    try {
      final info = await sl
          .get<MaximaGameInstance>()
          .clientService
          .commonClient
          .getInfo(Empty())
          .timeout(const Duration(seconds: 3));
      if (!info.hasServer() || !info.server.id.startsWith('lan:')) {
        return null;
      }

      // Discovery gives us the actual name, port and mod list. The local RPC
      // still lets HOST show its own server while the responder is starting.
      final discovered = await LanDiscovery().discover(
        timeout: const Duration(milliseconds: 600),
      );
      for (final server in discovered) {
        if (server.isLanOnly && server.ip == '127.0.0.1') {
          server
            ..id = info.server.id
            ..playerCount = info.server.playerList.length;
          return server;
        }
      }

      final fallback = Server(
        id: info.server.id,
        name: Preferences.hostServer.name,
        creator: 'LAN host',
        levelSetup: info.server.levelSetup,
        playerCount: info.server.playerList.length,
        maxPlayerCount: Preferences.hostServer.maxPlayers,
        ip: '127.0.0.1',
        port: 25200,
        region: 'LAN',
      );
      fallback.meta['lan_only'] = '1';
      return fallback;
    } catch (_) {
      // The game can disappear between registration and a refresh.
      return null;
    }
  }

  Future<void> loadServers() async {
    if (isClosed) return;
    final generation = ++_loadGeneration;
    final previous = state;
    if (previous is! ModerationServersLoaded) {
      emit(const ModerationServersLoading());
    }
    final local = await _hostedLanServer();
    if (isClosed || generation != _loadGeneration) return;
    // Local moderation must be available before the public API responds.
    // Keep public entries visible during refresh, but never cache a LAN host
    // whose local RPC no longer reports it running.
    final retained = previous is ModerationServersLoaded
        ? previous.servers.where((server) => !server.isLanOnly).toList()
        : <Server>[];
    emit(
      ModerationServersLoaded([
        if (local != null) local,
        if (!LanMode.enabled) ...retained,
      ]),
    );
    if (LanMode.enabled) {
      return;
    }
    try {
      final servers = await sl
          .get<KyberGRPCService>()
          .serverManagementClient
          .moderatedServers(
            Empty(),
            options: grpc.CallOptions(timeout: const Duration(seconds: 8)),
          );
      if (isClosed || generation != _loadGeneration) return;
      if (Preferences.admin.dummyServer) {
        servers.servers.add(KyberDummyServer(title: 'Dummy Server'));
      }

      final sorted = servers.servers
        ..sort((a, b) => b.playerCount.compareTo(a.playerCount));

      emit(
        ModerationServersLoaded([
          if (local != null) local,
          ...sorted.where((server) => server.id != local?.id),
        ]),
      );
    } catch (e) {
      if (isClosed || generation != _loadGeneration) return;
      if (local == null) {
        NotificationService.error(
          message:
              'Failed to load servers: ${e is grpc.GrpcError ? e.message : e}',
        );
      }
      emit(ModerationServersLoaded([if (local != null) local, ...retained]));
    }
  }
}

abstract class ModerationServersState {
  const ModerationServersState();
}

class ModerationServersInitial extends ModerationServersState {
  const ModerationServersInitial();
}

class ModerationServersLoading extends ModerationServersState {
  const ModerationServersLoading();
}

class ModerationServersLoaded extends ModerationServersState {
  const ModerationServersLoaded(this.servers);

  final List<Server> servers;
}
