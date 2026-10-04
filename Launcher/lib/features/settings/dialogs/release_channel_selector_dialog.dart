import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/core/services/module_version_service.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';

class ReleaseChannelSelectorDialog extends StatefulWidget {
  const ReleaseChannelSelectorDialog({super.key});

  @override
  State<ReleaseChannelSelectorDialog> createState() =>
      _ReleaseChannelSelectorDialogState();
}

class _ReleaseChannelSelectorDialogState
    extends State<ReleaseChannelSelectorDialog> {
  late TextEditingController _controller;
  late VersionModule _selectedModule;

  @override
  void initState() {
    _selectedModule = VersionModule.installer;
    _controller = TextEditingController(text: _selectedModule.releaseChannel);
    super.initState();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      constraints: const BoxConstraints(
        maxHeight: 400,
        maxWidth: 600,
      ),
      title: Text('release channel'.toUpperCase()),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'target service'.toUpperCase(),
            style: const TextStyle(
              color: kWhiteColor,
            ),
          ),
          const SizedBox(height: 5),
          ComboBox<VersionModule>(
            value: _selectedModule,
            isExpanded: true,
            items: VersionModule.values.map<ComboBoxItem<VersionModule>>((e) {
              return ComboBoxItem<VersionModule>(
                value: e,
                child: Text(
                  e == VersionModule.installer
                      ? 'LAN ADD launcher + module (GitHub)'
                      : 'Official Kyber module',
                ),
              );
            }).toList(),
            onChanged: (item) {
              setState(() => _selectedModule = item!);
              _controller.text = item!.releaseChannel;
            },
          ),
          const SizedBox(height: 20),
          Text(
            'Release Channel'.toUpperCase(),
            style: const TextStyle(
              color: kWhiteColor,
            ),
          ),
          if (_selectedModule == VersionModule.installer)
            ComboBox<String>(
              value: _controller.text,
              isExpanded: true,
              items: const [
                ComboBoxItem(value: 'beta', child: Text('BETA / PRE-RELEASE')),
                ComboBoxItem(value: 'stable', child: Text('STABLE')),
              ],
              onChanged: (value) => setState(() => _controller.text = value!),
            )
          else
            TextBox(
              controller: _controller,
              placeholder: 'Release channel',
            ),
        ],
      ),
      actions: [
        KyberButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          text: 'Cancel',
        ),
        KyberButton(
          onPressed: () async {
            if (_controller.text.isEmpty) {
              NotificationService.showNotification(
                message: 'Please enter a release channel.',
                severity: InfoBarSeverity.error,
              );
              return;
            }

            final isValid = await ModuleVersionService().checkChannel(
              module: _selectedModule,
              channel: _controller.text,
            );
            if (!isValid) {
              NotificationService.showNotification(
                message: 'The release channel is not valid. Please try again.',
                severity: InfoBarSeverity.error,
              );
              return;
            }

            if (_selectedModule == VersionModule.installer) {
              NotificationService.showNotification(
                message: 'To apply the changes, please restart the launcher.',
              );
            }

            await _selectedModule.setReleaseChannel(_controller.text);
            Navigator.of(context).pop();
          },
          text: 'Apply',
        ),
      ],
    );
  }
}
