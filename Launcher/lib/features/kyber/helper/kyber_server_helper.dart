import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart' hide ServerMod;
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_api_status_cubit.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_proxy_cubit.dart';
import 'package:kyber_launcher/features/kyber/helper/server_mod_order.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_start_game_dialog.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/features/mod_collections/extensions/mod_collection_extension.dart';
import 'package:kyber_launcher/features/mods/extensions/frosty_collection_extension.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/features/session/providers/session_cubit.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:logging/logging.dart';

class KyberServerHelper {
  static final _logger = Logger('kyber_server_helper');

  static Future<void> joinServer(
    Server server, {
    ModCollectionMetaData? selectedCollection,
    bool? spectator,
    String? password,
    bool queueIfFull = false,
    bool resolveLanRoute = true,
  }) async {
    // Selections/invite links may predate the last scan. Resolve LAN again
    // immediately before joining, including when an online row was selected.
    if (resolveLanRoute && !server.isLan) {
      final local =
          (await LanDiscovery().discover(
            hostPort: Preferences.hostServer.port,
          )).firstWhereOrNull(
            (s) => s.id == server.id && !s.isLanOnly,
          );
      if (local != null) server = LanDiscovery.preferLan(server, local);
    }
    final runningGame = sl.isRegistered<MaximaGameInstance>()
        ? sl.get<MaximaGameInstance>()
        : null;
    if (runningGame != null && runningGame.lanOnly != server.isLanOnly) {
      NotificationService.error(
        message: 'Restart the game to switch between LAN-only and online play.',
      );
      return;
    }
    final modService = sl.get<ModService>();
    final localMods = [...modService.mods, ...modService.hiddenMods];
    final mods = server.mods.map((e) {
      final matches = localMods
          .where(
            (element) => element.toKyberString() == '${e.name} (${e.version})',
          )
          .toList();

      if (matches.isEmpty) {
        throw StateError(
          'Required mod ${e.name} (${e.version}) is not installed.',
        );
      }

      return matches.firstWhereOrNull(
            (m) => !m.isCollection || !m.isCorrupted(),
          ) ??
          matches.first;
    });
    final collectionMods = <CollectionMod>[];
    for (final mod in mods) {
      if (mod.isCollection) {
        final cMods = mod.getMods()!.map(
          (e) => localMods
              .firstWhereOrNull((x) => x.filename == e)
              ?.toCollectionMod(),
        );
        if (cMods.contains(null)) {
          throw Exception(
            '"${mod.details.name}" is corrupted. Please reinstall it',
          );
        }

        collectionMods.addAll(cMods.whereType<CollectionMod>());
      } else {
        collectionMods.add(mod.toCollectionMod());
      }
    }

    // Keep the host's required mod order even when the chosen collection
    // already includes gameplay mods. Expand collections before deduplicating
    // so an explicit .fbmod and the same file inside a collection load once.
    final selectedMods = selectedCollection?.getLocalMods(
      expandCollections: true,
    );
    if (selectedMods?.contains(null) ?? false) {
      throw StateError(
        'The selected cosmetic collection contains missing files.',
      );
    }
    final orderedMods = mergeServerModOrder(
      collectionMods,
      selectedMods
              ?.whereType<FrostyMod>()
              .where((mod) => !mod.isCollection)
              .map((mod) => mod.toCollectionMod()) ??
          const [],
    );
    _logger.info(
      'Required server mods in host order: '
      '${server.mods.map((mod) => '${mod.name} (${mod.version})').join(', ')}',
    );
    _logger.fine(
      'Resolved mod load order: '
      '${orderedMods.map((mod) => mod.filename ?? mod.name).join(', ')}',
    );
    final tmpCollection = ModCollectionMetaData(
      title: server.name,
      mods: orderedMods,
      localId: server.id,
    );

    if (sl.isRegistered<MaximaGameInstance>()) {
      final instance = sl.get<MaximaGameInstance>();
      if (instance.loadedMods == null ||
          !hasSameModLoadOrder(instance.loadedMods!, orderedMods)) {
        _logger.warning(
          'Reconnect refused: running game mod snapshot is unknown or differs '
          'from the requested mods, versions or load order.',
        );
        NotificationService.error(
          message: instance.loadedMods == null
              ? "Cannot verify the running game's mods. "
                    'Restart Battlefront II '
                    'once from this launcher before reconnecting.'
              : 'Cannot join: the running game has different mods, versions or '
                    'load order. Use the same cosmetic selection or restart '
                    "Battlefront II with this server's mods.",
        );
        return;
      }
    }

    var serverIp = server.ip;
    if (!server.isLan && !server.requiresProxy) {
      try {
        final currentIp = await KyberNetworkHelper.getCurrentIpAddress()
            .timeout(const Duration(seconds: 3));
        if (serverIp == currentIp) serverIp = '127.0.0.1';
      } on Object catch (error) {
        _logger.warning(
          'Public IP lookup unavailable; using the server address',
          error,
        );
      }
    }

    var proxyIp = '';
    if (server.isLan) {
      _logger.info(
        'Joining server directly over LAN ($serverIp:${server.port})',
      );
    }
    if (server.requiresProxy) {
      final proxyCubit = navigatorKey.currentContext!.read<KyberProxyCubit>();
      if (proxyCubit.isLoading) {
        NotificationService.info(message: 'Waiting for proxies to load...');
      }

      await proxyCubit.ensureReady();
      final proxies = proxyCubit.state.proxies;
      // The game module resolves the host's pinned proxy itself if its ping
      // endpoint did not reply. Preserve that existing join path.
      final selectedProxy =
          KyberProxy.forServer(
            proxies,
            server,
            proxyCubit.state.selectedProxy,
          ) ??
          proxies.firstOrNull;
      if (selectedProxy == null) throw StateError('No proxy available');

      _logger.info(
        'Joining server with proxy ${selectedProxy.proxy.name} (${selectedProxy.proxy.ip})',
      );
      proxyIp = selectedProxy.proxy.ip;
    }

    try {
      JoinTokenResponse? joinToken;
      if (!server.isLanOnly) {
        try {
          joinToken = await sl
              .get<KyberGRPCService>()
              .clientServerClient
              .createJoinToken(
                .new(
                  server: server.id,
                  password: password,
                ),
              );
        } on GrpcError catch (e) {
          if (!server.isLan &&
              queueIfFull &&
              e.code == StatusCode.resourceExhausted &&
              LightswitchCubit.isFeatureEnabled(.queues)) {
            await _joinQueueForServer(
              server,
              selectedCollection: selectedCollection,
              spectator: spectator,
              password: password,
            );
            return;
          }
          rethrow;
        }
      }

      final joinRequest = JoinServerRequest(
        id: server.isLanOnly ? null : server.id,
        ip: server.requiresProxy ? proxyIp : serverIp,
        port: server.requiresProxy ? null : server.port,
        type: server.requiresProxy ? .PROXIED : .DIRECT,
        spectate: spectator ?? false,
        joinToken: joinToken?.token,
      );

      if (!sl.isRegistered<MaximaGameInstance>()) {
        await showKyberDialog(
          context: navigatorKey.currentContext!,
          builder: (_) => MaximaStartGameDialog(
            mods: tmpCollection.getLocalMods().whereType<FrostyMod>().toList(),
            initializeRequest: InitializeRequest(
              joinServer: joinRequest,
              modData: tmpCollection.getInterfaceData(),
            ),
          ),
        );
      } else {
        final instance = sl.get<MaximaGameInstance>();
        await instance.clientService.client.joinServer(joinRequest);
        _logger.info(
          'Join request sent to the running game (PID ${instance.pid}); '
          'mod selection matches.',
        );
      }
    } on GrpcError catch (e) {
      _logger.severe('Failed to join server: ${e.message}', e);
      NotificationService.error(message: 'Failed to join server: ${e.message}');
    } catch (e) {
      _logger.severe('Failed to join server: $e', e);
      NotificationService.error(message: 'Failed to join server: $e');
    }
  }

  static Future<void> _joinQueueForServer(
    Server server, {
    ModCollectionMetaData? selectedCollection,
    bool? spectator,
    String? password,
  }) async {
    final sessionCubit = navigatorKey.currentContext?.read<SessionCubit>();
    if (sessionCubit == null) {
      return;
    }

    try {
      await sessionCubit.joinQueue(
        server,
        password: password ?? '',
        spectator: spectator ?? false,
        selectedCollection: selectedCollection,
      );

      NotificationService.info(
        message: 'Server is full. You joined the queue.',
      );
    } on GrpcError catch (e) {
      if (e.code == StatusCode.failedPrecondition &&
          (e.message?.contains('not full') ?? false)) {
        NotificationService.info(
          message: 'Joining server...',
        );
        await joinServer(
          server,
          resolveLanRoute: false,
          selectedCollection: selectedCollection,
          spectator: spectator,
          password: password,
        );
        return;
      }

      _logger.severe('Failed to join server queue: ${e.message}', e);
      NotificationService.error(
        message: 'Failed to join server queue: ${e.message}',
      );
    }
  }
}
