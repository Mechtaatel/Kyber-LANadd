import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/server_browser/constants/modes.dart';
import 'package:kyber_launcher/features/server_browser/models/server_filter.dart';
import 'package:kyber_launcher/features/server_browser/models/server_list_state.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_servers_cubit.dart';
import 'package:kyber_launcher/gen/rust/api/maxima.dart';
import 'package:kyber_launcher/injection_container.dart';

List<ServicePlayer> _friends = [];

const _pageLimit = 12;

class ServerListCubit extends Cubit<ServerListState> {
  bool _needsUpdate = false;
  int _page = 1;
  int _loadGeneration = 0;

  ServerListCubit() : super(const ServerListInitial()) {
    filter = ServerFilter();

    (LanMode.enabled ? Future.value(<ServicePlayer>[]) : getFriendList())
        .then((value) {
          _friends = value;
          loadServers();
        })
        .timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            NotificationService.error(message: 'Failed to load friends list');
            _friends = [];
            loadServers();
          },
        )
        .catchError((Object error) {
          _friends = [];
          loadServers();
        });

    emit(const ServerListLoading());

    _updateTimer = Timer.periodic(const Duration(seconds: 40), (timer) {
      final route = router.routeInformationProvider.value.uri.toString();
      if (!route.startsWith('/home')) {
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
    await super.close();
    _updateTimer.cancel();
  }

  void checkUpdate() {
    if (_needsUpdate) {
      loadServers();
      _needsUpdate = false;
    }
  }

  void clearSearch() {
    if (filter.query?.isNotEmpty ?? false) {
      filter = filter.copyWith(query: '');
      _needsUpdate = true;
    }
  }

  void setFilter(ServerFilter filter) {
    if (filter == this.filter) {
      return;
    }

    _page = 1;

    if (state is ServerListLoaded) {
      final x = state as ServerListLoaded;
      emit(
        ServerListLoaded(
          servers: x.servers,
          page: _page,
          pages: x.pages,
          filter: filter,
        ),
      );
    }

    this.filter = filter;

    emit(
      ServerListLoading(page: _page, pages: state.pages, filter: this.filter),
    );
    loadServers();
  }

  void nextPage() {
    if (state is ServerListLoaded) {
      final x = state as ServerListLoaded;
      if (x.page + 1 > x.pages) {
        return;
      }

      _page = x.page + 1;
      emit(ServerListLoading(page: _page, pages: x.pages, filter: filter));
      loadServers();
    }
  }

  void previousPage() {
    if (state is ServerListLoaded) {
      final x = state as ServerListLoaded;
      if (x.page - 1 < 1) {
        return;
      }

      _page = x.page - 1;
      emit(ServerListLoading(page: _page, pages: x.pages, filter: filter));
      loadServers();
    }
  }

  Future<void> loadServers() async {
    if (isClosed) return;
    final generation = ++_loadGeneration;
    emit(ServerListLoading(page: _page, pages: state.pages));

    _needsUpdate = false;

    final lanFuture = LanDiscovery().discover();
    ServerList servers;
    try {
      servers = LanMode.enabled || filter.region == ServerRegion.lan
          ? ServerList()
          : await sl
                .get<KyberGRPCService>()
                .serverBrowserClient
                .getServers(ServerListRequest())
                .timeout(const Duration(seconds: 4));
    } catch (_) {
      servers = ServerList();
    }
    final localServers = await lanFuture;
    if (isClosed || generation != _loadGeneration) return;
    final s = servers.servers.map((e) {
      return Server(
        id: e.id,
        mods: e.mods,
        name: e.name,
        levelSetup: e.levelSetup,
        port: e.port,
        description: e.description,
        creator: e.creator,
        requiresPassword: e.requiresPassword,
        official: e.official,
        ip: e.ip,
        maxPlayerCount: e.maxPlayerCount,
        playerCount: e.playerCount,
        requiresProxy: e.requiresProxy,
        region: e.region,
        mapImageHash: e.mapImageHash,
        meta: e.meta.entries,
      );
    }).toList();

    for (final local in localServers) {
      if (LanMode.enabled && !local.isLanOnly) continue;
      final index = s.indexWhere((server) => server.id == local.id);
      if (index >= 0) {
        // Keep trusted official/friend metadata, prefer the discovered LAN route.
        s[index]
          ..ip = local.ip
          ..port = local.port
          ..region = 'LAN'
          ..requiresProxy = false;
        s[index].meta.remove('persisted_id');
        s[index].meta['lan_only'] = '0';
      } else {
        s.add(local);
      }
    }

    if (Preferences.admin.dummyServer) {
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
        return element.region.toLowerCase() != filter.region.name;
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
    final groupedServers =
        List.of(s)
            .where(
              (e) =>
                  e.meta.containsKey('instance_id') &&
                  e.meta.containsKey('persisted_id'),
            )
            .groupListsBy((element) => element.meta['persisted_id']!)
          ..removeWhere((k, v) => v.length < 2);

    for (final entry in groupedServers.entries) {
      serverGroups[entry.key] = ServerGroup(
        servers: entry.value,
        groupName: entry.value.last.name,
      );
    }

    final newServers =
        <Object>[
          ...serverGroups.values,
          ...s.where(
            (e) => !serverGroups.keys.contains(e.meta['persisted_id'] ?? ''),
          ),
        ]..sort((a, b) {
          final playerCountA = a is ServerGroup
              ? a.totalPlayerCount
              : (a as Server).playerCount;
          final playerCountB = b is ServerGroup
              ? b.totalPlayerCount
              : (b as Server).playerCount;
          a = a is ServerGroup ? a.serverInfo : a as Server;
          b = b is ServerGroup ? b.serverInfo : b as Server;

          final aIsFriend = _friends.any(
            (e) => e.displayName == (a as Server).creator,
          );
          final bIsFriend = _friends.any(
            (e) => e.displayName == (b as Server).creator,
          );

          final priority = a
              .browserPriority(friend: aIsFriend)
              .compareTo(b.browserPriority(friend: bIsFriend));
          if (priority != 0) return priority;

          if (aIsFriend && !bIsFriend) {
            return -1;
          } else if (!aIsFriend && bIsFriend) {
            return 1;
          }

          if (a.requiresPassword && !b.requiresPassword) {
            return 1;
          } else if (!a.requiresPassword && b.requiresPassword) {
            return -1;
          }

          if (playerCountA != playerCountB) {
            return playerCountB.compareTo(playerCountA);
          }

          return 0;
        });

    if (filter.query != null && filter.query!.isNotEmpty) {
      newServers.removeWhere((element) {
        final info = element is ServerGroup
            ? element.serverInfo
            : element as Server;
        return !info.name.toLowerCase().contains(filter.query!.toLowerCase()) &&
            !info.creator.toLowerCase().contains(filter.query!.toLowerCase());
      });
    }

    final pages = (newServers.length / _pageLimit).ceil();
    if (_page > pages && pages > 0) {
      _page = pages;
    }

    final paginatedServers = pages == 0
        ? const <Server>[]
        : newServers.skip((_page - 1) * _pageLimit).take(_pageLimit).toList();

    emit(
      ServerListLoaded(
        servers: paginatedServers,
        page: _page,
        pages: pages,
        filter: filter,
      ),
    );
  }

  /// Checks if a server's creator is in the friends list.
  bool isServerCreatorFriend(Server server) {
    return _friends.any((e) => e.displayName == server.creator);
  }
}
