import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/utils/custom_logger.dart';

class ExportLogsButton extends StatefulWidget {
  const ExportLogsButton({super.key});

  @override
  State<ExportLogsButton> createState() => _ExportLogsButtonState();
}

class _ExportLogsButtonState extends State<ExportLogsButton> {
  bool _exporting = false;

  Future<void> _export() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await CustomLogger.requestLogExport();
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      hint: 'Ctrl+Alt+Space',
      child: Button(
        onPressed: _exporting ? null : _export,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_exporting)
              const SizedBox(
                width: 14,
                height: 14,
                child: ProgressRing(strokeWidth: 2),
              )
            else
              const Icon(FluentIcons.diagnostic, size: 16),
            const SizedBox(width: 8),
            Text(_exporting ? 'Exporting logs...' : 'Export Logs'),
          ],
        ),
      ),
    );
  }
}
