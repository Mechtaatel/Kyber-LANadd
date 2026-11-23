import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../gen/Proto/kyber_api.pb.dart';
import '../gen/Proto/kyber_interface.pb.dart' show InitializeRequest;

/// Explicit offline session; EA/Maxima still handles ownership and game startup.
class LanMode {
  static bool enabled = fromEnvironment(Platform.environment);

  static bool fromEnvironment(Map<String, String> environment) =>
      environment['KYBER_LAN_ONLY'] == '1' ||
      const {
        '1',
        'true',
        'yes',
        'on',
      }.contains(environment['KYBER_LAN']?.toLowerCase());

  /// A direct route to an online server still needs Kyber authentication.
  static bool forLaunch(InitializeRequest? request) =>
      enabled ||
      (request?.startServer.lanOnly ?? false) ||
      request != null &&
          request.hasJoinServer() &&
          request.joinServer.id.isEmpty;
}

extension LanServer on Server {
  bool get isLan => region == 'LAN';
  bool get isSavedOffline => isLan && id.startsWith('offline:');
  int? get discoveryPing => int.tryParse(meta['discovery_ping_ms'] ?? '');
  bool get isLanOnly => isLan && meta['lan_only'] == '1';

  /// Public identity retained separately from an address-based offline join ID.
  String get browserServerId => isLan ? meta['lan_server_id'] ?? id : id;

  int browserPriority({required bool friend}) => isSavedOffline
      ? 4
      : official
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
      _servers = response
          .map((s) => Server.fromBuffer(s.writeToBuffer()))
          .toList();
      _updated = now;
    }
    if (_updated == null ||
        now.difference(_updated!) > const Duration(minutes: 2)) {
      return [];
    }
    return _servers.map((s) => Server.fromBuffer(s.writeToBuffer())).toList();
  }
}

/// A single user-entered unicast IPv4 endpoint. Never resolve a hostname or
/// expand an address into a subnet when the user requests one server.
class ServerEndpoint {
  const ServerEndpoint._(this.address, this.port);
  final InternetAddress address;
  final int port;

  static ServerEndpoint? tryParse(String input) {
    final parts = input.trim().split(':');
    if (parts.length != 2 ||
        !RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(parts[0]) ||
        !RegExp(r'^\d{1,5}$').hasMatch(parts[1]))
      return null;
    final octets = parts[0].split('.').map(int.parse).toList();
    final port = int.parse(parts[1]);
    if (octets.any((n) => n > 255) ||
        octets.first == 0 ||
        octets.first >= 224 ||
        port < 1 ||
        port > 65535)
      return null;
    return ServerEndpoint._(InternetAddress(octets.join('.')), port);
  }

  @override
  String toString() => '${address.address}:$port';
}

/// IPv4 discovery on the local network. Never trusts an advertised IP address.
class LanDiscovery {
  const LanDiscovery({this.discoveryPort = port});

  static const port = 25200;
  static const legacyPort = 25202;
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
          interfaces.any(
            (a) => a.type == InternetAddressType.IPv4 && a.rawAddress[0] == 26,
          );

  static List<InternetAddress> probeTargets(InternetAddress address) =>
      address.isLoopback
      ? [InternetAddress.loopbackIPv4]
      : [
          InternetAddress('255.255.255.255'),
          if (address.rawAddress[0] == 26) InternetAddress('26.255.255.255'),
        ];

  /// Preserve authenticated public metadata, but prefer a fresh direct route.
  static Server preferLan(Server online, Server local) {
    if (online.id != local.browserServerId || !local.isLan) return online;
    // A password-protected public listing cannot acquire an unauthenticated
    // route from a discovery reply.
    if (local.isLanOnly && online.requiresPassword) return online;
    final merged = Server.fromBuffer(online.writeToBuffer())
      ..id = local.id
      ..ip = local.ip
      ..port = local.port
      ..region = 'LAN'
      ..requiresProxy = false;
    merged.meta.remove('persisted_id');
    merged.meta['lan_only'] = local.isLanOnly ? '1' : '0';
    merged.meta['lan_server_id'] = online.id;
    if (local.discoveryPing != null) {
      merged.meta['discovery_ping_ms'] = local.discoveryPing.toString();
    }
    return merged;
  }

  static Server? _readReply(
    Datagram packet,
    int offset,
    ServerEndpoint? endpoint,
    List<InternetAddress> interfaces,
    int ping,
  ) {
    final server = Server.fromBuffer(packet.data.sublist(offset));
    if (server.name.isEmpty ||
        server.id.isEmpty ||
        server.port < 1 ||
        server.port > 65535 ||
        server.maxPlayerCount == 0)
      return null;
    final lanOnly = server.meta['lan_only'] == '1';
    if (lanOnly && server.requiresPassword) return null;
    if (endpoint != null) {
      // A legacy discovery socket may report a different game port. When
      // probing it as a fallback, match the user's requested game instance.
      final sharedPort = server.meta['lan_shared_port'] == '1';
      if (packet.port != endpoint.port &&
          (sharedPort || server.port != endpoint.port)) {
        return null;
      }
      if (sharedPort) server.port = packet.port;
    }
    server
      ..ip = endpoint == null && interfaces.contains(packet.address)
          ? '127.0.0.1'
          : packet.address.address
      ..region = 'LAN'
      ..official = false
      ..requiresProxy = false;
    server.meta.clear();
    server.meta['lan_only'] = lanOnly ? '1' : '0';
    server.meta['lan_server_id'] = server.id;
    server.meta['discovery_ping_ms'] = ping.toString();
    if (lanOnly) server.id = 'lan:${server.ip}:${server.port}';
    return server;
  }

  Future<List<Server>> discover({
    ServerEndpoint? endpoint,
    int? hostPort,
    Duration timeout = const Duration(milliseconds: 1200),
  }) async {
    final servers = <String, Server>{};
    final sockets = <RawDatagramSocket>[];
    final random = Random.secure();
    final clock = Stopwatch()..start();
    final probes = <(List<int>, int)>[];
    final found = Completer<void>();
    final targetPort = endpoint?.port ?? discoveryPort;
    final ports = {
      targetPort,
      if (targetPort == port) legacyPort,
      if (endpoint == null && hostPort != null) hostPort,
    };
    try {
      final addresses = <InternetAddress>[InternetAddress.loopbackIPv4];
      if (endpoint == null) {
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        final adapters = interfaces.expand((i) => i.addresses).toList();
        addresses.addAll(adapters.where((a) => isDiscoveryPeer(a, adapters)));
      }
      for (final address
          in endpoint == null ? addresses : [InternetAddress.anyIPv4]) {
        try {
          final socket = await RawDatagramSocket.bind(address, 0);
          sockets.add(socket);
          socket.broadcastEnabled = endpoint == null;
          final challengeSentAt = <int, int>{};
          socket.listen((event) {
            if (event != RawSocketEvent.read) return;
            Datagram? packet;
            while ((packet = socket.receive()) != null) {
              final p = packet!;
              if (!ports.contains(p.port) ||
                  p.data.length > 60000 ||
                  (endpoint != null
                      ? p.address != endpoint.address
                      : !isDiscoveryPeer(p.address, addresses)))
                continue;
              for (final (query, sentAt) in probes) {
                if (p.data.length <= query.length ||
                    !Iterable<int>.generate(
                      query.length,
                    ).every((i) => p.data[i] == query[i]))
                  continue;
                try {
                  if (endpoint != null &&
                      p.port == targetPort &&
                      p.data.length == query.length + 8) {
                    if (!challengeSentAt.containsKey(sentAt)) {
                      challengeSentAt[sentAt] = clock.elapsedMilliseconds;
                      socket.send(p.data, p.address, p.port);
                    }
                    break;
                  }
                  if (servers.length >= 256) break;
                  final server = _readReply(
                    p,
                    query.length,
                    endpoint,
                    addresses,
                    clock.elapsedMilliseconds -
                        (p.port == targetPort
                            ? challengeSentAt[sentAt] ?? sentAt
                            : sentAt),
                  );
                  if (server == null) break;
                  servers[server.id] = server;
                  if (endpoint != null && !found.isCompleted) found.complete();
                } on Object {
                  // Ignore malformed datagrams and adapters disappearing mid-query.
                }
                break;
              }
            }
          }, onError: (Object _) {});
        } on SocketException {
          // Other adapters may still reach the server.
        }
      }

      for (var attempt = 0; attempt < 2 && !found.isCompleted; attempt++) {
        final nonce = [
          ...ascii.encode(magic),
          ...List.generate(16, (_) => random.nextInt(256)),
        ];
        probes.add((nonce, clock.elapsedMilliseconds));
        for (final socket in sockets) {
          for (final target
              in endpoint == null
                  ? probeTargets(socket.address)
                  : [endpoint.address]) {
            for (final port in ports) {
              if (endpoint != null && attempt == 0 && port != targetPort)
                continue;
              try {
                socket.send(nonce, target, port);
              } on SocketException {
                // Adapter disappeared during scan.
              }
            }
          }
        }
        await found.future.timeout(timeout ~/ 2, onTimeout: () {});
      }
    } on SocketException {
      // Return any servers already received.
    } finally {
      for (final socket in sockets) {
        socket.close();
      }
    }
    return servers.values.toList();
  }
}
