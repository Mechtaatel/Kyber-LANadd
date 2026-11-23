import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/server_browser/constants/modes.dart';
import 'package:kyber_launcher/features/server_browser/models/server_entry.dart';
import 'package:kyber_launcher/features/server_browser/models/server_filter.dart';
import 'package:kyber_launcher/features/server_browser/models/server_list_state.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_servers_cubit.dart';
import 'package:kyber_launcher/gen/rust/api/maxima.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/main.dart' show box;

const _pageLimit = 12;

class ServerListCubit extends Cubit<ServerListState> {
  bool _needsUpdate = false;
  int _page = 1;
  int _loadGeneration = 0;
  final _publicCache = PublicServerCache();
  final LanDiscovery _discovery;
  Set<String> _friends = {};
  List<Server>? _servers;
  String? _warning;

  final bool browseLan;
  bool get localOnly => browseLan || LanMode.enabled;

  ServerListCubit({
    this.browseLan = false,
    LanDiscovery discovery = const LanDiscovery(),
  }) : _discovery = discovery,
       super(const ServerListInitial()) {
    filter = ServerFilter();

    unawaited(loadServers());
    if (!localOnly) unawaited(_loadFriends());

    _updateTimer = Timer.periodic(const Duration(seconds: 40), (timer) {
      final route = router.routeInformationProvider.value.uri.toString();
      if (!browseLan && !route.startsWith('/home')) {
        _needsUpdate = true;
        return;
      }

      loadServers();
    });
  }

  late ServerFilter filter;
  late Timer _updateTimer;

  @override
  Future<void> close() async {
    _updateTimer.cancel();
    await super.close();
  }

  Future<void> _loadFriends() async {
    try {
      final friends = await getFriendList().timeout(const Duration(seconds: 5));
      if (isClosed) return;
      _friends = friends.map((friend) => friend.displayName).toSet();
      _publishServers();
    } on Object {
      if (!isClosed) {
        NotificationService.error(message: 'Failed to load friends list');
      }
    }
  }

  void checkUpdate() {
    if (_needsUpdate) {
      loadServers();
      _needsUpdate = false;
    }
  }

  void clearSearch() {
    if (filter.query?.isNotEmpty ?? false) {
      setFilter(filter.copyWith(query: ''));
    }
  }

  void setFilter(ServerFilter filter) {
    if (filter == this.filter) {
      return;
    }

    _page = 1;
    this.filter = filter;
    _publishServers();
  }

  void goToPage(int page) {
    if (state is ServerListLoaded) {
      final x = state as ServerListLoaded;
      if (page < 1 || page > x.pages) {
        return;
      }

      _page = page;
      _publishServers();
    }
  }

  void nextPage() {
    goToPage(_page + 1);
  }

  void previousPage() {
    goToPage(_page - 1);
  }

  Map<String, String> get _savedEndpoints => Map<String, String>.from(
    box.get('directServers', defaultValue: const <String, String>{}) as Map,
  );

  Future<Server?> findEndpoint(ServerEndpoint endpoint) async =>
      (await _discovery.discover(endpoint: endpoint)).firstOrNull;

  Future<void> rememberEndpoint(ServerEndpoint endpoint, Server server) async {
    final address = endpoint.toString();
    await box.put('directServers', _savedEndpoints..[address] = server.name);
    await loadServers(confirmed: {address: server});
  }

  Future<void> forgetEndpoint(String address) async {
    await box.put('directServers', _savedEndpoints..remove(address));
    await loadServers();
  }

  Future<List<Server>> _localServers(Map<String, Server> confirmed) async {
    final discovered = await _discovery.discover(
      hostPort: Preferences.hostServer.port,
    );
    final live = {for (final server in discovered) server.id: server};
    final reachable = discovered.map((s) => '${s.ip}:${s.port}').toSet();
    final pending = _savedEndpoints.entries.where(
      (entry) => !reachable.contains(entry.key),
    );
    final saved = await Future.wait(
      pending.map((entry) async {
        final endpoint = ServerEndpoint.tryParse(entry.key);
        if (endpoint == null) return null;
        return confirmed[entry.key] ??
            await findEndpoint(endpoint) ??
            Server(
              id: 'offline:${entry.key}',
              name: entry.value,
              ip: endpoint.address.address,
              port: endpoint.port,
              region: 'LAN',
            );
      }),
    );
    for (final server in saved.nonNulls) {
      live[server.id] = server;
    }
    return live.values.toList();
  }

  Future<void> loadServers({Map<String, Server> confirmed = const {}}) async {
    if (isClosed) return;
    final generation = ++_loadGeneration;
    // Background refresh must not blank the visible list.
    if (state is! ServerListLoaded) {
      emit(ServerListLoading(page: _page, pages: state.pages, filter: filter));
    }

    _needsUpdate = false;

    final lanFuture = _localServers(confirmed);
    ServerList? servers;
    String? warning;
    try {
      servers = localOnly
          ? ServerList()
          : await sl
                .get<KyberGRPCService>()
                .serverBrowserClient
                .getServers(ServerListRequest())
                .timeout(const Duration(seconds: 4));
    } catch (_) {
      warning =
          'Kyber is unavailable. Public listings may be up to 2 minutes old; LAN discovery is live.';
    }
    final localServers = await lanFuture;
    if (isClosed || generation != _loadGeneration) return;
    final s = _publicCache.resolve(servers?.servers, now: DateTime.now());

    for (final local in localServers) {
      if (localOnly && !local.isLanOnly && !local.isSavedOffline) continue;
      final index = s.indexWhere(
        (server) => !server.isLan && server.id == local.browserServerId,
      );
      if (index >= 0) {
        // Retain both routes. A region selection must use the original online
        // endpoint and authentication, not a LAN record relabeled as EU/NA.
        final route = LanDiscovery.preferLan(s[index], local);
        if (route.isLan) s.add(route);
      } else {
        s.add(local);
      }
    }

    _servers = s;
    _warning = warning;
    _publishServers();
  }

  // UI changes reuse the last scan. Only refresh requests touch the network.
  void _publishServers() {
    if (isClosed || _servers == null) return;
    final s = List<Server>.of(_servers!);
    if (!localOnly && Preferences.admin.dummyServer) {
      s.add(KyberDummyServer(title: 'Dummy Server'));
      s.add(
        KyberDummyServer(
          title: 'Dummy Server AA',
          creator: 'Dangercato',
          requiredPassword: true,
        ),
      );
      s.add(KyberDummyServer(title: 'Dummy Server X', isOfficial: true));
      s.add(
        KyberDummyServer(
          title: 'Dummy Server X',
          isOfficial: false,
          playerCount: 10,
        ),
      );
      s.add(KyberDummyServer(title: 'Dummy Server', requiredPassword: true));
      s.add(KyberDummyServer(title: 'Dummy Server', requiredPassword: true));
      s.add(KyberDummyServer(title: 'Dummy Server', requiredPassword: true));
      s.add(KyberDummyServer(title: 'Dummy Server', requiredPassword: true));
    }

    if (filter.type != .all) {
      s.removeWhere((element) {
        switch (filter.type) {
          case .official:
            return !element.official;
          case .custom:
            return element.official || element.requiresPassword;
          case .private:
            return !element.requiresPassword || element.official;
          case .event:
            return true;
          case .all:
            return false;
        }
      });
    }

    if (filter.modes.isNotEmpty) {
      final mappedModes = filter.modes
          .where((e) => e != 'CO-OP')
          .map((e) => filterModes.firstWhere((e1) => e == e1.$1).$2)
          .toList();
      if (filter.modes.contains('CO-OP')) {
        final coop =
            filterModes.firstWhere((e) => e.$1 == 'CO-OP').$2
                as (String, String);
        mappedModes
          ..add(coop.$1)
          ..add(coop.$2);
      }

      s.removeWhere((element) {
        return !mappedModes.contains(element.levelSetup.mode);
      });
    }

    if (filter.region != .all) {
      s.removeWhere((element) {
        return element.serverRegion != filter.region;
      });
    }

    if (filter.gameType != .all) {
      s.removeWhere((element) {
        if (filter.gameType == .modded) {
          return element.mods.isEmpty;
        } else if (filter.gameType == .vanilla) {
          return element.mods.isNotEmpty;
        }

        return false;
      });
    }

    final serverGroups = <String, ServerGroup>{};
    final routeGroups = s.groupListsBy((server) => server.browserServerId)
      ..removeWhere(
        (_, routes) =>
            !routes.any((server) => server.isLan) ||
            !routes.any((server) => !server.isLan),
      );
    for (final entry in routeGroups.entries) {
      final key = 'routes:${entry.key}';
      serverGroups[key] = ServerGroup(
        servers: entry.value,
        groupName: entry.value.first.name,
        groupType: .connectionRoutes,
        groupKey: key,
      );
    }
    final routeServerIds = routeGroups.values
        .expand((routes) => routes.map((server) => server.id))
        .toSet();
    final groupIdServers = Preferences.general.groupServersByRegion
        ? (List.of(s)
              .where(
                (e) =>
                    !e.isLan &&
                    !routeServerIds.contains(e.id) &&
                    e.meta.containsKey('group_id'),
              )
              .groupListsBy((e) => e.meta['group_id']! + e.creatorId)
            ..removeWhere((k, v) => v.length < 2))
        : <String, List<Server>>{};

    for (final entry in groupIdServers.entries) {
      serverGroups[entry.key] = ServerGroup(
        servers: entry.value,
        groupName: entry.value.first.name,
        groupType: ServerGroupType.crossRegion,
        groupKey: entry.key,
      );
    }

    final alreadyGroupedIds = groupIdServers.values
        .expand((v) => v)
        .map((e) => e.id)
        .toSet();
    final persistedGroups =
        List.of(s)
            .where(
              (e) =>
                  !e.isLan &&
                  !routeServerIds.contains(e.id) &&
                  !alreadyGroupedIds.contains(e.id) &&
                  e.meta.containsKey('instance_id') &&
                  e.meta.containsKey('persisted_id'),
            )
            .groupListsBy((e) => e.meta['persisted_id']! + e.creatorId)
          ..removeWhere((k, v) => v.length < 2);

    for (final entry in persistedGroups.entries) {
      serverGroups[entry.key] = ServerGroup(
        servers: entry.value,
        groupName: entry.value.first.name,
        groupType: ServerGroupType.persisted,
        groupKey: entry.key,
      );
    }

    final groupedServerIds = serverGroups.values
        .expand((g) => g.servers.map((s) => s.id))
        .toSet();

    final newServers =
        <ServerEntry>[
          ...serverGroups.values.map((g) => GroupedServer(group: g)),
          ...s
              .where((e) => !groupedServerIds.contains(e.id))
              .map((e) => SingleServer(server: e)),
        ]..sort((a, b) {
          final playerCountA = a.totalPlayerCount;
          final playerCountB = b.totalPlayerCount;
          final serverA = a.serverInfo;
          final serverB = b.serverInfo;

          final aIsFriend = isServerCreatorFriend(serverA);
          final bIsFriend = isServerCreatorFriend(serverB);

          final priority = serverA
              .browserPriority(friend: aIsFriend)
              .compareTo(serverB.browserPriority(friend: bIsFriend));
          if (priority != 0) return priority;

          if (aIsFriend && !bIsFriend) {
            return -1;
          } else if (!aIsFriend && bIsFriend) {
            return 1;
          }

          if (serverA.requiresPassword && !serverB.requiresPassword) {
            return 1;
          } else if (!serverA.requiresPassword && serverB.requiresPassword) {
            return -1;
          }

          if (playerCountA != playerCountB) {
            return playerCountB.compareTo(playerCountA);
          }

          return 0;
        });

    if (filter.query != null && filter.query!.isNotEmpty) {
      final query = filter.query!.toLowerCase();
      newServers.removeWhere((element) {
        final info = element.serverInfo;
        return !info.name.toLowerCase().contains(query) &&
            !info.creator.toLowerCase().contains(query) &&
            !(info.isLan && '${info.ip}:${info.port}'.contains(query));
      });
    }

    final pages = (newServers.length / _pageLimit).ceil();
    if (pages == 0) {
      _page = 1;
    } else if (_page > pages) {
      _page = pages;
    }

    final paginatedServers = pages == 0
        ? const <ServerEntry>[]
        : newServers.skip((_page - 1) * _pageLimit).take(_pageLimit).toList();

    emit(
      ServerListLoaded(
        servers: paginatedServers,
        page: _page,
        pages: pages,
        filter: filter,
        warning: _warning,
      ),
    );
  }

  /// Checks if a server's creator is in the friends list.
  bool isServerCreatorFriend(Server server) {
    return _friends.contains(server.creator);
  }
}
