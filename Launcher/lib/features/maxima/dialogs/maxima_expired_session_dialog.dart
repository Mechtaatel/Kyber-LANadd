import 'dart:io';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/core.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class MaximaExpiredSessionDialog extends StatefulWidget {
  const MaximaExpiredSessionDialog({super.key});

  @override
  State<MaximaExpiredSessionDialog> createState() =>
      _MaximaExpiredSessionDialogState();
}

class _MaximaExpiredSessionDialogState
    extends State<MaximaExpiredSessionDialog> {
  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      title: const Text('EA session expired'),
      constraints: const BoxConstraints(maxWidth: 650, maxHeight: 400),
      content: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your EA session has expired, to continue, please log in again after exiting the launcher.',
            style: TextStyle(
              color: kWhiteColor,
              fontSize: 15,
            ),
          ),
        ],
      ),
      actions: [
        KyberButton(
          text: 'Restart and sign in',
          onPressed: () async {
            final authFile = File(
              '${Platform.environment['APPDATA']}\\ArmchairDevelopers\\Maxima\\data\\auth.toml',
            );
            if (await authFile.exists()) await authFile.delete();

            final executable = Platform.resolvedExecutable;
            final args = <String>['--restart'];
            final workingDirectory = Directory.current.path;

            await Process.start(
              executable,
              args,
              workingDirectory: workingDirectory,
            );
            exit(0);
          },
        ),
      ],
    );
  }
}
