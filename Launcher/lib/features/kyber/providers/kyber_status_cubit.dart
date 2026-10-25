import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/rich_presence.dart';
import 'package:kyber_launcher/core/services/voip_service.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';

class KyberStatusCubit extends Cubit<KyberStatusState> {
  bool joined = false;

  KyberStatusCubit() : super(KyberStatusInitial()) {
    _statusTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) async => onTick(),
    );

    _rpcServerTimer = Timer.periodic(
      const Duration(minutes: 2),
      (_) => _refreshPresence(),
    );
  }

  Future<void> _refreshPresence() async {
    if (isClosed || !sl.isRegistered<MaximaGameInstance>()) return;
    try {
      final instance = sl.get<MaximaGameInstance>();
      final info = await instance.clientService.commonClient.getInfo(Empty());
      if (isClosed) return;
      if (!info.hasServer() && !info.client.hasServerId()) {
        sl.get<RichPresence>().clearPresence();
        return;
      }

      final id = info.hasServer() ? info.server.id : info.client.serverId;
      if (id.isEmpty || instance.lanOnly || id.startsWith('lan:')) return;
      final client = sl.get<KyberGRPCService>();
      final server = await client.serverBrowserClient.getServer(
        ServerRequest(id: id),
      );
      if (isClosed) return;
      final current = state;
      if (current is KyberStatusHosting) {
        emit(
          KyberStatusHosting(
            serverState: current.serverState,
            server: server,
          ),
        );
      } else if (current is KyberStatusPlaying) {
        emit(
          KyberStatusPlaying(
            serverState: current.serverState,
            server: server,
            joined: joined,
          ),
        );
      } else {
        emit(KyberStatusNormal());
      }

      sl.get<RichPresence>().updatePresenceKyber(info, server);
    } catch (e, stack) {
      _logger.warning('Failed to refresh server presence', e, stack);
    }
  }

  Future<void> onTick() async {
    if (isClosed) return;
    final isRegistered = sl.isRegistered<MaximaGameInstance>();
    if (!isRegistered) {
      final rp = sl.get<RichPresence>();
      if (state is! KyberStatusInitial || rp.started != null) {
        sl.get<RichPresence>().clearPresence();
      }

      joined = false;

      return emit(KyberStatusInitial());
    }

    try {
      final client = sl.get<MaximaGameInstance>();
      final data = await client.clientService.commonClient.getInfo(Empty());
      if (isClosed) return;
      if (data.vivoxInitialized && client.voipSettings == null) {
        sl.get<VoipService>().setGameVoipSettings();
      }

      final isKyber = data.hasClient() || data.hasServer();
      final id = data.hasServer() ? data.server.id : data.client.serverId;
      // A game can report its server before registration has supplied an ID.
      // Do not advertise it as ready or send an empty ID to the public API.
      if (isKyber && id.isEmpty) {
        emit(KyberStatusNormal());
        return;
      }
      var server = (state is KyberStatusPlaying || state is KyberStatusHosting)
          ? ((state as dynamic).server as Server?)
          : null;
      if (server?.id != id) server = null;
      if (isKyber && server == null) {
        if (!client.lanOnly && !id.startsWith('lan:')) {
          final client = sl.get<KyberGRPCService>();
          server = await client.serverBrowserClient.getServer(
            ServerRequest(id: id),
          );
          if (isClosed) return;
          sl.get<RichPresence>().updatePresenceKyber(data, server);
        }
      }

      if (data.hasClient()) {
        emit(
          KyberStatusPlaying(
            serverState: data.server,
            server: server,
            joined: joined,
          ),
        );
      } else if (data.hasServer()) {
        emit(KyberStatusHosting(serverState: data.server, server: server));
      } else {
        emit(KyberStatusNormal());
      }
    } catch (e, stack) {
      if (e is GrpcError) {
        if (e.code == StatusCode.unavailable || e.code == StatusCode.unknown) {
          return;
        }

        _logger.severe('GRPC Error: ${e.message}');
      }

      _logger.warning('Failed to update game status', e, stack);
    }
  }

  final _logger = Logger('status_cubit');

  @override
  Future<void> close() {
    _statusTimer.cancel();
    _rpcServerTimer.cancel();
    return super.close();
  }

  late Timer _statusTimer;
  late Timer _rpcServerTimer;
}

class KyberStatusState {}

class KyberStatusInitial extends KyberStatusState {}

class KyberStatusNormal extends KyberStatusState {}

class KyberStatusPlaying extends KyberStatusState {
  KyberStatusPlaying({
    required this.serverState,
    this.server,
    this.joined = false,
  });

  final ServerState serverState;
  final Server? server;
  final bool joined;
}

class KyberStatusHosting extends KyberStatusState {
  KyberStatusHosting({required this.serverState, this.server});

  final ServerState serverState;
  final Server? server;
}
