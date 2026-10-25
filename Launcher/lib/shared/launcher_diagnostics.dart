import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:kyber_launcher/core/utils/custom_logger.dart';
import 'package:kyber_launcher/shared/ui/buttons/export_logs_button.dart';

// Keep diagnostics above the navigator, including login, modal and empty routes.
class LauncherDiagnostics extends StatelessWidget {
  const LauncherDiagnostics({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.space,
          control: true,
          alt: true,
        ): CustomLogger.requestLogExport,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          fit: StackFit.expand,
          children: [
            child,
            const Positioned(
              right: 12,
              bottom: 8,
              child: ExportLogsButton(),
            ),
          ],
        ),
      ),
    );
  }
}
