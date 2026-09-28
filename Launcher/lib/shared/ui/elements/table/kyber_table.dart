import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/shared/ui/elements/table/kyber_table_item.dart';

class KyberTable extends StatefulWidget {
  const KyberTable({required this.items, super.key, this.itemStyle});

  final TextStyle? itemStyle;
  final List<KyberTableItem> items;

  @override
  State<KyberTable> createState() => _KyberTableState();
}

class _KyberTableState extends State<KyberTable> {
  bool hovered = false;
  int hoveredIndex = 0;

  @override
  Widget build(BuildContext context) {
    final theme = FluentTheme.of(context);
    final convertedStyle = const TextStyle(
      color: Colors.white,
      fontSize: 20,
      fontWeight: FontWeight.bold,
      fontFamily: FontFamily.battlefrontUI,
    ).merge(widget.itemStyle);

    return SizedBox(
      width: 200,
      child: FluentTheme(
        data: theme.copyWith(
          typography: theme.typography.merge(
            Typography.raw(body: convertedStyle),
          ),
        ),
        child: ListView.separated(
          itemCount: widget.items.length + 2,
          physics: const NeverScrollableScrollPhysics(),
          separatorBuilder: (context, index) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 2,
            color:
                hovered && (hoveredIndex == index || hoveredIndex == index - 1)
                ? kActiveColor
                : decoColor,
          ),
          itemBuilder: (context, index) {
            if (index == 0 || index == widget.items.length + 1) {
              return const SizedBox.shrink();
            }

            final item = widget.items[index - 1];
            return MouseRegion(
              onEnter: (_) {
                setState(() {
                  hovered = true;
                  hoveredIndex = index - 1;
                });
              },
              onExit: (_) {
                setState(() {
                  hovered = false;
                  hoveredIndex = 0;
                });
              },
              child: item,
            );
          },
          shrinkWrap: true,
        ),
      ),
    );
  }
}
