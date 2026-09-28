import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../gen/Proto/kyber_api.pb.dart';

/// Explicit offline session; EA/Maxima still handles ownership and game startup.
class LanMode {
  static bool enabled = fromEnvironment(Platform.environment);

  static bool fromEnvironment(Map<String, String> environment) =>
      environment['KYBER_LAN_ONLY'] == '1' ||
      const {'1', 'true', 'yes', 'on'}.contains(
        environment['KYBER_LAN']?.toLowerCase(),
      );
}

extension LanServer on Server {
  bool get isLan => region == 'LAN';
  bool get isLanOnly => isLan && meta['lan_only'] == '1';

  int browserPriority({required bool friend}) => official
      ? 0
      : isLan
          ? 1
          : friend
              ? 2
              : 3;
}

/// Retain public listings briefly across API failures, never cached LAN routes.
class PublicServerCache {
  List<Server> _servers = [];
  DateTime? _updated;

  List<Server> resolve(List<Server>? response, {required DateTime now}) {
    if (response != null) {
      _servers =
          response.map((s) => Server.fromBuffer(s.writeToBuffer())).toList();
      _updated = now;
    }
    if (_updated == null ||
        now.difference(_updated!) > const Duration(minutes: 2)) {
      return [];
    }
    return _servers.map((s) => Server.fromBuffer(s.writeToBuffer())).toList();
  }
}

/// IPv4 discovery on the local network. Never trusts an advertised IP address.
class LanDiscovery {
  const LanDiscovery({this.discoveryPort = port});

  static const port = 25202;
  static const magic = 'KYBER-LAN-1:';
  final int discoveryPort;

  static bool isLocalAddress(InternetAddress address) {
    final b = address.rawAddress;
    return b.length == 4 &&
        (b[0] == 10 ||
            b[0] == 127 ||
            b[0] == 172 && b[1] >= 16 && b[1] <= 31 ||
            b[0] == 192 && b[1] == 168 ||
            b[0] == 169 && b[1] == 254);
  }

  // Radmin uses 26/8, which is NOT an RFC1918 private range. Only accept
  // responses from it when this machine has an address on that overlay.
  static bool isDiscoveryPeer(
    InternetAddress address,
    Iterable<InternetAddress> interfaces,
  ) =>
      isLocalAddress(address) ||
      address.type == InternetAddressType.IPv4 &&
          address.rawAddress[0] == 26 &&
          interfaces.any((a) =>
              a.type == InternetAddressType.IPv4 && a.rawAddress[0] == 26);

  static List<InternetAddress> probeTargets(InternetAddress address) =>
      address.isLoopback
          ? [InternetAddress.loopbackIPv4]
          : [
              InternetAddress('255.255.255.255'),
              if (address.rawAddress[0] == 26)
                InternetAddress('26.255.255.255'),
            ];

  /// Preserve authenticated public metadata, but prefer a fresh direct route.
  static Server preferLan(Server online, Server local) {
    if (online.id != local.id || !local.isLan || local.isLanOnly) return online;
    final merged = Server.fromBuffer(online.writeToBuffer())
      ..ip = local.ip
      ..port = local.port
      ..region = 'LAN'
      ..requiresProxy = false;
    merged.meta.remove('persisted_id');
    merged.meta['lan_only'] = '0';
    return merged;
  }

  Future<List<Server>> discover({
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final servers = <String, Server>{};
    final sockets = <RawDatagramSocket>[];
    final random = Random.secure();
    final query = [
      ...ascii.encode(magic),
      ...List.generate(16, (_) => random.nextInt(256)),
    ];
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final interfaceAddresses = interfaces.expand((i) => i.addresses).toList();
      final addresses = <InternetAddress>[
        InternetAddress.loopbackIPv4,
        ...interfaceAddresses
            .where((a) => isDiscoveryPeer(a, interfaceAddresses)),
      ];
      for (final address in addresses) {
        try {
          final socket = await RawDatagramSocket.bind(address, 0);
          sockets.add(socket);
          socket.broadcastEnabled = true;
          socket.listen((event) {
            if (event != RawSocketEvent.read) return;
            Datagram? packet;
            while ((packet = socket.receive()) != null) {
              final p = packet!;
              if (p.port != discoveryPort ||
                  !isDiscoveryPeer(p.address, addresses) ||
                  p.data.length <= query.length ||
                  p.data.length > 60000 ||
                  !Iterable<int>.generate(query.length)
                      .every((i) => p.data[i] == query[i])) continue;
              try {
                final server = Server.fromBuffer(p.data.sublist(query.length));
                if (server.name.isEmpty ||
                    server.id.isEmpty ||
                    server.port < 1 ||
                    server.port > 65535 ||
                    server.maxPlayerCount == 0 ||
                    servers.length >= 256) continue;
                final offline = server.meta['lan_only'] == '1';
                if (offline && server.requiresPassword) continue;
                server
                  ..ip = addresses.any((a) => a.address == p.address.address)
                      ? '127.0.0.1'
                      : p.address.address
                  ..region = 'LAN'
                  ..official = false
                  ..requiresProxy = false;
                server.meta.clear();
                server.meta['lan_only'] = offline ? '1' : '0';
                final key = offline ? '${server.ip}:${server.port}' : server.id;
                if (offline) server.id = 'lan:$key';
                servers[key] = server;
              } catch (_) {
                // Ignore malformed/unknown packets from other LAN applications.
              }
            }
          }, onError: (Object _) {});
        } on SocketException {
          // One unavailable adapter must not hide servers on the other adapters.
        }
      }
      void probe() {
        for (final socket in sockets) {
          for (final target in probeTargets(socket.address)) {
            try {
              socket.send(query, target, discoveryPort);
            } on SocketException {
              /* Adapter disappeared during scan. */
            }
          }
        }
      }

      probe();
      await Future<void>.delayed(timeout ~/ 2);
      probe();
      await Future<void>.delayed(timeout ~/ 2);
      return servers.values.toList();
    } on SocketException {
      return servers.values.toList();
    } finally {
      for (final socket in sockets) {
        socket.close();
      }
    }
  }
}
