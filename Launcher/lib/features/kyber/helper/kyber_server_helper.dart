import 'package:collection/collection.dart';
import 'package:fluent_ui/fluent_ui.dart';
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
  }) async {
    // Selections/invite links may predate the last scan. Resolve LAN again
    // immediately before joining, including when an online row was selected.
    if (!server.isLanOnly) {
      final local = (await LanDiscovery().discover()).firstWhereOrNull(
        (s) => s.id == server.id && !s.isLanOnly,
      );
      if (local != null) server = LanDiscovery.preferLan(server, local);
    }
    if (sl.isRegistered<MaximaGameInstance>() &&
        sl.get<MaximaGameInstance>().lanOnly != server.isLanOnly) {
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
    final orderedMods = mergeServerModOrder(
      collectionMods,
      selectedCollection
              ?.getLocalMods(expandCollections: true)
              .whereType<FrostyMod>()
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

    if (server.isLan && sl.isRegistered<MaximaGameInstance>()) {
      final instance = sl.get<MaximaGameInstance>();
      final requiredPaths = mergeServerModOrder(
        collectionMods,
        const [],
      ).map((mod) => mod.filename).whereType<String>();
      if (!hasRequiredServerModOrder(instance.loadedModPaths, requiredPaths)) {
        _logger.warning(
          'Running game has a different required LAN mod set or load order. '
          'A join request cannot reload mods in an existing game process.',
        );
        NotificationService.error(
          message:
              'Restart Battlefront II to load this LAN server\'s required mods.',
        );
        return;
      }
    }

    var serverIp = server.ip;
    final currentIp = server.isLan
        ? null
        : await KyberNetworkHelper.getCurrentIpAddress();
    if (serverIp == currentIp) {
      serverIp = '127.0.0.1';
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
      var selectedProxy = proxies.firstWhereOrNull(
        (p) => p.proxy.id == Preferences.general.proxy,
      );
      if (selectedProxy == null) {
        selectedProxy = proxies.firstOrNull;
        _logger.warning(
          'No proxy selected, using ${selectedProxy?.proxy.name} instead',
        );
        if (selectedProxy == null) {
          _logger.severe('No proxy available');
          throw Exception('No proxy available');
        }

        NotificationService.showNotification(
          message:
              'Selected Proxy not available, using ${selectedProxy.proxy.name} instead',
          severity: InfoBarSeverity.warning,
        );
      }

      _logger.info(
        'Joining server with proxy ${selectedProxy.proxy.name} (${selectedProxy.proxy.ip})',
      );
      proxyIp = selectedProxy.proxy.ip;
    }

    try {
      final service = sl.get<KyberGRPCService>();
      JoinTokenResponse? joinToken;
      if (!server.isLanOnly)
        try {
          joinToken = await service.clientServerClient.createJoinToken(
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
