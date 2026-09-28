import 'package:flutter/material.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';

class SetTokenDialog extends StatefulWidget {
  const SetTokenDialog({super.key});

  @override
  State<SetTokenDialog> createState() => _SetTokenDialogState();
}

class _SetTokenDialogState extends State<SetTokenDialog> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return KyberContentDialog(
      title: const Text('Set Token'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enter the token address'),
          const SizedBox(height: 10),
          TextField(
            style: const TextStyle(color: kWhiteColor),
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'TOKEN',
            ),
          ),
        ],
      ),
      actions: [
        KyberButton(
          text: 'CANCEL',
          onPressed: () => Navigator.of(context).pop(),
        ),
        KyberButton(
          text: 'SET',
          onPressed: () {
            Navigator.pop(context, controller.text);
          },
        ),
      ],
    );
  }
}
