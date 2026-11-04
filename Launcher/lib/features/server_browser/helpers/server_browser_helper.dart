import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/mods/helper/mod_helper.dart';
import 'package:kyber_launcher/features/server_browser/models/server_filter.dart';
import 'package:kyber_launcher/features/server_browser/providers/server_browser_cubit.dart';

class ServerBrowserHelper {
  static bool canJoinServer(
    BuildContext context, {
    required Server server,
    bool ignoreInstalled = false,
  }) {
    if (server.isFull(context)) {
      return false;
    }

    final installed = server.mods.every(
      (m) => ModHelper.isInstalled(m.name, m.version, ignoreCorrupted: true),
    );
    // The join handler checks the expanded launch snapshot and explains a
    // mismatch. Comparing collection labels here silently disabled valid joins.
    return installed ||
        ignoreInstalled &&
            context.read<ServerBrowserCubit>().state.joiningServer == null;
  }
}
