import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:logging/logging.dart';

class KyberProxyCubit extends Cubit<KyberProxyState> {
  KyberProxyCubit() : super(KyberProxyState(loading: true)) {
    loadProxies();
  }

  final _logger = Logger('proxy_cubit');

  Future<void>? _ready;
  bool _loading = true;

  bool get isLoading => _loading;

  Future<void> ensureReady() => _ready ?? Future<void>.value();

  void selectProxy(String proxyId) {
    Preferences.general.proxy = proxyId;
    emit(state.copyWith(selectedProxy: proxyId));
  }

  Future<void> loadProxies({List<ProxyInfo>? initialProxies}) {
    return _ready = _loadProxies(
      initialProxies: initialProxies,
    ).whenComplete(() => _loading = false);
  }

  Future<void> _loadProxies({List<ProxyInfo>? initialProxies}) async {
    if (LanMode.enabled) {
      emit(state.copyWith(proxies: [], selectedProxy: '', loading: false));
      return;
    }
    emit(state.copyWith(loading: true));
    try {
      var proxyList = initialProxies;
      if (proxyList == null) {
        final resp = await sl.get<KyberGRPCService>().proxyClient.getList(
          Empty(),
        );

        proxyList = List<ProxyInfo>.from(resp.proxies);
      }

      if (proxyList.isEmpty) {
        _logger.warning('No proxies returned');
        emit(state.copyWith(proxies: [], selectedProxy: ''));
        return;
      }

      final proxies = await KyberProxy.measure(proxyList);
      if (proxies.isEmpty) {
        _logger.warning('No proxy responded to the latency check');
        emit(state.copyWith(proxies: [], selectedProxy: ''));
        return;
      }

      final best = proxies.first;
      final autoInfo = ProxyInfo(
        name: 'Auto',
        ip: best.proxy.ip,
        flag: '',
        id: 'auto',
      );

      final entries = [
        KyberProxy(ping: best.ping, proxy: autoInfo),
        ...proxies,
      ];
      final validIds = {...proxyList.map((e) => e.id), 'auto'};

      final selected = _validatedSelection(validIds, Preferences.general.proxy);
      emit(state.copyWith(proxies: entries, selectedProxy: selected));

      if (Preferences.general.proxy.isEmpty) {
        Preferences.general.proxy = 'auto';
        emit(state.copyWith(selectedProxy: 'auto'));
      }
    } catch (e, s) {
      _logger.severe('Failed to load proxies', e, s);
      emit(state.copyWith(proxies: [], selectedProxy: '', loading: false));
    } finally {
      if (!isClosed) {
        emit(state.copyWith(loading: false));
      }
    }
  }

  String _validatedSelection(Iterable<String> validIds, String current) {
    if (current.isEmpty) return '';

    final ok = validIds.any((id) => id == current);
    if (!ok) {
      _logger.warning(
        'Selected proxy "$current" not available. Clearing selection.',
      );
      Preferences.general.proxy = '';
      return '';
    }

    return current;
  }
}

class KyberProxyState {
  KyberProxyState({
    this.proxies = const [],
    this.selectedProxy = '',
    this.loading = false,
  });

  List<KyberProxy> proxies;
  String selectedProxy;

  bool loading;

  KyberProxyState copyWith({
    List<KyberProxy>? proxies,
    String? selectedProxy,
    bool? loading,
  }) {
    return KyberProxyState(
      proxies: proxies ?? this.proxies,
      selectedProxy: selectedProxy ?? this.selectedProxy,
      loading: loading ?? this.loading,
    );
  }
}
