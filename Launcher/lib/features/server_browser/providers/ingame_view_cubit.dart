import 'dart:async';
import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class IngameViewCubit extends Cubit<IngameViewState> {
  IngameViewCubit() : super(const IngameViewState());

  final _logger = Logger('ingame_view_cubit');
  Timer? _keepAliveTimer;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  String? _loadingServerId;
  int _loadGeneration = 0;

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    unloadServer();
    return super.close();
  }

  void unloadServer() {
    _logger.info('Unloading server');
    _loadGeneration++;
    _loadingServerId = null;
    final channel = _channel;
    _channel = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    if (channel != null) unawaited(_closeChannel(channel));
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    if (!isClosed) emit(const IngameViewState());
  }

  Future<void> _closeChannel(WebSocketChannel channel) async {
    try {
      await channel.sink.close();
    } on Object catch (error) {
      _logger.fine('Server event channel already closed', error);
    }
  }

  Future<void> loadServer(Server server) async {
    if (isClosed) return;
    await selectServer(serverId: server.id);
  }

  Future<void> selectServer({String? serverId}) async {
    final id = serverId ?? state.id;
    if (isClosed || id == null) {
      return;
    }
    if (_loadingServerId == id || (_channel != null && state.id == id)) return;

    final generation = ++_loadGeneration;
    _loadingServerId = id;
    final previous = _channel;
    _channel = null;
    final previousSubscription = _subscription;
    _subscription = null;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;

    try {
      await previousSubscription?.cancel();
      if (previous != null) await _closeChannel(previous);
      if (isClosed || generation != _loadGeneration) return;
      _logger.info('Loading server $id');
      emit(IngameViewState(id: id));
      final service = sl.get<KyberGRPCService>();
      final server = await service.serverBrowserClient.getServer(
        ServerRequest(id: id),
      );
      if (isClosed || generation != _loadGeneration) return;
      emit(state.copyWith(id: id, server: server));

      _logger.info('Subscribing to server events');

      final channel = IOWebSocketChannel.connect(
        'wss://api.${Preferences.admin.apiEnv}.kyber.gg/ws/client/${server.id}',
        headers: {
          'Authorization': service.token,
        },
        connectTimeout: const Duration(seconds: 10),
      );

      _channel = channel;
      await channel.ready;
      if (isClosed || generation != _loadGeneration) {
        await _closeChannel(channel);
        return;
      }

      _subscription = channel.stream.listen(
        (event) {
          if (isClosed || !identical(_channel, channel)) return;
          try {
            final data = ServerManagementAPIEvent.fromBuffer(
              event as List<int>,
            );
            if (data.hasPlayers()) {
              _logger.fine('Received players event');
              emit(state.copyWith(players: data.players.players));
            } else if (data.hasConsole()) {
              _logger.fine('Received console event');
              final commands = List<String>.from(state.commands)
                ..add(data.console.message);
              emit(state.copyWith(commands: commands));
            }
          } catch (e, s) {
            _logger.severe('Error parsing event', e, s);
          }
        },
        onDone: () {
          if (!identical(_channel, channel)) return;
          _logger.info('Stream done');
          unloadServer();
        },
        onError: (dynamic e, StackTrace s) {
          if (!identical(_channel, channel)) return;
          NotificationService.showNotification(
            title: 'Server error',
            message: 'An error occurred while communicating with the server',
          );
          _logger.severe('Stream error', e, s);
          unloadServer();
        },
      );

      _keepAliveTimer = Timer.periodic(
        const Duration(seconds: 10),
        (_) {
          if (isClosed || !identical(_channel, channel)) return;
          try {
            channel.sink.add('');
          } on Object catch (error) {
            _logger.warning('Server event channel closed', error);
            unloadServer();
          }
        },
      );

      await Future<void>.delayed(const Duration(seconds: 3));
    } on WebSocketException catch (e, s) {
      if (isClosed || generation != _loadGeneration) return;
      var error = 'Failed to connect to websocket';
      switch (e.httpStatusCode ?? 0) {
        case 401:
          error = 'Failed to connect to websocket: Unauthorized';
        case 404:
          error = 'The specified server was not found';
      }

      _logger.severe('Failed to connect to websocket', e, s);
      NotificationService.error(message: error);
      unloadServer();
    } on GrpcError catch (e, s) {
      if (isClosed || generation != _loadGeneration) return;
      _logger.severe('Error loading server:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message:
            e.message ??
            'An error occurred while communicating with the server',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    } on SocketException catch (e, s) {
      if (isClosed || generation != _loadGeneration) return;
      _logger.severe('Socket error:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message: 'An error occurred while communicating with the server',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    } catch (e, s) {
      if (isClosed || generation != _loadGeneration) return;
      _logger.severe('Error loading server:', e, s);
      NotificationService.showNotification(
        title: 'Server error',
        message: 'An error occurred while communicating with the server',
        severity: InfoBarSeverity.error,
      );
      unloadServer();
    } finally {
      if (generation == _loadGeneration) _loadingServerId = null;
    }
  }
}

class IngameViewState {
  const IngameViewState({
    this.id,
    this.server,
    this.players = const [],
    this.commands = const [],
  });

  final String? id;
  final Server? server;
  final List<ServerPlayer> players;
  final List<String> commands;

  IngameViewState copyWith({
    String? id,
    Server? server,
    List<ServerPlayer>? players,
    List<String>? commands,
  }) {
    return IngameViewState(
      id: id ?? this.id,
      server: server ?? this.server,
      players: players ?? this.players,
      commands: commands ?? this.commands,
    );
  }
}
