import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
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

  @override
  void initState() {
    if (WindowsUtils.isWindowsCompMode()) {
      isCompMode = true;
    } else if (widget.forceInstall && widget.module == VersionModule.module) {
      startDownload();
    }

    super.initState();
  }

  void startDownload() async {
    if (widget.module == VersionModule.installer) {
      await launchUrlString(
        'https://github.com/Mechtaatel/Kyber-LANadd/releases',
      );
      return;
    }
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
    } catch (error) {
      if (!mounted) return;
      setState(() => installing = false);
      NotificationService.error(message: 'Module update failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      title: Text(
        '${widget.module == VersionModule.module ? 'Module' : 'Launcher'} Update'
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
          onPressed: !installing ? startDownload : null,
          text: widget.module == VersionModule.installer
              ? 'OPEN RELEASES'
              : 'Install',
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
                      ? 'LAN ADD launcher and LAN module updates are available from our GitHub Releases. The official Kyber game module updates separately.'
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
