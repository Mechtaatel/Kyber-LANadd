import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';

class NavigationBarSeperator extends StatelessWidget {
  const NavigationBarSeperator({
    required this.active,
    required this.hover,
    required this.showPositioned,
    super.key,
  });

  final bool hover;
  final bool active;
  final bool showPositioned;

  @override
  Widget build(BuildContext context) {
    late Color color;
    if (hover) {
      color = kActiveColor;
    } else if (active) {
      color = kInactiveColor;
    } else {
      color = kWhiteBackgroundColor;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 50),
          height: 41,
          width: 2,
          color: color,
        ),
        AnimatedPositioned(
          bottom: active && showPositioned ? -6 : 0,
          duration: Duration(milliseconds: showPositioned ? 100 : 0),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 50),
            height: 3,
            width: 2,
            color: color,
          ),
        ),
      ],
    );
  }
}
