import 'dart:async';
import 'dart:math';

import 'package:fixnum/fixnum.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' as grpc;
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/kyber/models/modes.dart';
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

  Future<void> loadServers() async {
    if (LanMode.enabled) {
      emit(const ModerationServersLoaded([]));
      return;
    }
    emit(const ModerationServersLoading());
    try {
      final token = sl.get<KyberGRPCService>().token;
      final servers = await sl
          .get<KyberGRPCService>()
          .serverManagementClient
          .moderatedServers(Empty());
      if (Preferences.admin.dummyServer) {
        servers.servers.add(KyberDummyServer(title: 'Dummy Server'));
      }

      final sorted = servers.servers
        ..sort((a, b) => b.playerCount.compareTo(a.playerCount));

      emit(ModerationServersLoaded(sorted));
    } catch (e) {
      if (e is grpc.GrpcError) {
        NotificationService.error(
          message: 'Failed to load servers: ${e.message}',
        );
        return emit(const ModerationServersLoaded([]));
      }

      NotificationService.error(message: 'Failed to load servers: $e');

      rethrow;
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
