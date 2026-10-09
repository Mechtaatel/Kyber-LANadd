import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as mt;
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';

class ServerListHeader extends StatelessWidget {
  const ServerListHeader({super.key, this.withoutQuickJoin = false});

  final bool withoutQuickJoin;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border.symmetric(
          vertical: BorderSide(
            color: decoColor,
            width: 2,
          ),
        ),
      ),
      alignment: Alignment.center,
      child: KyberHeader(
        title: 'SERVER BROWSER',
        headerLength: 150,
        sections: [
          const ExpandedHeaderSection(children: []),
          const FixedWidthHeaderSection(
            width: 99,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'PLAYERS',
                textAlign: TextAlign.left,
              ),
            ],
          ),
          const FixedWidthHeaderSection(
            width: 120,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'SERVER TYPE',
                textAlign: TextAlign.left,
              ),
            ],
          ),
          if (!withoutQuickJoin)
            FixedWidthHeaderSection(
              width: 67,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Text('PLAY'.toUpperCase())],
            ),
        ],
      ),
    );
  }
}

class DashedLineVerticalPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const double dashHeight = 5;
    const double dashSpace = 5;
    double startY = 4;
    final paint = Paint()
      ..color = decoColor
      ..strokeWidth = size.width;
    final stopY = size.height - 4;
    while (startY < stopY) {
      canvas.drawLine(Offset(0, startY), Offset(0, startY + dashHeight), paint);
      startY += dashHeight + dashSpace;
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}
