/// PCB assembly drawing: every placement drawn as its part (chip resistor,
/// capacitor, SOT, IC ...) at its real size and rotation, with view mirror and
/// rotation. Designators appear inside the bodies once they are large enough
/// to read.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/footprints.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'check_view.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

/// Flat part colours (no gradients).
class PartPalette {
  static const resistor = Color(0xFF2FA36B);
  static const capacitor = Color(0xFFE8892B);
  static const inductor = Color(0xFF4A5566);
  static const diode = Color(0xFF2B2F35);
  static const led = Color(0xFFEDEFF2);
  static const transistor = Color(0xFF25292E);
  static const ic = Color(0xFF2F6FD6);
  static const crystal = Color(0xFFB9BFC7);
  static const connector = Color(0xFFD8CFBD);
  static const testPoint = Color(0xFFD4A84A);
  static const fiducial = Color(0xFFC98A4B);
  static const other = Color(0xFF8A929C);
  static const terminal = Color(0xFFCDD2D8);
  static const copper = Color(0xFFC0844A);

  static Color body(PartKind k) => switch (k) {
        PartKind.resistor => resistor,
        PartKind.capacitor => capacitor,
        PartKind.inductor => inductor,
        PartKind.diode => diode,
        PartKind.led => led,
        PartKind.transistor => transistor,
        PartKind.ic => ic,
        PartKind.crystal => crystal,
        PartKind.connector => connector,
        PartKind.testPoint => testPoint,
        PartKind.fiducial => fiducial,
        PartKind.other => other,
      };

  /// Text colour readable on the body colour.
  static Color label(Color body) => body.computeLuminance() > 0.45 ? const Color(0xFF15181C) : const Color(0xFFFFFFFF);
}

class _Part {
  _Part(this.p, this.merged, this.shape, this.side);

  final Placement p;
  final MergedRef? merged;
  final PartShape shape;
  final BoardSide side;
}

class BoardView extends StatefulWidget {
  const BoardView({super.key, required this.state});

  final AppState state;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  double _zoom = 1;
  Offset _pan = Offset.zero;
  int _fitSeen = 0;
  double _gestureZoom = 1;
  _Part? _hover;
  Offset _hoverPos = Offset.zero;

  void _fit() => setState(() {
        _zoom = 1;
        _pan = Offset.zero;
      });

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final state = widget.state;
    final coords = state.coords;
    if (coords == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(title: s.t('mod_board')),
        Expanded(
          child: EmptyState(
            icon: Ic.crosshair,
            text: s.t('board_empty'),
            action: FlatButton(label: s.t('btn_coord'), primary: true, onTap: () => importFile(context, state, InputKind.coords)),
          ),
        ),
      ]);
    }
    if (state.boardFitRequest != _fitSeen) {
      _fitSeen = state.boardFitRequest;
      _zoom = 1;
      _pan = Offset.zero;
    }
    final report = state.report;
    final merged = {for (final m in report?.merged ?? const <MergedRef>[]) m.ref: m};
    final highlight = <String>{
      ...?state.selected?.bomRefs.map((m) => m.ref),
      ...?state.selected?.smtRefs.map((m) => m.ref),
    };
    final all = [
      for (final p in coords.result.items)
        _Part(
          p,
          merged[p.ref],
          shapeOf(p.ref, footprint: p.footprint, description: '${merged[p.ref]?.description ?? ''} ${p.value}'),
          _sideOf(p, merged[p.ref]),
        ),
    ];
    final parts = all
        .where((e) => switch (state.boardSide) {
              BoardSideFilter.both => true,
              BoardSideFilter.top => e.side != BoardSide.bottom,
              BoardSideFilter.bottom => e.side != BoardSide.top,
            })
        .toList();
    final deg = state.boardQuarterTurns * 90;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: s.t('mod_board'),
          subtitle: s.t('page_board_sub', {'n': parts.length}),
          trailing: [
            Text(
              s.t('board_view_state', {'deg': deg, 'mirror': state.boardMirror ? s.t('board_mirrored') : ''}),
              style: TextStyle(fontSize: 12, color: c.textDim, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ],
        ),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            final view = _View.fit(all, size, state.boardQuarterTurns, state.boardMirror, _zoom, _pan);
            return Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  setState(() => _zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.18 : 1 / 1.18, size));
                }
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                onHover: (e) {
                  _Part? best;
                  var bestD = double.infinity;
                  for (final part in parts) {
                    final d = (view.toScreen(part.p.x, part.p.y) - e.localPosition).distance;
                    final reach = math.max(8.0, math.max(part.shape.width, part.shape.height) * view.scale / 2);
                    if (d < reach && d < bestD) {
                      bestD = d;
                      best = part;
                    }
                  }
                  if (best != _hover || best != null) {
                    setState(() {
                      _hover = best;
                      _hoverPos = e.localPosition;
                    });
                  }
                },
                onExit: (_) => setState(() => _hover = null),
                child: GestureDetector(
                  onScaleStart: (_) => _gestureZoom = _zoom,
                  onScaleUpdate: (d) => setState(() {
                    final center = Offset(size.width / 2, size.height / 2);
                    final newZoom = (_gestureZoom * d.scale).clamp(0.2, 200.0);
                    final f = newZoom / _zoom;
                    _pan = (d.localFocalPoint - center) * (1 - f) + _pan * f + d.focalPointDelta;
                    _zoom = newZoom;
                  }),
                  onDoubleTap: _fit,
                  child: ClipRect(
                    child: Stack(children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _AssemblyPainter(
                            all: all,
                            parts: parts,
                            view: view,
                            colors: c,
                            coloring: state.boardColoring,
                            checked: report != null,
                            highlight: highlight,
                            hover: _hover,
                            dimBottom: state.boardSide == BoardSideFilter.both,
                            showLabels: _zoom > 1.05,
                          ),
                        ),
                      ),
                      Positioned(left: 14, bottom: 14, child: _LegendCard(coloring: state.boardColoring, checked: report != null)),
                      if (_hover != null)
                        Positioned(
                          left: math.min(_hoverPos.dx + 16, size.width - 250),
                          top: math.min(_hoverPos.dy + 16, size.height - 120),
                          child: _HoverCard(part: _hover!),
                        ),
                    ]),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  void _zoomAt(Offset at, double factor, Size size) {
    final newZoom = (_zoom * factor).clamp(0.2, 200.0);
    final f = newZoom / _zoom;
    final center = Offset(size.width / 2, size.height / 2);
    _pan = (at - center) * (1 - f) + _pan * f;
    _zoom = newZoom;
  }

  BoardSide _sideOf(Placement p, MergedRef? m) {
    if (p.side != BoardSide.unknown) return p.side;
    if (m?.side == StationSide.a) return BoardSide.top;
    if (m?.side == StationSide.b) return BoardSide.bottom;
    return BoardSide.unknown;
  }
}

/// World (mm, Y up) → screen transform with view rotation and mirror.
class _View {
  _View(this.cx, this.cy, this.quarter, this.mirror, this.scale, this.origin);

  final double cx;
  final double cy;
  final int quarter;
  final bool mirror;

  /// Pixels per mm.
  final double scale;

  /// Screen position of the board centre.
  final Offset origin;

  /// Board point after mirror and rotation, still Y up, relative to centre.
  Offset _view(double x, double y) {
    var vx = x - cx;
    final vy = y - cy;
    if (mirror) vx = -vx;
    return switch (quarter % 4) {
      1 => Offset(-vy, vx),
      2 => Offset(-vx, -vy),
      3 => Offset(vy, -vx),
      _ => Offset(vx, vy),
    };
  }

  Offset toScreen(double x, double y) {
    final v = _view(x, y);
    return origin + Offset(v.dx * scale, -v.dy * scale);
  }

  /// Applies the linear part of the transform for a part rotated [rotDeg].
  void applyPart(Canvas canvas, Offset at, double rotDeg) {
    canvas.translate(at.dx, at.dy);
    canvas.scale(scale, -scale);
    canvas.rotate(quarter * math.pi / 2);
    if (mirror) canvas.scale(-1, 1);
    canvas.rotate(rotDeg * math.pi / 180);
  }

  /// On-screen direction of the part's X axis, in radians (screen, Y down).
  double screenAngle(double rotDeg) {
    final a = rotDeg * math.pi / 180;
    var x = math.cos(a);
    final y = math.sin(a);
    if (mirror) x = -x;
    final t = quarter * math.pi / 2;
    final rx = x * math.cos(t) - y * math.sin(t);
    final ry = x * math.sin(t) + y * math.cos(t);
    return math.atan2(-ry, rx);
  }

  /// Board extents including each part's body (half its longest side).
  static (double, double, double, double) extents(List<_Part> parts) {
    var minX = double.infinity, minY = double.infinity, maxX = -double.infinity, maxY = -double.infinity;
    for (final e in parts) {
      final r = math.max(e.shape.width, e.shape.height) / 2;
      minX = math.min(minX, e.p.x - r);
      minY = math.min(minY, e.p.y - r);
      maxX = math.max(maxX, e.p.x + r);
      maxY = math.max(maxY, e.p.y + r);
    }
    return (minX, minY, maxX, maxY);
  }

  static _View fit(List<_Part> parts, Size size, int quarter, bool mirror, double zoom, Offset pan) {
    if (parts.isEmpty) return _View(0, 0, quarter, mirror, 1, Offset(size.width / 2, size.height / 2));
    final (minX, minY, maxX, maxY) = extents(parts);
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    final odd = quarter.isOdd;
    final w = math.max((odd ? maxY - minY : maxX - minX) + 4, 2.0);
    final h = math.max((odd ? maxX - minX : maxY - minY) + 4, 2.0);
    const margin = 56.0;
    final base = math.max(math.min((size.width - 2 * margin) / w, (size.height - 2 * margin) / h), 0.01);
    return _View(cx, cy, quarter, mirror, base * zoom, Offset(size.width / 2, size.height / 2) + pan);
  }
}

class _AssemblyPainter extends CustomPainter {
  _AssemblyPainter({
    required this.all,
    required this.parts,
    required this.view,
    required this.colors,
    required this.coloring,
    required this.checked,
    required this.highlight,
    required this.hover,
    required this.dimBottom,
    required this.showLabels,
  });

  final List<_Part> all;
  final List<_Part> parts;
  final _View view;
  final AppColors colors;
  final BoardColoring coloring;
  final bool checked;
  final Set<String> highlight;
  final _Part? hover;
  final bool dimBottom;

  /// Designators are drawn only once the user zooms in.
  final bool showLabels;

  Color get _boardFill => colors.dark ? const Color(0xFF15211C) : const Color(0xFFF2F5F1);
  Color get _boardEdge => colors.dark ? const Color(0xFF2C4A3D) : const Color(0xFFBFCFC4);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.window);
    final dot = Paint()..color = colors.border.withValues(alpha: 0.7);
    for (var x = 12.0; x < size.width; x += 24) {
      for (var y = 12.0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 0.8, dot);
      }
    }
    if (all.isEmpty) return;

    // Board outline: extents of all placements plus a margin.
    final (minX, minY, maxX, maxY) = _View.extents(all);
    final board = Rect.fromPoints(view.toScreen(minX - 2, minY - 2), view.toScreen(maxX + 2, maxY + 2));
    final rr = RRect.fromRectAndRadius(board, Radius.circular(math.min(12, view.scale * 1.5)));
    canvas.drawRRect(rr, Paint()..color = _boardFill);
    canvas.drawRRect(
        rr,
        Paint()
          ..color = _boardEdge
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    final px = 1 / view.scale; // one screen pixel in mm
    for (final part in parts) {
      final at = view.toScreen(part.p.x, part.p.y);
      final r = math.max(part.shape.width, part.shape.height) * view.scale;
      if (at.dx < -r || at.dy < -r || at.dx > size.width + r || at.dy > size.height + r) continue;
      canvas.save();
      view.applyPart(canvas, at, part.p.rotation);
      final dim = dimBottom && part.side == BoardSide.bottom;
      if (dim) canvas.saveLayer(null, Paint()..color = const Color(0x8C000000));
      _drawPart(canvas, part, px);
      if (dim) canvas.restore();
      canvas.restore();
    }
    if (showLabels) _drawLabels(canvas, size);
  }

  /// Fill colour for a part in the current colouring mode, or null to draw
  /// it as an empty footprint (not placed / not in the BOM).
  Color? _fill(_Part part) {
    final m = part.merged;
    if (checked && m == null) return null;
    if (coloring == BoardColoring.status && checked) return colors.category(m!.category);
    return PartPalette.body(part.shape.kind);
  }

  void _drawPart(Canvas canvas, _Part part, double px) {
    final sh = part.shape;
    final w = sh.width, h = sh.height;
    final body = Rect.fromCenter(center: Offset.zero, width: w, height: h);
    final fill = _fill(part);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = px * 1.2;

    if (fill == null) {
      // Empty footprint: outline only.
      canvas.drawRect(body, stroke..color = colors.textFaint);
      return;
    }
    final terminal = Paint()..color = PartPalette.terminal;
    switch (sh.kind) {
      case PartKind.resistor:
      case PartKind.capacitor:
        final t = w * 0.2;
        canvas.drawRect(Rect.fromLTWH(-w / 2, -h / 2, t, h), terminal);
        canvas.drawRect(Rect.fromLTWH(w / 2 - t, -h / 2, t, h), terminal);
        canvas.drawRect(Rect.fromLTRB(-w / 2 + t, -h / 2, w / 2 - t, h / 2), Paint()..color = fill);
      case PartKind.inductor:
        final t = w * 0.18;
        canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(h * 0.12)), Paint()..color = fill);
        final cu = Paint()..color = PartPalette.copper;
        canvas.drawRect(Rect.fromLTWH(-w / 2, -h / 2, t, h), cu);
        canvas.drawRect(Rect.fromLTWH(w / 2 - t, -h / 2, t, h), cu);
      case PartKind.diode:
        canvas.drawRect(body, Paint()..color = fill);
        canvas.drawRect(Rect.fromLTWH(-w / 2 + w * 0.12, -h / 2, w * 0.12, h), terminal);
      case PartKind.led:
        canvas.drawRect(body, Paint()..color = fill);
        canvas.drawCircle(Offset.zero, h * 0.32, Paint()..color = colors.pass);
        canvas.drawRect(Rect.fromLTWH(-w / 2, -h / 2, w * 0.1, h), Paint()..color = colors.pass);
      case PartKind.transistor:
        final lw = math.min(0.4, w * 0.15), ll = h * 0.45;
        for (final x in [-w * 0.33, w * 0.33]) {
          canvas.drawRect(Rect.fromCenter(center: Offset(x, -h / 2 - ll / 2), width: lw, height: ll), terminal);
        }
        canvas.drawRect(Rect.fromCenter(center: Offset(0, h / 2 + ll / 2), width: lw, height: ll), terminal);
        canvas.drawRect(body, Paint()..color = fill);
      case PartKind.ic:
        if (sh.pins > 0 && !sh.bga) {
          final square = (w - h).abs() < 0.2;
          final pitch = w / (sh.pins + 1);
          final lw = math.min(pitch * 0.55, 0.45), ll = math.min(w, h) * 0.12;
          for (var i = 1; i <= sh.pins; i++) {
            final x = -w / 2 + pitch * i;
            canvas.drawRect(Rect.fromCenter(center: Offset(x, h / 2 + ll * 0.2), width: lw, height: ll), terminal);
            canvas.drawRect(Rect.fromCenter(center: Offset(x, -h / 2 - ll * 0.2), width: lw, height: ll), terminal);
            if (square) {
              final y = -h / 2 + (h / (sh.pins + 1)) * i;
              canvas.drawRect(Rect.fromCenter(center: Offset(w / 2 + ll * 0.2, y), width: ll, height: lw), terminal);
              canvas.drawRect(Rect.fromCenter(center: Offset(-w / 2 - ll * 0.2, y), width: ll, height: lw), terminal);
            }
          }
        }
        final small = math.min(w, h);
        canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(small * 0.04)), Paint()..color = fill);
        canvas.drawCircle(Offset(-w / 2 + small * 0.14, h / 2 - small * 0.14), small * 0.06,
            Paint()..color = PartPalette.label(fill).withValues(alpha: 0.6));
      case PartKind.crystal:
        canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(h * 0.18)), Paint()..color = fill);
        canvas.drawRRect(RRect.fromRectAndRadius(body.deflate(h * 0.12), Radius.circular(h * 0.12)), stroke..color = const Color(0xFF8E959E));
      case PartKind.connector:
        canvas.drawRect(body, Paint()..color = fill);
        final n = (w / 0.8).floor().clamp(2, 40);
        final pin = Paint()..color = const Color(0xFF3A3530);
        for (var i = 0; i < n; i++) {
          canvas.drawRect(Rect.fromCenter(center: Offset(-w / 2 + w * (i + 0.5) / n, 0), width: w / n * 0.4, height: h * 0.3), pin);
        }
      case PartKind.testPoint:
        if ((w - h).abs() < 0.05) {
          canvas.drawCircle(Offset.zero, w / 2, Paint()..color = fill);
          canvas.drawCircle(Offset.zero, w / 4, Paint()..color = _boardFill);
        } else {
          canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(h * 0.25)), Paint()..color = fill);
        }
      case PartKind.fiducial:
        canvas.drawCircle(Offset.zero, w * 0.9, stroke..color = PartPalette.copper.withValues(alpha: 0.6));
        canvas.drawCircle(Offset.zero, w / 2, Paint()..color = fill);
      case PartKind.other:
        canvas.drawRRect(RRect.fromRectAndRadius(body, Radius.circular(h * 0.1)), Paint()..color = fill);
    }

    // Status outline in part-type mode; selection and hover in both modes.
    final m = part.merged;
    Paint ring(Color c, double width) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = px * width;
    if (checked && m != null && coloring == BoardColoring.type && m.category != CheckCategory.pass) {
      canvas.drawRect(body.inflate(px * 2.5), ring(m.category == CheckCategory.ng ? colors.ng : colors.substitute, 2));
    }
    if (highlight.contains(part.p.ref)) canvas.drawRect(body.inflate(px * 5), ring(colors.accent, 2.2));
    if (identical(hover, part)) canvas.drawRect(body.inflate(px * 3.5), ring(colors.text, 1.2));
  }

  /// Designators inside bodies, along the body's long axis, kept upright.
  void _drawLabels(Canvas canvas, Size size) {
    for (final part in parts) {
      final sh = part.shape;
      final long = math.max(sh.width, sh.height) * view.scale;
      final short = math.min(sh.width, sh.height) * view.scale;
      if (short < 7) continue;
      final at = view.toScreen(part.p.x, part.p.y);
      if (at.dx < -long || at.dy < -long || at.dx > size.width + long || at.dy > size.height + long) continue;
      final fill = _fill(part);
      final color = fill == null ? colors.textDim : PartPalette.label(fill);
      // Measure at 10 px, then scale to fit inside the body.
      final probe = TextPainter(
        text: TextSpan(text: part.p.ref, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, fontFamily: uiFontFamily)),
        textDirection: TextDirection.ltr,
      )..layout();
      final font = math.min(short * 0.62, 10 * (long * 0.84) / probe.width);
      if (font < 6.5) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: part.p.ref,
          style: TextStyle(fontSize: math.min(font, 22), fontWeight: FontWeight.w700, color: color, fontFamily: uiFontFamily, height: 1),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var angle = view.screenAngle(part.p.rotation);
      if (sh.height > sh.width) angle += math.pi / 2;
      while (angle > math.pi / 2) {
        angle -= math.pi;
      }
      while (angle <= -math.pi / 2) {
        angle += math.pi;
      }
      canvas.save();
      canvas.translate(at.dx, at.dy);
      canvas.rotate(angle);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AssemblyPainter old) => true;
}

class _LegendCard extends StatelessWidget {
  const _LegendCard({required this.coloring, required this.checked});

  final BoardColoring coloring;
  final bool checked;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final items = coloring == BoardColoring.status && checked
        ? <(Color?, String)>[
            (c.pass, s.t('cat_pass')),
            (c.ng, s.t('cat_ng')),
            (c.substitute, s.t('cat_substitute')),
            (null, s.t('board_not_in_bom')),
          ]
        : <(Color?, String)>[
            (PartPalette.resistor, s.t('type_resistor')),
            (PartPalette.capacitor, s.t('type_capacitor')),
            (PartPalette.inductor, s.t('type_inductor')),
            (PartPalette.diode, s.t('type_diode')),
            (PartPalette.transistor, s.t('type_transistor')),
            (PartPalette.ic, s.t('type_ic')),
            (PartPalette.crystal, s.t('type_crystal')),
            (PartPalette.connector, s.t('type_connector')),
            (null, s.t('type_other')),
          ];
    return IgnorePointer(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: c.panel.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.border),
        ),
        child: Wrap(spacing: 14, runSpacing: 6, children: [
          for (final (color, label) in items)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 14,
                height: 8,
                decoration: BoxDecoration(
                  color: color,
                  border: Border.all(color: color == null ? c.textFaint : c.border),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              ),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 11.5, color: c.textDim)),
            ]),
          if (coloring == BoardColoring.type && checked)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(width: 14, height: 8, decoration: BoxDecoration(border: Border.all(color: c.ng, width: 1.5))),
              const SizedBox(width: 6),
              Text(s.t('cat_ng'), style: TextStyle(fontSize: 11.5, color: c.textDim)),
            ]),
        ]),
      ),
    );
  }
}

class _HoverCard extends StatelessWidget {
  const _HoverCard({required this.part});

  final _Part part;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final p = part.p;
    final m = part.merged;
    final style = TextStyle(fontSize: 12, color: c.textDim);
    return IgnorePointer(
      child: Container(
        width: 234,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: c.panel,
          border: Border.all(color: c.borderStrong),
          borderRadius: BorderRadius.circular(8),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 14, offset: Offset(0, 4))],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(p.ref, style: TextStyle(fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(width: 8),
            Text(part.side == BoardSide.bottom ? s.t('side_bottom') : s.t('side_top'), style: style),
          ]),
          const SizedBox(height: 3),
          Text('X ${p.x.toStringAsFixed(3)}  Y ${p.y.toStringAsFixed(3)}  ${p.rotation.toStringAsFixed(0)}°', style: style),
          if (m != null) Text('${s.t('col_pn')}: ${m.smtPartNo.isEmpty ? m.bomPartNo : m.smtPartNo}', style: style),
          if (m != null) Text(m.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: style),
          if (m == null && p.footprint.isNotEmpty) Text(p.footprint, style: style),
        ]),
      ),
    );
  }
}
