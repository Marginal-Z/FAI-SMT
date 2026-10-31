/// Lucide line icons (ISC licence) as used by the SMT-FAI design, drawn from
/// their SVG source on a 24 × 24 grid with round caps and joins.
library;

import 'package:flutter/widgets.dart';

/// One icon: SVG elements in a compact form.
///   'M…'                  path data
///   'rect x y w h rx'     rounded rectangle
///   'circle cx cy r'      circle
///   'line x1 y1 x2 y2'    line
///   'poly x,y x,y …'      polyline
/// A leading '*' fills the element with the icon colour instead of stroking.
class Lucide {
  const Lucide(this.parts);

  final List<String> parts;

  static const cpu = Lucide(['rect 4 4 16 16 3', 'rect 9 9 6 6 1.5', 'M15 2v2M15 20v2M2 15h2M2 9h2M20 15h2M20 9h2M9 2v2M9 20v2']);
  static const chevronDown = Lucide(['m6 9 6 6 6-6']);
  static const chevronLeft = Lucide(['m15 18-6-6 6-6']);
  static const more = Lucide(['circle 12 12 1', 'circle 19 12 1', 'circle 5 12 1']);
  static const circle = Lucide(['circle 12 12 9']);
  static const externalLink = Lucide(['M15 3h6v6', 'M10 14 21 3', 'M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6']);
  static const copy = Lucide(['rect 8 8 14 14 2', 'M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2']);
  static const locate = Lucide(['M2 12h3M19 12h3M12 2v3M12 19v3', 'circle 12 12 7', 'circle 12 12 3']);
  static const chevronRight = Lucide(['m9 18 6-6-6-6']);
  static const theme = Lucide(['circle 12 12 9', '*M12 3a9 9 0 0 1 0 18Z']);
  static const help = Lucide(['circle 12 12 10', 'M9.09 9a3 3 0 0 1 5.83 1c0 2-3 3-3 3', 'M12 17h.01']);
  static const settings = Lucide([
    'line 21 4 14 4', 'line 10 4 3 4', 'line 21 12 12 12', 'line 8 12 3 12', 'line 21 20 16 20', 'line 12 20 3 20', //
    'line 14 2 14 6', 'line 8 10 8 14', 'line 16 18 16 22',
  ]);
  static const clipboardCheck = Lucide(['rect 8 2 8 4 1', 'M16 4h2a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2h2', 'm9 14 2 2 4-4']);
  static const sheetTop = Lucide(['rect 3 3 18 18 3.5', '*M3 6.5A3.5 3.5 0 0 1 6.5 3h11A3.5 3.5 0 0 1 21 6.5V11H3Z']);
  static const sheetBottom = Lucide(['rect 3 3 18 18 3.5', '*M3 13h18v4.5a3.5 3.5 0 0 1-3.5 3.5h-11A3.5 3.5 0 0 1 3 17.5Z']);
  static const plus = Lucide(['M12 5v14', 'M5 12h14']);
  static const minus = Lucide(['M5 12h14']);
  static const check = Lucide(['M20 6 9 17l-5-5']);
  static const x = Lucide(['M18 6 6 18', 'm6 6 12 12']);
  static const trash = Lucide(['M3 6h18', 'M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6', 'M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2']);
  static const package = Lucide(['M21 8 12 3 3 8v8l9 5 9-5Z', 'm3.3 7.5 8.7 5 8.7-5', 'M12 22V12.5']);
  static const swap = Lucide(['M17 4l4 4-4 4', 'M3 8h18', 'M7 20l-4-4 4-4', 'M21 16H3']);
  static const alert = Lucide(['M12 3 2 20h20Z', 'M12 10v4', 'M12 17h.01']);
  static const search = Lucide(['circle 11 11 8', 'm21 21-4.3-4.3']);
  static const download = Lucide(['M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4', 'poly 7,10 12,15 17,10', 'line 12 15 12 3']);
  static const exportArrow = Lucide(['M12 3v12', 'm7 10 5 5 5-5', 'M5 21h14']);
  static const fileText = Lucide(['M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z', 'M14 2v4a2 2 0 0 0 2 2h4', 'M10 13h4', 'M10 17h4']);
  static const fileCheck = Lucide(['M15 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V7Z', 'M14 2v4a2 2 0 0 0 2 2h4', 'm9 15 2 2 4-4']);
  static const refresh = Lucide(['M3 12a9 9 0 0 1 15-6.7L21 8', 'M21 3v5h-5', 'M21 12a9 9 0 0 1-15 6.7L3 16', 'M3 21v-5h5']);
  static const ruler = Lucide([
    'M21.3 15.3a2.4 2.4 0 0 1 0 3.4l-2.6 2.6a2.4 2.4 0 0 1-3.4 0L2.7 8.7a2.4 2.4 0 0 1 0-3.4l2.6-2.6a2.4 2.4 0 0 1 3.4 0Z',
    'm14.5 12.5 2-2',
    'm11.5 9.5 2-2',
    'm8.5 6.5 2-2',
    'm17.5 15.5 2-2',
  ]);
  static const grid = Lucide(['rect 3 3 18 18 3', 'M3 9h18', 'M3 15h18', 'M9 3v18']);
  static const gear = Lucide([
    'M12.22 2h-.44a2 2 0 0 0-2 2v.18a2 2 0 0 1-1 1.73l-.43.25a2 2 0 0 1-2 0l-.15-.08a2 2 0 0 0-2.73.73l-.22.38a2 2 0 0 0 .73 2.73l.15.1a2 2 0 0 1 1 1.72v.51a2 2 0 0 1-1 1.74l-.15.09a2 2 0 0 0-.73 2.73l.22.38a2 2 0 0 0 2.73.73l.15-.08a2 2 0 0 1 2 0l.43.25a2 2 0 0 1 1 1.73V20a2 2 0 0 0 2 2h.44a2 2 0 0 0 2-2v-.18a2 2 0 0 1 1-1.73l.43-.25a2 2 0 0 1 2 0l.15.08a2 2 0 0 0 2.73-.73l.22-.39a2 2 0 0 0-.73-2.73l-.15-.08a2 2 0 0 1-1-1.74v-.5a2 2 0 0 1 1-1.74l.15-.09a2 2 0 0 0 .73-2.73l-.22-.38a2 2 0 0 0-2.73-.73l-.15.08a2 2 0 0 1-2 0l-.43-.25a2 2 0 0 1-1-1.73V4a2 2 0 0 0-2-2z',
    'circle 12 12 3',
  ]);
  static const info = Lucide(['circle 12 12 10', 'M12 16v-4', 'M12 8h.01']);
  static const folderOpen = Lucide([
    'm6 14 1.5-2.9A2 2 0 0 1 9.24 10H20a2 2 0 0 1 1.94 2.5l-1.54 6a2 2 0 0 1-1.95 1.5H4a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h3.9a2 2 0 0 1 1.69.9l.81 1.2a2 2 0 0 0 1.67.9H18a2 2 0 0 1 2 2v2',
  ]);
  static const layers = Lucide([
    'M12.83 2.18a2 2 0 0 0-1.66 0L2.6 6.08a1 1 0 0 0 0 1.83l8.58 3.91a2 2 0 0 0 1.66 0l8.58-3.9a1 1 0 0 0 0-1.83Z',
    'm22 17.65-9.17 4.16a2 2 0 0 1-1.66 0L2 17.65',
    'm22 12.65-9.17 4.16a2 2 0 0 1-1.66 0L2 12.65',
  ]);
  static const faceTop = Lucide(['rect 3 3 18 18 4', '*M3 7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4v5H3Z']);
  static const faceBottom = Lucide(['rect 3 3 18 18 4', '*M3 12h18v5a4 4 0 0 1-4 4H7a4 4 0 0 1-4-4Z']);
  static const mirror = Lucide(['m3 7 5 5-5 5V7', 'm21 7-5 5 5 5V7', 'M12 20v2', 'M12 14v2', 'M12 8v2', 'M12 2v2']);
  static const rotateLeft = Lucide(['M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8', 'M3 3v5h5']);
  static const rotateRight = Lucide(['M21 12a9 9 0 1 1-9-9c2.52 0 4.93 1 6.74 2.74L21 8', 'M21 3v5h-5']);
  static const fit = Lucide([
    'M3 7V5a2 2 0 0 1 2-2h2',
    'M17 3h2a2 2 0 0 1 2 2v2',
    'M21 17v2a2 2 0 0 1-2 2h-2',
    'M7 21H5a2 2 0 0 1-2-2v-2',
    'rect 7 8 10 8 1.5',
  ]);
  static const reset = Lucide(['M3 7v6h6', 'M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13']);
  static const fullscreen = Lucide(['M8 3H5a2 2 0 0 0-2 2v3', 'M21 8V5a2 2 0 0 0-2-2h-3', 'M3 16v3a2 2 0 0 0 2 2h3', 'M16 21h3a2 2 0 0 0 2-2v-3']);
  static const exitFullscreen = Lucide(['M8 3v3a2 2 0 0 1-2 2H3', 'M21 8h-3a2 2 0 0 1-2-2V3', 'M3 16h3a2 2 0 0 1 2 2v3', 'M16 21v-3a2 2 0 0 1 2-2h3']);
  static const palette = Lucide([
    'circle 13.5 6.5 .5',
    'circle 17.5 10.5 .5',
    'circle 8.5 7.5 .5',
    'circle 6.5 12.5 .5',
    'M12 2C6.5 2 2 6.5 2 12s4.5 10 10 10c.926 0 1.648-.746 1.648-1.688 0-.437-.18-.835-.437-1.125-.29-.289-.438-.652-.438-1.125a1.64 1.64 0 0 1 1.668-1.668h1.996c3.051 0 5.555-2.503 5.555-5.554C21.965 6.012 17.461 2 12 2z',
  ]);
  static const chevronUp = Lucide(['m18 15-6-6-6 6']);
  static const cube = Lucide(['M21 8 12 3 3 8v8l9 5 9-5Z', 'm3.3 7.5 8.7 5 8.7-5', 'M12 22V12.5']);
  static const back = Lucide(['m12 19-7-7 7-7', 'M19 12H5']);
  static const book = Lucide(['M2 3h6a4 4 0 0 1 4 4v14a3 3 0 0 0-3-3H2z', 'M22 3h-6a4 4 0 0 0-4 4v14a3 3 0 0 1 3-3h7z']);
  static const library = Lucide(['m16 6 4 14', 'M12 6v14', 'M8 8v12', 'M4 4v16']);
  static const shield = Lucide([
    'M20 13c0 5-3.5 7.5-7.66 8.95a1 1 0 0 1-.67-.01C7.5 20.5 4 18 4 13V6a1 1 0 0 1 1-1c2 0 4.5-1.2 6.24-2.72a1.17 1.17 0 0 1 1.52 0C14.51 3.81 17 5 19 5a1 1 0 0 1 1 1z',
    'm9 12 2 2 4-4',
  ]);
  static const update = Lucide([
    'M21 12a9 9 0 0 0-9-9 9.75 9.75 0 0 0-6.74 2.74L3 8',
    'M3 3v5h5',
    'M3 12a9 9 0 0 0 9 9 9.75 9.75 0 0 0 6.74-2.74L21 16',
    'M16 16h5v5',
  ]);
  static const brush = Lucide([
    'm9.06 11.9 8.07-8.06a2.85 2.85 0 1 1 4.03 4.03l-8.06 8.08',
    'M7.07 14.94c-1.66 0-3 1.35-3 3.02 0 1.33-2.5 1.52-2 2.02 1.08 1.1 2.49 2.02 4 2.02 2.2 0 4-1.8 4-4.04a3.01 3.01 0 0 0-3-3.02z',
  ]);
  static const lightbulb = Lucide([
    'M15 14c.2-1 .7-1.7 1.5-2.5 1-.9 1.5-2.2 1.5-3.5A6 6 0 0 0 6 8c0 1 .2 2.2 1.5 3.5.7.7 1.3 1.5 1.5 2.5',
    'M9 18h6',
    'M10 22h4',
  ]);
  static const play = Lucide(['*m6 3 14 9-14 9V3z']);
  static const stop = Lucide(['*rect 6 6 12 12 2']);
  static const gitCompare = Lucide(['circle 18 18 3', 'circle 6 6 3', 'M13 6h3a2 2 0 0 1 2 2v7', 'M11 18H8a2 2 0 0 1-2-2V9']);
  static const sparkles = Lucide([
    'M9.94 15.5A2 2 0 0 0 8.5 14.06l-6.14-1.58a.5.5 0 0 1 0-.96L8.5 9.94A2 2 0 0 0 9.94 8.5l1.58-6.14a.5.5 0 0 1 .96 0L14.06 8.5A2 2 0 0 0 15.5 9.94l6.14 1.58a.5.5 0 0 1 0 .96L15.5 14.06a2 2 0 0 0-1.44 1.44l-1.58 6.14a.5.5 0 0 1-.96 0z',
    'M20 3v4',
    'M22 5h-4',
  ]);
  static const pencil = Lucide(['M21.17 6.81a1 1 0 0 0-3.99-3.99L3.84 16.17a2 2 0 0 0-.5.83l-1.32 4.35a.5.5 0 0 0 .62.62l4.35-1.32a2 2 0 0 0 .83-.5z', 'm15 5 4 4']);
  static const undo = Lucide(['M3 7v6h6', 'M21 17a9 9 0 0 0-9-9 9 9 0 0 0-6 2.3L3 13']);
}

class LucideIcon extends StatelessWidget {
  const LucideIcon(this.icon, {super.key, this.size = 18, this.color, this.stroke = 1.8});

  final Lucide icon;
  final double size;
  final Color? color;

  /// Stroke width on the 24-unit grid.
  final double stroke;

  @override
  Widget build(BuildContext context) {
    final c = color ?? DefaultTextStyle.of(context).style.color ?? const Color(0xFF000000);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _LucidePainter(icon, c, stroke)),
    );
  }
}

class _LucidePainter extends CustomPainter {
  _LucidePainter(this.icon, this.color, this.stroke);

  final Lucide icon;
  final Color color;
  final double stroke;

  static final _cache = <String, Path>{};

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fillPaint = Paint()..color = color;
    for (final raw in icon.parts) {
      final fill = raw.startsWith('*');
      final spec = fill ? raw.substring(1) : raw;
      final path = _cache.putIfAbsent(spec, () => _parse(spec));
      canvas.drawPath(path, fill ? fillPaint : strokePaint);
    }
  }

  @override
  bool shouldRepaint(_LucidePainter old) => old.icon != icon || old.color != color || old.stroke != stroke;
}

Path _parse(String spec) {
  final words = spec.split(' ');
  List<double> nums() => [for (final w in words.skip(1)) double.parse(w)];
  switch (words.first) {
    case 'rect':
      final n = nums();
      return Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(n[0], n[1], n[2], n[3]), Radius.circular(n.length > 4 ? n[4] : 0)));
    case 'circle':
      final n = nums();
      return Path()..addOval(Rect.fromCircle(center: Offset(n[0], n[1]), radius: n[2]));
    case 'line':
      final n = nums();
      return Path()
        ..moveTo(n[0], n[1])
        ..lineTo(n[2], n[3]);
    case 'poly':
      final pts = [for (final w in words.skip(1)) Offset(double.parse(w.split(',')[0]), double.parse(w.split(',')[1]))];
      return Path()..addPolygon(pts, false);
  }
  return _svgPath(spec);
}

/// SVG path data: M L H V C S Q T A Z, absolute and relative.
Path _svgPath(String d) {
  final tokens = RegExp(r'[MmLlHhVvCcSsQqTtAaZz]|-?(?:\d+\.?\d*|\.\d+)(?:e-?\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var i = 0;
  var cmd = '';
  var cur = Offset.zero, start = Offset.zero, lastCtrl = Offset.zero;
  var lastCmd = '';
  bool isCmd(String t) => RegExp(r'^[A-Za-z]$').hasMatch(t);
  double next() => double.parse(tokens[i++]);
  // Arc flags may be packed without separators ("0 0 1" or "011").
  bool flag() {
    final t = tokens[i];
    if (t.length > 1 && (t.startsWith('0') || t.startsWith('1')) && !t.contains('.')) {
      tokens[i] = t.substring(1);
      return t[0] == '1';
    }
    i++;
    return t == '1';
  }

  while (i < tokens.length) {
    if (isCmd(tokens[i])) cmd = tokens[i++];
    final rel = cmd == cmd.toLowerCase();
    Offset pt(double x, double y) => rel ? cur + Offset(x, y) : Offset(x, y);
    switch (cmd.toUpperCase()) {
      case 'M':
        cur = pt(next(), next());
        path.moveTo(cur.dx, cur.dy);
        start = cur;
        // Further pairs are line-tos.
        cmd = rel ? 'l' : 'L';
      case 'L':
        cur = pt(next(), next());
        path.lineTo(cur.dx, cur.dy);
      case 'H':
        final x = next();
        cur = Offset(rel ? cur.dx + x : x, cur.dy);
        path.lineTo(cur.dx, cur.dy);
      case 'V':
        final y = next();
        cur = Offset(cur.dx, rel ? cur.dy + y : y);
        path.lineTo(cur.dx, cur.dy);
      case 'C':
        final c1 = pt(next(), next()), c2 = pt(next(), next()), e = pt(next(), next());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
        lastCtrl = c2;
        cur = e;
      case 'S':
        final c1 = 'CcSs'.contains(lastCmd) ? cur * 2 - lastCtrl : cur;
        final c2 = pt(next(), next()), e = pt(next(), next());
        path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, e.dx, e.dy);
        lastCtrl = c2;
        cur = e;
      case 'Q':
        final c1 = pt(next(), next()), e = pt(next(), next());
        path.quadraticBezierTo(c1.dx, c1.dy, e.dx, e.dy);
        lastCtrl = c1;
        cur = e;
      case 'T':
        final c1 = 'QqTt'.contains(lastCmd) ? cur * 2 - lastCtrl : cur;
        final e = pt(next(), next());
        path.quadraticBezierTo(c1.dx, c1.dy, e.dx, e.dy);
        lastCtrl = c1;
        cur = e;
      case 'A':
        final rx = next(), ry = next(), rot = next();
        final large = flag(), sweep = flag();
        final e = pt(next(), next());
        path.arcToPoint(e, radius: Radius.elliptical(rx, ry), rotation: rot, largeArc: large, clockwise: sweep);
        cur = e;
      case 'Z':
        path.close();
        cur = start;
    }
    lastCmd = cmd;
  }
  return path;
}
