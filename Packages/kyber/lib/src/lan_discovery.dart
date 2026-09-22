import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../gen/Proto/kyber_api.pb.dart';

/// Explicit offline session; EA/Maxima still handles ownership and game startup.
class LanMode {
  static bool enabled = Platform.environment['KYBER_LAN_ONLY'] == '1';
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

/// IPv4 discovery on the local network. Never trusts an advertised IP address.
class LanDiscovery {
  static const port = 25202;
  static const magic = 'KYBER-LAN-1:';

  static bool isLocalAddress(InternetAddress address) {
    final b = address.rawAddress;
    return b.length == 4 &&
        (b[0] == 10 ||
            b[0] == 127 ||
            b[0] == 172 && b[1] >= 16 && b[1] <= 31 ||
            b[0] == 192 && b[1] == 168 ||
            b[0] == 169 && b[1] == 254);
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
      final addresses = <InternetAddress>[
        InternetAddress.loopbackIPv4,
        ...interfaces.expand((i) => i.addresses).where(isLocalAddress),
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
              if (p.port != port ||
                  !isLocalAddress(p.address) ||
                  p.data.length <= query.length ||
                  p.data.length > 60000 ||
                  !List.generate(
                    query.length,
                    (i) => p.data[i] == query[i],
                  ).every((v) => v))
                continue;
              try {
                final server = Server.fromBuffer(p.data.sublist(query.length));
                if (server.name.isEmpty ||
                    server.id.isEmpty ||
                    server.port < 1 ||
                    server.port > 65535 ||
                    server.maxPlayerCount == 0 ||
                    servers.length >= 256)
                  continue;
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
          try {
            socket.send(
              query,
              socket.address.isLoopback
                  ? InternetAddress.loopbackIPv4
                  : InternetAddress('255.255.255.255'),
              port,
            );
          } on SocketException {
            /* Adapter disappeared during scan. */
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
