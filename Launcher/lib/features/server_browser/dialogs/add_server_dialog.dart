import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber/kyber.dart';
import 'package:kyber_launcher/features/server_browser/providers/server_list_cubit.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class AddServerDialog extends StatefulWidget {
  const AddServerDialog({required this.servers, super.key});

  final ServerListCubit servers;

  @override
  State<AddServerDialog> createState() => _AddServerDialogState();
}

class _AddServerDialogState extends State<AddServerDialog> {
  final address = TextEditingController();
  String? error;
  bool searching = false;

  @override
  void dispose() {
    address.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (searching) return;
    final endpoint = ServerEndpoint.tryParse(address.text);
    if (endpoint == null) {
      setState(
        () => error = 'Enter an IPv4 address and a UDP port from 1 to 65535.',
      );
      return;
    }
    setState(() {
      searching = true;
      error = null;
    });
    try {
      final server = await widget.servers.findEndpoint(endpoint);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (server == null) {
        setState(() => error = 'No server replied at $endpoint.');
        return;
      }
      if (widget.servers.localOnly && !server.isLanOnly) {
        setState(() => error = 'This server requires a Kyber sign-in.');
        return;
      }
      await widget.servers.rememberEndpoint(endpoint, server);
      if (mounted && ModalRoute.of(context)?.isCurrent == true)
        Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not add server: $e');
    } finally {
      if (mounted) setState(() => searching = false);
    }
  }

  @override
  Widget build(BuildContext context) => KyberContentDialog(
    compact: true,
    title: const Text('Add server by IP'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextBox(
          controller: address,
          autofocus: true,
          enabled: !searching,
          placeholder: '192.168.0.155:25200',
          onSubmitted: (_) => submit(),
        ),
        if (searching)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: ProgressBar(),
          ),
        if (error != null)
          Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!)),
      ],
    ),
    actions: [
      KyberButton(text: 'CANCEL', onPressed: () => Navigator.pop(context)),
      KyberButton(text: 'ACCEPT', onPressed: searching ? null : submit),
    ],
  );
}
