/// SMT-FAI logo: a board with a chip under an inspection reticle and a pass
/// mark. Flat colours only. Used in the title bar and for launcher icons.
library;

import 'package:flutter/widgets.dart';

const logoBackground = Color(0xFF1B1E24);
const logoBoard = Color(0xFFDDE1E6);
const logoAccent = Color(0xFF4C8DF6);
const logoPass = Color(0xFF22C55E);

class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: const LogoPainter());
}

class LogoPainter extends CustomPainter {
  const LogoPainter({this.background = true, this.inset = 0});

  /// Draw the rounded-square tile (off for Android adaptive foregrounds).
  final bool background;

  /// Fraction of the size kept clear around the artwork.
  final double inset;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    if (background) {
      canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.22)), Paint()..color = logoBackground);
    }
    canvas.save();
    final k = 1 - 2 * inset;
    canvas.translate(s * inset, s * inset);
    canvas.scale(k);
    final u = s / 100;
    Offset p(double x, double y) => Offset(x * u, y * u);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Board outline.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(17 * u, 21 * u, 83 * u, 79 * u), Radius.circular(7 * u)),
      stroke
        ..color = logoBoard
        ..strokeWidth = 4.2 * u,
    );

    // Chip with pins.
    final chip = RRect.fromRectAndRadius(Rect.fromLTRB(39 * u, 39 * u, 61 * u, 61 * u), Radius.circular(3.5 * u));
    canvas.drawRRect(chip, Paint()..color = logoAccent);
    final pin = Paint()
      ..color = logoAccent
      ..strokeWidth = 3 * u
      ..strokeCap = StrokeCap.round;
    for (final t in [44.5, 50.0, 55.5]) {
      canvas.drawLine(p(t, 32.5), p(t, 36), pin);
      canvas.drawLine(p(t, 64), p(t, 67.5), pin);
      canvas.drawLine(p(32.5, t), p(36, t), pin);
      canvas.drawLine(p(64, t), p(67.5, t), pin);
    }
    canvas.drawCircle(p(44.5, 44.5), 2 * u, Paint()..color = logoBackground);

    // Inspection reticle: four corner brackets around the chip.
    final ret = Paint()
      ..color = logoBoard
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2 * u
      ..strokeCap = StrokeCap.round;
    for (final (x, y, dx, dy) in [(28.0, 28.0, 1.0, 1.0), (72.0, 28.0, -1.0, 1.0), (28.0, 72.0, 1.0, -1.0)]) {
      canvas.drawPath(
        Path()
          ..moveTo(x * u, (y + 8 * dy) * u)
          ..lineTo(x * u, y * u)
          ..lineTo((x + 8 * dx) * u, y * u),
        ret,
      );
    }

    // Pass badge.
    canvas.drawCircle(p(74, 74), 15 * u, Paint()..color = logoBackground);
    canvas.drawCircle(p(74, 74), 12 * u, Paint()..color = logoPass);
    final check = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.6 * u
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(68.5 * u, 74.5 * u)
        ..lineTo(72.5 * u, 78.5 * u)
        ..lineTo(80 * u, 70 * u),
      check,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(LogoPainter old) => old.background != background || old.inset != inset;
}
