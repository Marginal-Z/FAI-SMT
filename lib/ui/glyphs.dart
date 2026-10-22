/// Hand-drawn duotone icon set for the ribbon and title bar.
///
/// Each glyph is drawn on a 24-unit grid: a fine outline in the foreground
/// colour plus one accent element (flat fill, no gradients), so the set reads
/// as one family at 22–32 px.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'theme.dart';

enum Glyph {
  bom,
  stationA,
  stationB,
  coords,
  unitAuto,
  unit,
  clear,
  runCheck,
  report,
  exclusion,
  alternates,
  program,
  general,
  layersBoth,
  layerTop,
  layerBottom,
  fit,
  cadFormat,
  cad,
  globe,
  sun,
  moon,
  system,
  info,
}

class GlyphIcon extends StatelessWidget {
  const GlyphIcon(this.glyph, {super.key, this.size = 28, this.color, this.accent, this.disabled = false});

  final Glyph glyph;
  final double size;
  final Color? color;
  final Color? accent;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final fg = disabled ? c.textFaint : (color ?? c.text);
    final ac = disabled ? c.textFaint : (accent ?? c.accent);
    return CustomPaint(
      size: Size.square(size),
      painter: _GlyphPainter(glyph, fg, ac, c.dark ? c.ribbon : c.panel),
    );
  }
}

class _GlyphPainter extends CustomPainter {
  _GlyphPainter(this.glyph, this.fg, this.accent, this.knockout);

  final Glyph glyph;
  final Color fg;
  final Color accent;

  /// Background colour used to cut badges out of the outline.
  final Color knockout;

  late double _u;

  Paint get _line => Paint()
    ..color = fg
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5 * _u
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _accentLine => Paint()
    ..color = accent
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.6 * _u
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint get _tint => Paint()..color = accent.withValues(alpha: 0.18);

  Paint get _solid => Paint()..color = accent;

  Offset p(double x, double y) => Offset(x * _u, y * _u);

  Rect r(double l, double t, double w, double h) => Rect.fromLTWH(l * _u, t * _u, w * _u, h * _u);

  RRect rr(double l, double t, double w, double h, double rad) => RRect.fromRectAndRadius(r(l, t, w, h), Radius.circular(rad * _u));

  Path poly(List<List<double>> pts, {bool close = false}) {
    final path = Path()..moveTo(pts.first[0] * _u, pts.first[1] * _u);
    for (final q in pts.skip(1)) {
      path.lineTo(q[0] * _u, q[1] * _u);
    }
    if (close) path.close();
    return path;
  }

  void _badge(Canvas canvas, double cx, double cy, double radius, {String? letter}) {
    canvas.drawCircle(p(cx, cy), (radius + 1.4) * _u, Paint()..color = knockout);
    canvas.drawCircle(p(cx, cy), radius * _u, _solid);
    if (letter != null) {
      // Letters are stroked paths so they look the same with any font.
      final white = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.35 * _u
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final h = radius * 0.62;
      final w = radius * 0.5;
      if (letter == 'A') {
        canvas.drawPath(
          poly([
            [cx - w, cy + h],
            [cx, cy - h],
            [cx + w, cy + h],
          ]),
          white,
        );
        canvas.drawLine(p(cx - w * 0.55, cy + h * 0.3), p(cx + w * 0.55, cy + h * 0.3), white);
      } else {
        final l = cx - w * 0.8;
        final path = Path()
          ..moveTo(l * _u, (cy - h) * _u)
          ..lineTo(l * _u, (cy + h) * _u)
          ..lineTo((cx + w * 0.15) * _u, (cy + h) * _u)
          ..arcToPoint(p(cx + w * 0.15, cy), radius: Radius.circular(h * 0.5 * _u), clockwise: false)
          ..lineTo(l * _u, cy * _u)
          ..moveTo(l * _u, (cy - h) * _u)
          ..lineTo((cx + w * 0.05) * _u, (cy - h) * _u)
          ..arcToPoint(p(cx + w * 0.05, cy), radius: Radius.circular(h * 0.5 * _u))
          ..lineTo(l * _u, cy * _u);
        canvas.drawPath(path, white);
      }
    }
  }

  /// Sheet of paper with a folded corner.
  void _sheet(Canvas canvas, {double l = 4.5, double t = 2.5, double w = 13, double h = 18}) {
    const fold = 4.0;
    canvas.drawPath(
      poly([
        [l, t + 1.5],
        [l, t + h - 1.5],
        [l + 1.5, t + h],
        [l + w - 1.5, t + h],
        [l + w, t + h - 1.5],
        [l + w, t + fold],
        [l + w - fold, t],
        [l + 1.5, t],
      ], close: true),
      _line,
    );
    canvas.drawPath(
      poly([
        [l + w - fold, t],
        [l + w - fold, t + fold],
        [l + w, t + fold],
      ]),
      _line,
    );
  }

  /// Feeder rack: base rail with three reels.
  void _rack(Canvas canvas) {
    canvas.drawRRect(rr(2.5, 13.5, 17, 5.5, 1.2), _line);
    for (final x in [6.0, 11.0, 16.0]) {
      canvas.drawCircle(p(x, 8.5), 2.6 * _u, _line);
      canvas.drawCircle(p(x, 8.5), 0.8 * _u, Paint()..color = fg);
      canvas.drawLine(p(x, 11.1), p(x, 13.5), _line);
    }
    canvas.drawRRect(rr(2.5, 13.5, 17, 5.5, 1.2), _tint);
  }

  /// Chip body with pins on two sides.
  void _chip(Canvas canvas, double l, double t, double s, {bool tint = false}) {
    final body = rr(l, t, s, s, 1.2);
    if (tint) canvas.drawRRect(body, _tint);
    canvas.drawRRect(body, _line);
    final n = s > 8 ? 3 : 2;
    for (var i = 0; i < n; i++) {
      final y = t + s * (i + 1) / (n + 1);
      canvas.drawLine(p(l - 2, y), p(l, y), _line);
      canvas.drawLine(p(l + s, y), p(l + s + 2, y), _line);
    }
  }

  void _arrow(Canvas canvas, Offset from, Offset to, Paint paint, {double head = 2.6}) {
    canvas.drawLine(p(from.dx, from.dy), p(to.dx, to.dy), paint);
    final a = math.atan2(to.dy - from.dy, to.dx - from.dx);
    for (final s in [-1, 1]) {
      final b = a + math.pi + s * math.pi / 4;
      canvas.drawLine(p(to.dx, to.dy), p(to.dx + head * math.cos(b), to.dy + head * math.sin(b)), paint);
    }
  }

  void _layers(Canvas canvas, {required bool top, required bool bottom}) {
    Path plate(double y) => poly([
          [12, y],
          [21, y + 4],
          [12, y + 8],
          [3, y + 4],
        ], close: true);
    final low = plate(10);
    final high = plate(4);
    if (bottom) canvas.drawPath(low, _tint);
    canvas.drawPath(low, bottom ? _accentLine : _line);
    canvas.drawPath(high, Paint()..color = knockout);
    if (top) canvas.drawPath(high, _tint);
    canvas.drawPath(high, top ? _accentLine : _line);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _u = size.width / 24;
    switch (glyph) {
      case Glyph.bom:
        _sheet(canvas);
        // Tree: parent node and two children.
        canvas.drawRRect(rr(7.5, 7.5, 4, 3, 0.8), _solid);
        canvas.drawPath(
          poly([
            [9.5, 10.5],
            [9.5, 16],
            [12.5, 16],
          ]),
          _accentLine,
        );
        canvas.drawLine(p(9.5, 13), p(12.5, 13), _accentLine);
        canvas.drawLine(p(14, 13), p(15, 13), _line);
        canvas.drawLine(p(14, 16), p(15, 16), _line);
      case Glyph.stationA:
      case Glyph.stationB:
        _rack(canvas);
        _badge(canvas, 18.5, 18.5, 4.2, letter: glyph == Glyph.stationA ? 'A' : 'B');
      case Glyph.coords:
        canvas.drawRRect(rr(3, 3, 18, 18, 2), _line);
        for (final v in [9.0, 15.0]) {
          canvas.drawLine(p(v, 3.5), p(v, 5), _line);
          canvas.drawLine(p(3.5, v), p(5, v), _line);
        }
        canvas.drawCircle(p(13, 13), 4 * _u, _tint);
        canvas.drawCircle(p(13, 13), 4 * _u, _accentLine);
        canvas.drawLine(p(13, 6.5), p(13, 9), _accentLine);
        canvas.drawLine(p(13, 17), p(13, 19.5), _accentLine);
        canvas.drawLine(p(6.5, 13), p(9, 13), _accentLine);
        canvas.drawLine(p(17, 13), p(19.5, 13), _accentLine);
        canvas.drawCircle(p(13, 13), 1 * _u, _solid);
      case Glyph.unitAuto:
      case Glyph.unit:
        canvas.save();
        canvas.translate(12 * _u, 12 * _u);
        canvas.rotate(-math.pi / 4);
        canvas.translate(-12 * _u, -12 * _u);
        canvas.drawRRect(rr(2, 8.5, 20, 7, 1.2), _tint);
        canvas.drawRRect(rr(2, 8.5, 20, 7, 1.2), _line);
        for (var i = 0; i < 7; i++) {
          final x = 4.5 + i * 2.5;
          canvas.drawLine(p(x, 8.5), p(x, i.isEven ? 12 : 10.5), _line);
        }
        canvas.restore();
        if (glyph == Glyph.unitAuto) {
          // Four-point spark.
          final c = p(5.5, 5.5);
          final s = 3.6 * _u;
          final spark = Path()
            ..moveTo(c.dx, c.dy - s)
            ..quadraticBezierTo(c.dx, c.dy, c.dx + s, c.dy)
            ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy + s)
            ..quadraticBezierTo(c.dx, c.dy, c.dx - s, c.dy)
            ..quadraticBezierTo(c.dx, c.dy, c.dx, c.dy - s);
          canvas.drawPath(spark, _solid);
        }
      case Glyph.clear:
        canvas.save();
        canvas.translate(12 * _u, 12 * _u);
        canvas.rotate(-math.pi / 4);
        canvas.translate(-12 * _u, -12 * _u);
        canvas.drawRRect(rr(4, 8, 16, 8, 1.5), _line);
        canvas.drawRRect(rr(4, 8, 6, 8, 1.5), _solid);
        canvas.restore();
        canvas.drawLine(p(11, 20.5), p(21, 20.5), _line);
      case Glyph.runCheck:
        canvas.drawRRect(rr(4.5, 4.5, 15, 17, 2), _line);
        canvas.drawRRect(rr(8.5, 2.5, 7, 4, 1.2), Paint()..color = knockout);
        canvas.drawRRect(rr(8.5, 2.5, 7, 4, 1.2), _line);
        canvas.drawCircle(p(12, 14), 5 * _u, _tint);
        canvas.drawPath(
          poly([
            [9.3, 14.2],
            [11.3, 16.2],
            [15, 12],
          ]),
          _accentLine..strokeWidth = 2 * _u,
        );
      case Glyph.report:
        canvas.drawRRect(rr(3, 3.5, 15, 15, 1.8), _line);
        canvas.drawRect(r(3.75, 4.25, 13.5, 3.5), _tint);
        canvas.drawLine(p(3, 8), p(18, 8), _line);
        canvas.drawLine(p(3, 13), p(18, 13), _line);
        canvas.drawLine(p(8.5, 8), p(8.5, 18.5), _line);
        _badge(canvas, 18, 18, 4.5);
        _arrow(canvas, const Offset(18, 15.4), const Offset(18, 20.4), Paint()
          ..color = const Color(0xFFFFFFFF)
          ..strokeWidth = 1.5 * _u
          ..strokeCap = StrokeCap.round, head: 2);
      case Glyph.exclusion:
        _sheet(canvas, l: 3.5, t: 2.5, w: 12.5, h: 17);
        canvas.drawLine(p(6.5, 9), p(12, 9), _line);
        canvas.drawLine(p(6.5, 12.5), p(10, 12.5), _line);
        canvas.drawCircle(p(16.5, 16.5), 5.6 * _u, Paint()..color = knockout);
        canvas.drawCircle(p(16.5, 16.5), 4.4 * _u, _tint);
        canvas.drawCircle(p(16.5, 16.5), 4.4 * _u, _accentLine);
        canvas.drawLine(p(13.4, 19.6), p(19.6, 13.4), _accentLine);
      case Glyph.alternates:
        _chip(canvas, 3, 8.5, 6.5);
        _chip(canvas, 14.5, 8.5, 6.5, tint: true);
        final arc = Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * _u
          ..strokeCap = StrokeCap.round;
        canvas.drawArc(r(7, 2, 10, 9), math.pi * 1.1, math.pi * 0.8, false, arc);
        canvas.drawArc(r(7, 13, 10, 9), math.pi * 0.1, math.pi * 0.8, false, arc);
        _arrow(canvas, const Offset(15.5, 3.4), const Offset(16.6, 4.6), arc, head: 2.2);
        _arrow(canvas, const Offset(8.5, 20.6), const Offset(7.4, 19.4), arc, head: 2.2);
      case Glyph.program:
        _chip(canvas, 4.5, 4.5, 15);
        canvas.drawPath(
          poly([
            [13, 7],
            [9, 12.6],
            [12, 12.6],
            [11, 17],
            [15, 11.4],
            [12, 11.4],
          ], close: true),
          _solid,
        );
      case Glyph.general:
        for (final (y, x) in [(6.0, 15.0), (12.0, 8.0), (18.0, 13.0)]) {
          canvas.drawLine(p(3, y), p(21, y), _line);
          canvas.drawCircle(p(x, y), 2.4 * _u, Paint()..color = knockout);
          canvas.drawCircle(p(x, y), 2.4 * _u, y == 12 ? _solid : _line);
        }
      case Glyph.layersBoth:
        _layers(canvas, top: true, bottom: true);
      case Glyph.layerTop:
        _layers(canvas, top: true, bottom: false);
      case Glyph.layerBottom:
        _layers(canvas, top: false, bottom: true);
      case Glyph.fit:
        for (final (x, y, dx, dy) in [(3.0, 3.0, 1.0, 1.0), (21.0, 3.0, -1.0, 1.0), (3.0, 21.0, 1.0, -1.0), (21.0, 21.0, -1.0, -1.0)]) {
          canvas.drawPath(
            poly([
              [x, y + 5 * dy],
              [x, y],
              [x + 5 * dx, y],
            ]),
            _line,
          );
        }
        canvas.drawRRect(rr(8, 8, 8, 8, 1.2), _tint);
        canvas.drawRRect(rr(8, 8, 8, 8, 1.2), _accentLine);
      case Glyph.cadFormat:
        canvas.drawRRect(rr(3, 4, 18, 16, 1.8), _line);
        canvas.drawRect(r(3.75, 4.75, 16.5, 3.75), _tint);
        canvas.drawLine(p(3, 9), p(21, 9), _line);
        canvas.drawLine(p(9, 4), p(9, 20), _line);
        canvas.drawLine(p(15, 4), p(15, 20), _line);
        for (final y in [12.5, 16.0]) {
          canvas.drawLine(p(5, y), p(7, y), _accentLine);
          canvas.drawLine(p(11, y), p(13, y), _accentLine);
          canvas.drawLine(p(17, y), p(19, y), _accentLine);
        }
      case Glyph.cad:
        canvas.drawRRect(rr(2.5, 4.5, 15, 15, 2), _line);
        _chip(canvas, 6.5, 8.5, 7, tint: true);
        _badge(canvas, 18.5, 6, 4.6);
        _arrow(canvas, const Offset(16.6, 7.9), const Offset(20.4, 4.1), Paint()
          ..color = const Color(0xFFFFFFFF)
          ..strokeWidth = 1.5 * _u
          ..strokeCap = StrokeCap.round, head: 2);
      case Glyph.globe:
        canvas.drawCircle(p(12, 12), 8.5 * _u, _line);
        canvas.drawOval(r(8.2, 3.5, 7.6, 17), _line);
        canvas.drawLine(p(3.5, 12), p(20.5, 12), _line);
        canvas.drawLine(p(5, 7.5), p(19, 7.5), _line);
        canvas.drawLine(p(5, 16.5), p(19, 16.5), _line);
      case Glyph.sun:
        canvas.drawCircle(p(12, 12), 4 * _u, _tint);
        canvas.drawCircle(p(12, 12), 4 * _u, _line);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawLine(p(12 + 6.5 * math.cos(a), 12 + 6.5 * math.sin(a)), p(12 + 8.5 * math.cos(a), 12 + 8.5 * math.sin(a)), _line);
        }
      case Glyph.moon:
        final crescent = Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: p(12, 12), radius: 8 * _u)),
          Path()..addOval(Rect.fromCircle(center: p(16.5, 8), radius: 6.5 * _u)),
        );
        canvas.drawPath(crescent, _tint);
        canvas.drawPath(crescent, _line);
      case Glyph.system:
        canvas.drawCircle(p(12, 12), 8 * _u, _line);
        canvas.drawPath(
          Path()
            ..moveTo(12 * _u, 4 * _u)
            ..arcTo(Rect.fromCircle(center: p(12, 12), radius: 8 * _u), -math.pi / 2, math.pi, false)
            ..close(),
          _solid,
        );
      case Glyph.info:
        canvas.drawCircle(p(12, 12), 8.5 * _u, _line);
        canvas.drawLine(p(12, 11), p(12, 16.5), _accentLine..strokeWidth = 2 * _u);
        canvas.drawCircle(p(12, 7.8), 1.2 * _u, _solid);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.fg != fg || old.accent != accent || old.knockout != knockout;
}
