import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/services/lan_add_update_service.dart';
import 'package:kyber_launcher/core/services/module_version_service.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/core/services/windows_utils.dart';
import 'package:kyber_launcher/features/settings/dialogs/chromium_download_dialog.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:url_launcher/url_launcher_string.dart';

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    this.forceInstall = false,
    this.module = VersionModule.installer,
    super.key,
  });

  final VersionModule module;
  final bool forceInstall;

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  bool installing = false;
  bool isCompMode = false;
  int total = 0;
  int current = 0;
  bool checking = false;
  String? installedVersion;
  LanAddRelease? release;
  String? checkError;

  @override
  void initState() {
    super.initState();
    if (WindowsUtils.isWindowsCompMode()) {
      isCompMode = true;
    }
    if (widget.module == VersionModule.installer) {
      unawaited(loadLauncherUpdate());
    } else if (widget.forceInstall && !isCompMode) {
      unawaited(startDownload());
    }
  }

  Future<void> loadLauncherUpdate() async {
    setState(() {
      checking = true;
      checkError = null;
      release = null;
    });
    try {
      final installed = await VersionModule.installer.getCurrentVersion();
      final latest = await LanAddUpdateService().latest(
        channel: VersionModule.installer.releaseChannel,
        refresh: true,
      );
      if (!mounted) return;
      setState(() {
        installedVersion = installed;
        release = latest;
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(
        () => checkError = 'Could not check GitHub for updates. Try again.',
      );
    } finally {
      if (mounted) setState(() => checking = false);
    }
    if (mounted &&
        widget.forceInstall &&
        launcherUpdateAvailable &&
        !isCompMode) {
      await startDownload();
    }
  }

  bool get launcherUpdateAvailable =>
      installedVersion != null &&
      release != null &&
      release!.isNewerThan(installedVersion!);

  Future<void> startDownload() async {
    setState(() => installing = true);
    try {
      await ModuleVersionService().updateVersion(
        module: widget.module,
        onProgress: (current, total) {
          if (!mounted) return;
          setState(() {
            this.current = current;
            this.total = total;
          });
        },
      );
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() => installing = false);
      NotificationService.error(message: 'Update failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      title: Text(
        '${widget.module == VersionModule.module ? 'Module' : 'LAN ADD'} Update'
            .toUpperCase(),
      ),
      constraints: const BoxConstraints(
        maxWidth: 600,
        maxHeight: 400,
      ),
      actions: [
        KyberButton(
          onPressed: installing ? null : () => Navigator.pop(context),
          text: 'Ignore',
        ),
        KyberButton(
          onPressed: installing || checking
              ? null
              : widget.module == VersionModule.installer &&
                    !launcherUpdateAvailable
              ? loadLauncherUpdate
              : startDownload,
          text: widget.module == VersionModule.installer
              ? launcherUpdateAvailable
                    ? 'INSTALL'
                    : 'CHECK AGAIN'
              : 'Install',
        ),
        if (widget.module == VersionModule.installer)
          KyberButton(
            onPressed: installing
                ? null
                : () => launchUrlString(lanAddReleasesUrl),
            text: 'VIEW RELEASES',
          ),
      ],
      content: SizedBox(
        height: 400,
        width: 700,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: installing
                ? CrossAxisAlignment.stretch
                : CrossAxisAlignment.center,
            children: [
              if (installing) ...[
                const SizedBox(
                  height: 20,
                ),
                Text(
                  'Downloading update... (${total != 0 ? (current / total * 100).toStringAsFixed(0) : 0}%)',
                  style: const TextStyle(
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 300,
                  child: ProgressBar(
                    value: total == 0 ? 0 : (current / total) * 100,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${formatBytes(current, 1)}/${formatBytes(total, 1)}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    color: kWhiteColor,
                  ),
                ),
              ],
              if (!installing) ...[
                if (widget.module == VersionModule.installer) ...[
                  if (checking)
                    const ProgressRing()
                  else
                    Text(
                      checkError ??
                          (launcherUpdateAvailable
                              ? 'LAN ADD ${release!.version} is available.'
                              : release == null
                              ? 'No Windows release is published on this channel.'
                              : 'LAN ADD is up to date on this release channel.'),
                    ),
                  if (installedVersion != null) ...[
                    const SizedBox(height: 12),
                    Text('Installed: LAN ADD $installedVersion'),
                  ],
                  const SizedBox(height: 12),
                ],
                if (isCompMode) ...[
                  const Text(
                    'You are running the launcher in compatibility mode. This may cause issues with the update process.',
                  ),
                  const Text(
                    'We recommend to disable compatibility for updates.',
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  widget.module == VersionModule.installer
                      ? 'Updates come from Mechtaatel/Kyber-LANadd on GitHub. Install updates the launcher and LAN module together, then restarts the launcher. Close Battlefront II first.'
                      : 'Update the official Kyber game module. Your LAN module will not be changed.',
                  style: TextStyle(
                    fontSize: 15,
                  ),
                ),
                //const Text(
                //  'Changelog:',
                //  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                //),
                //const SizedBox(height: 16),
                //MarkdownBody(
                //  data: 'Dummy Changelog\n\n[View Dummy](#)',
                //  onTapLink: (String text, String? href, String title) {
                //    if (href == null || href == '#') {
                //      return;
                //    }
                //    launchUrlString(href);
                //  },
                //),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
