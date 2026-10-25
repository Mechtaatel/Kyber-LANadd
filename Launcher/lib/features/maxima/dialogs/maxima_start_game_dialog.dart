import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/core.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/core/services/module_version_service.dart';
import 'package:kyber_launcher/features/kyber/dialogs/kyber_anti_virus_exclusion.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_expired_session_dialog.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_game_locator_dialog.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_game_not_found_dialog.dart';
import 'package:kyber_launcher/features/maxima/helper/maxima_helper.dart';
import 'package:kyber_launcher/features/mods/helper/preloaded_mods_helper.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/buttons/export_logs_button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:logging/logging.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class MaximaStartGameDialog extends StatefulWidget {
  const MaximaStartGameDialog({
    super.key,
    this.gameDataDir,
    this.initializeRequest,
    this.mods,
  });

  final String? gameDataDir;
  final List<FrostyMod>? mods;
  final InitializeRequest? initializeRequest;

  @override
  State<MaximaStartGameDialog> createState() => _MaximaStartGameDialogState();
}

class _MaximaStartGameDialogState extends State<MaximaStartGameDialog> {
  StreamSubscription<String>? _gameEvents;
  bool _dialogDismissed = false;

  bool get _isActive =>
      mounted && !_dialogDismissed && ModalRoute.of(context)?.isActive == true;

  void _closeDialog() {
    if (!mounted || _dialogDismissed) return;
    _dialogDismissed = true;
    _gameEvents?.cancel();
    dismissKyberDialog(context);
  }

  bool updating = false;
  bool preloadingMods = false;
  String? lastEvent;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _startGame());
  }

  Future<void> _startGame() async {
    if (!_isActive) return;
    try {
      final lanOnly = LanMode.forLaunch(widget.initializeRequest);
      final available =
          !lanOnly &&
          await ModuleVersionService().updateAvailable(
            module: VersionModule.module,
          );
      if (!_isActive) return;
      if (available) {
        setState(() => updating = true);

        await ModuleVersionService().updateVersion(
          module: VersionModule.module,
        );

        if (!_isActive) return;

        setState(() => updating = false);
      }
      final req = widget.initializeRequest ?? .new();
      if (!lanOnly && Preferences.general.enabledPreloadMods) {
        setState(() => preloadingMods = true);
        final preloadedMods = await PreloadedModsHelper.preloadMods();
        if (!_isActive) return;

        req.modData = .new(
          mods: req.modData.mods,
          explodedMods: req.modData.explodedMods,
          basePath: req.modData.basePath,
          modPaths: [...req.modData.modPaths, ...preloadedMods],
        );
        setState(() => preloadingMods = false);
      }

      final instance = await MaximaHelper.startGame(
        gameDataPath: widget.gameDataDir,
        initializeRequest: req,
        mods: widget.mods,
      );
      if (!_isActive) return;
      _gameEvents = instance.eventStream.listen(
        (e) {
          if (!_isActive) return;
          setState(() => lastEvent = e);

          if ([
            'IsProgressiveInstallationAvailable',
            'GetGameInfo',
            'GetInfo',
          ].contains(e)) {
            _closeDialog();
          }
        },
        onDone: _closeDialog,
        cancelOnError: true,
        onError: _handleLaunchError,
      );
    } catch (error, stackTrace) {
      _handleLaunchError(error, stackTrace);
    }
  }

  void _handleLaunchError(Object error, StackTrace stackTrace) {
    final showError = _isActive;
    // Dismiss the launching dialog exactly once, before showing its replacement.
    _closeDialog();
    Logger.root.severe('Failed to start game', error, stackTrace);
    unawaited(Sentry.captureException(error, stackTrace: stackTrace));
    if (!showError) return;
    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null) return;

    final message = switch (error) {
      AnyhowException() => error.message,
      PanicException() => error.message,
      _ => error.toString(),
    };
    final Widget dialog;
    if (error is AnyhowException && message.contains('Game not found')) {
      dialog = const MaximaGameNotFoundDialog();
    } else if (error is AnyhowException &&
        message.contains('Game not installed')) {
      dialog = const MaximaGameLocatorDialog();
    } else if (error is AnyhowException &&
        message.contains('remote io error')) {
      dialog = const KyberAntiVirusExclusion();
    } else if (error is AnyhowException &&
        message.contains('invalid redirect')) {
      dialog = const MaximaExpiredSessionDialog();
    } else {
      dialog = _LaunchErrorDialog(message: message);
    }
    unawaited(showKyberDialog(context: dialogContext, builder: (_) => dialog));
  }

  @override
  void dispose() {
    _gameEvents?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      title: Text('GAME LAUNCHING'.toUpperCase()),
      constraints: const BoxConstraints(maxWidth: 500, maxHeight: 300),
      content: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                height: 15,
                width: 15,
                child: RepaintBoundary(child: ProgressRing()),
              ),
              const SizedBox(width: 15),
              if (updating)
                Text(
                  'Updating Kyber Module...',
                  style: FluentTheme.of(context).typography.bodyLarge,
                ),
              if (!updating)
                Text(
                  preloadingMods ? 'Preparing mods...' : 'Starting Game...',
                  style: FluentTheme.of(context).typography.bodyLarge,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Please wait while the game is starting. This may take a few seconds.',
            style: FluentTheme.of(
              context,
            ).typography.body?.copyWith(color: kWhiteColor),
          ),
          const SizedBox(height: 10),
          Text(lastEvent ?? '', style: FluentTheme.of(context).typography.body),
        ],
      ),
    );
  }
}

class _LaunchErrorDialog extends StatelessWidget {
  const _LaunchErrorDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      title: const Text('GAME COULD NOT START'),
      constraints: const BoxConstraints(maxWidth: 650, maxHeight: 480),
      content: SingleChildScrollView(
        child: SelectableText(
          message,
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      actions: [
        const ExportLogsButton(),
        KyberButton(
          text: 'Close',
          onPressed: () => dismissKyberDialog(context),
        ),
      ],
    );
  }
}
