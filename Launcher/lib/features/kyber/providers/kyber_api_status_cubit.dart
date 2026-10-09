import 'dart:async';
import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/features/kyber/helper/kyber_status_helper.dart';
import 'package:kyber_launcher/features/lightswitch/models/status.dart';
import 'package:logging/logging.dart';
import 'package:path/path.dart';
import 'package:rhttp/rhttp.dart';

class LightswitchCubit extends Cubit<LightswitchStatus> {
  final _logger = Logger('api_status');
  Timer? _refreshTimer;
  DateTime? _nextRefresh;
  final _firstRequestCompleter = Completer<LightswitchStatus>();

  Completer<LightswitchStatus> get firstRequestCompleter =>
      _firstRequestCompleter;

  DateTime? get nextRefresh => _nextRefresh;

  LightswitchCubit() : super(LightswitchStatus.defaultStatus()) {
    _refresh();
    _refreshTimer = .periodic(const .new(minutes: 1), (_) async => _refresh());
  }

  Future<void> _refresh() async {
    if (LanMode.enabled) {
      enableLanMode();
      return;
    }
    _nextRefresh = DateTime.now().add(const .new(minutes: 1));
    late LightswitchStatus status;

    final canSkip = File(
      join(FileHelper.getLauncherDirectory().path, 'SKIP_LIGHTSWITCH'),
    ).existsSync();

    try {
      if (canSkip || Platform.isMacOS) {
        status = LightswitchStatus(
          defaultEnvironment: 'prod',
          environments: [],
          status: KyberStatusEnum.up,
          message: 'Connection Error. Please check your internet connection.',
        );

        if (!_firstRequestCompleter.isCompleted) {
          _firstRequestCompleter.complete(status);
        }
        emit(status);
        return;
      }

      status = await KyberStatusHelper.checkKyberStatus();

      _logger.fine('Kyber API status: ${status.status} - ${status.message}');
    } on RhttpException catch (e, s) {
      Logger.root.severe('Failed to fetch Lightswitch status', e, s);

      if (e is RhttpConnectionException) {
        Logger.root.severe(
          'Connection error while fetching Lightswitch status (${e.message})',
          e,
          s,
        );
        status = LightswitchStatus(
          defaultEnvironment: 'prod',
          environments: [],
          status: KyberStatusEnum.down,
          message: 'Connection Error. Please check your internet connection.',
        );
      } else if (e is RhttpStatusCodeException) {
        status = LightswitchStatus(
          defaultEnvironment: 'prod',
          environments: [],
          status: KyberStatusEnum.down,
          message:
              'Server responded with status code ${e.statusCode}. Please try again later.',
        );
      } else if (e is RhttpTimeoutException) {
        status = LightswitchStatus(
          defaultEnvironment: 'prod',
          environments: [],
          status: KyberStatusEnum.down,
          message: 'Request timed out. Please try again later.',
        );
      } else {
        status = LightswitchStatus(
          defaultEnvironment: 'prod',
          environments: [],
          status: KyberStatusEnum.down,
          message: 'Unknown Request Error',
        );
        Logger.root.severe('Failed to request Lightswitch status', e, s);
      }
    }

    if (canSkip && status.status == .down) {
      status.status = .up;
    }

    if (LanMode.enabled) {
      enableLanMode();
      return;
    }
    emit(status);

    if (!_firstRequestCompleter.isCompleted) {
      _firstRequestCompleter.complete(status);
    }
  }

  @override
  Future<void> close() async {
    _refreshTimer?.cancel();
    await super.close();
  }

  void enableLanMode() {
    LanMode.enabled = true;
    final status = LightswitchStatus(
      defaultEnvironment: 'prod',
      environments: [],
      status: KyberStatusEnum.up,
      message: 'LAN mode',
    );
    if (!_firstRequestCompleter.isCompleted)
      _firstRequestCompleter.complete(status);
    emit(status);
  }
}
