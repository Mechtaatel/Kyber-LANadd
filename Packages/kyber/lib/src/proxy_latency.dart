import 'dart:async';
import 'dart:io';

import 'package:pool/pool.dart';

import '../gen/Proto/kyber_api.pb.dart';

class KyberProxy {
  const KyberProxy({required this.proxy, required this.ping});

  final ProxyInfo proxy;
  final int ping;

  String get _metadataKey => 'proxy_rtt_ms_${proxy.id}';

  int? estimatedRtt(Server server) {
    final hostPing = int.tryParse(server.meta[_metadataKey] ?? '');
    if (hostPing == null || hostPing < 0 || hostPing > 2000) return null;
    return ping + hostPing;
  }

  static String hostMetadata(String existing, Iterable<KyberProxy> proxies) => [
    if (existing.isNotEmpty) existing,
    for (final p in proxies)
      if (p.proxy.id != 'auto' &&
          RegExp(r'^[a-zA-Z0-9._-]{1,128}$').hasMatch(p.proxy.id))
        '${p._metadataKey}=${p.ping}',
  ].join(',');

  /// Input contains reachable proxies ordered by client RTT (and optionally
  /// the launcher's synthetic Auto entry). Only compare complete routes.
  static KyberProxy? forServer(
    Iterable<KyberProxy> proxies,
    Server server,
    String selection,
  ) {
    final pinned = server.meta['pinned_proxy_id'] ?? '';
    KyberProxy? nearest;
    KyberProxy? best;
    int? bestRtt;
    for (final p in proxies) {
      if (p.proxy.id == 'auto') continue;
      if (pinned.isNotEmpty) {
        if (p.proxy.id == pinned) return p;
        continue;
      }
      if (p.proxy.id == selection) return p;
      nearest ??= p;
      final rtt = p.estimatedRtt(server);
      if (rtt != null && (bestRtt == null || rtt < bestRtt)) {
        best = p;
        bestRtt = rtt;
      }
    }
    // Keep the existing route if its host leg is unknown. A partial set of
    // measurements is not evidence that moving to a different proxy helps.
    return nearest?.estimatedRtt(server) == null ? nearest : best;
  }

  static Future<List<KyberProxy>> measure(
    Iterable<ProxyInfo> list, {
    void Function(KyberProxy)? onMeasured,
  }) async {
    final pool = Pool(2);
    try {
      final measured = await Future.wait(
        list.map(
          (proxy) => pool.withResource(() async {
            for (final scheme in ['ws', 'wss']) {
              final ping = await _ping(Uri.parse('$scheme://${proxy.ip}/ping'));
              if (ping != null) {
                final result = KyberProxy(proxy: proxy, ping: ping);
                onMeasured?.call(result);
                return result;
              }
            }
            return null;
          }),
        ),
      );
      return measured.nonNulls.toList()
        ..sort((a, b) => a.ping.compareTo(b.ping));
    } finally {
      await pool.close();
    }
  }

  static Future<int?> _ping(Uri uri) async {
    const timeout = Duration(seconds: 2);
    final client = HttpClient()..connectionTimeout = timeout;
    WebSocket? socket;
    StreamIterator<dynamic>? replies;
    try {
      socket = await WebSocket.connect(
        uri.toString(),
        customClient: client,
      ).timeout(timeout);
      replies = StreamIterator<dynamic>(socket);
      final samples = <int>[];
      for (var i = 0; i < 4; i++) {
        final clock = Stopwatch()..start();
        socket.add('PING');
        if (!await replies.moveNext().timeout(timeout)) return null;
        if (i > 0) samples.add(clock.elapsedMilliseconds);
      }
      samples.sort();
      return samples[1];
    } on Exception {
      return null;
    } finally {
      client.close(force: true);
      if (socket != null) unawaited(socket.close().catchError((Object _) {}));
      await replies?.cancel();
    }
  }
}
