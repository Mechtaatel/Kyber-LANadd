import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../Packages/kyber/lib/gen/Proto/kyber_api.pb.dart';
import '../../../Packages/kyber/lib/gen/Proto/kyber_interface.pb.dart';
import '../../../Packages/kyber/lib/src/lan_discovery.dart';

void main() {
  test('official, LAN, friend and other priority ordering', () {
    final official = Server(official: true);
    final lan = Server(region: 'LAN');
    final friend = Server();
    final other = Server();
    expect(
      [
        official.browserPriority(friend: false),
        lan.browserPriority(friend: false),
        friend.browserPriority(friend: true),
        other.browserPriority(friend: false),
      ],
      [0, 1, 2, 3],
    );
    official.region = 'LAN';
    expect(official.browserPriority(friend: false), 0);
    expect(lan.browserPriority(friend: true), 1);
  });
  test('accepts LAN/loopback IPv4, rejects internet and IPv6', () {
    for (final ip in [
      '10.1.2.3',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.1.1',
      '127.0.0.1',
      '169.254.1.1',
    ]) {
      expect(
        LanDiscovery.isLocalAddress(InternetAddress(ip)),
        isTrue,
        reason: ip,
      );
    }
    for (final ip in [
      '8.8.8.8',
      '172.15.0.1',
      '172.32.0.1',
      '0.0.0.0',
      '::1',
    ]) {
      expect(
        LanDiscovery.isLocalAddress(InternetAddress(ip)),
        isFalse,
        reason: ip,
      );
    }
  });

  test('LAN host flag survives protobuf transport and defaults to online', () {
    expect(StartServerRequest().lanOnly, isFalse);
    final request = StartServerRequest(name: 'LAN', lanOnly: true);
    expect(
      StartServerRequest.fromBuffer(request.writeToBuffer()).lanOnly,
      isTrue,
    );
  });

  test(
    'discovers, sanitizes and deduplicates a real UDP responder; expires stopped hosts',
    () async {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        LanDiscovery.port,
      );
      final server = Server(
        id: 'lan:123',
        name: 'Test LAN',
        port: 25200,
        maxPlayerCount: 40,
        playerCount: 2,
        official: true,
        requiresProxy: true,
        ip: '8.8.8.8',
        meta: {'lan_only': '1', 'persisted_id': 'spoofed'}.entries,
      );
      socket.listen((event) {
        if (event != RawSocketEvent.read) return;
        final packet = socket.receive();
        if (packet == null) return;
        expect(
          ascii.decode(packet.data.take(LanDiscovery.magic.length).toList()),
          LanDiscovery.magic,
        );
        final wrongNonce = [...packet.data];
        wrongNonce[wrongNonce.length - 1] ^= 1;
        socket.send(
          [...wrongNonce, ...server.writeToBuffer()],
          packet.address,
          packet.port,
        );
        socket.send([...packet.data, 255], packet.address, packet.port);
        socket.send(
          [...packet.data, ...server.writeToBuffer()],
          packet.address,
          packet.port,
        );
      });
      try {
        final found = await LanDiscovery().discover(
          timeout: const Duration(milliseconds: 200),
        );
        expect(found, hasLength(1));
        expect(found.single.ip, '127.0.0.1');
        expect(found.single.isLanOnly, isTrue);
        expect(found.single.region, 'LAN');
        expect(found.single.official, isFalse);
        expect(found.single.requiresProxy, isFalse);
        expect(found.single.meta.containsKey('persisted_id'), isFalse);
        expect(found.single.playerCount, 2);
      } finally {
        socket.close();
      }
      expect(
        await LanDiscovery().discover(
          timeout: const Duration(milliseconds: 100),
        ),
        isEmpty,
      );
    },
  );
}
