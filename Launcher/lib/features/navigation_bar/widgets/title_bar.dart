import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';

class TitleBar extends StatelessWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const .only(top: 10),
      child: Row(
        children: [
          Assets.icons.betaIcon.svg(height: 20),
          const _LanAddBadge(),
          const Spacer(),
        ],
      ),
    );
  }
}

class _LanAddBadge extends StatelessWidget {
  const _LanAddBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'LAN ADD',
      image: true,
      excludeSemantics: true,
      child: SizedBox(
        width: 20 * 606.32 / 177.05,
        height: 20,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SvgPicture.asset('assets/icons/lan_add_badge.svg', height: 20),
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Text(
                'LAN ADD',
                textScaler: TextScaler.noScaling,
                style: TextStyle(
                  fontFamily: FontFamily.battlefrontUI,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.3,
                  color: Color(0xFFF5A9B8),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
