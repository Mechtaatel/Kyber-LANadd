import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';

class AppShortcuts {
  static Map<ShortcutActivator, VoidCallback> getNavigationShortcuts(
    BuildContext context,
  ) {
    return {
      LogicalKeySet(
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.alt,
      ): toggleDebugLogs,
    };
  }

  static Map<ShortcutActivator, VoidCallback> getDebugShortcuts() {
    return {
      LogicalKeySet(
        LogicalKeyboardKey.control,
        LogicalKeyboardKey.shift,
        LogicalKeyboardKey.alt,
      ): toggleDebugLogs,
    };
  }

  static void toggleDebugLogs() {
    Preferences.debug.frbDebugLogs = !Preferences.debug.frbDebugLogs;
    NotificationService.info(
      message:
          '${Preferences.debug.frbDebugLogs ? 'Enabled' : 'Disabled'} debug logs',
    );
  }
}
