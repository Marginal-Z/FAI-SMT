/// Placement plot of the coordinate file, coloured by check result.
library;

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'icons.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'check_view.dart';
import 'theme.dart';
import 'widgets.dart';

class BoardView extends StatefulWidget {
  const BoardView({super.key, required this.state});

  final AppState state;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  double _zoom = 1;
  int _fitSeen = 0;
  Offset _pan = Offset.zero;
  Placement? _hover;
  double _gestureZoom = 1;
  Offset _hoverPos = Offset.zero;

  void _fit() => setState(() {
        _zoom = 1;
        _pan = Offset.zero;
      });


  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final coords = widget.state.coords;
    if (coords == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(title: s.t('mod_board')),
        Expanded(
          child: EmptyState(
            icon: Ic.crosshair,
            text: s.t('board_empty'),
            action: FlatButton(label: s.t('go_files'), onTap: () => widget.state.setModule(Module.files)),
          ),
        ),
      ]);
    }
    if (widget.state.boardFitRequest != _fitSeen) {
      _fitSeen = widget.state.boardFitRequest;
      _zoom = 1;
      _pan = Offset.zero;
    }
    final report = widget.state.report;
    final merged = {for (final m in report?.merged ?? const <MergedRef>[]) m.ref: m};
    final highlight = <String>{
      ...?widget.state.selected?.bomRefs.map((m) => m.ref),
      ...?widget.state.selected?.smtRefs.map((m) => m.ref),
    };
    final parts = coords.result.items.where((p) {
      final side = _effectiveSide(p, merged[p.ref]);
      return switch (widget.state.boardSide) {
        BoardSideFilter.both => true,
        BoardSideFilter.top => side != BoardSide.bottom,
        BoardSideFilter.bottom => side != BoardSide.top,
      };
    }).toList();

    Color colorOf(Placement p) {
      if (report == null) return c.textDim;
      final m = merged[p.ref];
      if (m == null) return c.textFaint;
      return c.category(m.category);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title: s.t('mod_board'), subtitle: s.t('page_board_sub', {'n': parts.length})),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            final xf = _Transform.fit(coords.result.items, size, _zoom, _pan);
            return Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent) {
                  setState(() {
                    final factor = e.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15;
                    final newZoom = (_zoom * factor).clamp(0.2, 80.0);
                    final f = newZoom / _zoom;
                    // Keep the point under the cursor fixed.
                    final center = Offset(size.width / 2, size.height / 2);
                    _pan = (e.localPosition - center) * (1 - f) + _pan * f;
                    _zoom = newZoom;
                  });
                }
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.grab,
                onHover: (e) {
                  Placement? best;
                  var bestD = 10.0;
                  for (final p in parts) {
                    final d = (xf.apply(p) - e.localPosition).distance;
                    if (d < bestD) {
                      bestD = d;
                      best = p;
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
                  // One handler for mouse drag, touch pan and pinch zoom.
                  onScaleStart: (_) => _gestureZoom = _zoom,
                  onScaleUpdate: (d) => setState(() {
                    final center = Offset(size.width / 2, size.height / 2);
                    final newZoom = (_gestureZoom * d.scale).clamp(0.2, 80.0);
                    final f = newZoom / _zoom;
                    _pan = (d.localFocalPoint - center) * (1 - f) + _pan * f + d.focalPointDelta;
                    _zoom = newZoom;
                  }),
                  onDoubleTap: _fit,
                  child: ClipRect(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _BoardPainter(
                              parts: parts,
                              xf: xf,
                              colorOf: colorOf,
                              highlight: highlight,
                              colors: c,
                              hover: _hover,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 14,
                          bottom: 14,
                          child: IgnorePointer(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: c.panel.withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: c.border),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                if (report == null)
                                  _Legend(color: c.textDim, label: s.t('board_unchecked'))
                                else ...[
                                  _Legend(color: c.pass, label: s.t('cat_pass')),
                                  _Legend(color: c.ng, label: s.t('cat_ng')),
                                  _Legend(color: c.substitute, label: s.t('cat_substitute')),
                                  _Legend(color: c.textFaint, label: s.t('board_not_in_bom')),
                                ],
                              ]),
                            ),
                          ),
                        ),
                        if (_hover != null)
                          Positioned(
                            left: math.min(_hoverPos.dx + 14, size.width - 230),
                            top: math.min(_hoverPos.dy + 14, size.height - 90),
                            child: _HoverCard(p: _hover!, m: merged[_hover!.ref]),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
      ],
    );
  }

  BoardSide _effectiveSide(Placement p, MergedRef? m) {
    if (p.side != BoardSide.unknown) return p.side;
    if (m?.side == StationSide.a) return BoardSide.top;
    if (m?.side == StationSide.b) return BoardSide.bottom;
    return BoardSide.unknown;
  }
}

class _Transform {
  _Transform(this.scale, this.origin, this.minX, this.maxY);

  final double scale;
  final Offset origin;
  final double minX;
  final double maxY;

  /// CAD Y grows upward; screen Y grows downward.
  Offset apply(Placement p) => origin + Offset((p.x - minX) * scale, (maxY - p.y) * scale);

  Rect boardRect(List<Placement> all) {
    if (all.isEmpty) return Rect.zero;
    final xs = all.map((p) => p.x);
    final ys = all.map((p) => p.y);
    final a = origin + Offset((xs.reduce(math.min) - minX) * scale, (maxY - ys.reduce(math.max)) * scale);
    final b = origin + Offset((xs.reduce(math.max) - minX) * scale, (maxY - ys.reduce(math.min)) * scale);
    return Rect.fromPoints(a, b).inflate(10);
  }

  static _Transform fit(List<Placement> all, Size size, double zoom, Offset pan) {
    if (all.isEmpty) return _Transform(1, Offset.zero, 0, 0);
    final minX = all.map((p) => p.x).reduce(math.min);
    final maxX = all.map((p) => p.x).reduce(math.max);
    final minY = all.map((p) => p.y).reduce(math.min);
    final maxY = all.map((p) => p.y).reduce(math.max);
    final w = math.max(maxX - minX, 1.0);
    final h = math.max(maxY - minY, 1.0);
    const margin = 64.0;
    final base = math.min((size.width - 2 * margin) / w, (size.height - 2 * margin) / h);
    final scale = math.max(base, 0.01) * zoom;
    final contentSize = Size(w * scale, h * scale);
    final origin = Offset((size.width - contentSize.width) / 2, (size.height - contentSize.height) / 2) + pan;
    return _Transform(scale, origin, minX, maxY);
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({required this.parts, required this.xf, required this.colorOf, required this.highlight, required this.colors, this.hover});

  final List<Placement> parts;
  final _Transform xf;
  final Color Function(Placement) colorOf;
  final Set<String> highlight;
  final AppColors colors;
  final Placement? hover;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.window);
    // Grid
    final grid = Paint()
      ..color = colors.border.withValues(alpha: 0.5)
      ..strokeWidth = 1;
    const step = 40.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    if (parts.isEmpty) return;
    // Board outline from placement extents
    final board = xf.boardRect(parts);
    canvas.drawRect(board, Paint()..color = colors.panel);
    canvas.drawRect(
        board,
        Paint()
          ..color = colors.borderStrong
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);

    final r = (2.5 * math.sqrt(xf.scale)).clamp(2.5, 7.0);
    for (final p in parts) {
      final o = xf.apply(p);
      final col = colorOf(p);
      final rect = Rect.fromCenter(center: o, width: r * 2, height: r * 2);
      canvas.save();
      canvas.translate(o.dx, o.dy);
      canvas.rotate(-p.rotation * math.pi / 180);
      canvas.translate(-o.dx, -o.dy);
      canvas.drawRect(rect, Paint()..color = col.withValues(alpha: 0.85));
      canvas.drawLine(o, Offset(o.dx + r, o.dy), Paint()
        ..color = colors.window
        ..strokeWidth = 1);
      canvas.restore();
      if (highlight.contains(p.ref)) {
        canvas.drawCircle(
            o,
            r + 5,
            Paint()
              ..color = colors.accent
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
    }
    if (xf.scale > 16) {
      for (final p in parts) {
        final tp = TextPainter(
          text: TextSpan(text: p.ref, style: TextStyle(fontSize: 10, color: colors.textDim, fontFamily: uiFontFamily)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, xf.apply(p) + Offset(r + 3, -tp.height / 2));
      }
    }
    if (hover != null) {
      canvas.drawCircle(
          xf.apply(hover!),
          r + 4,
          Paint()
            ..color = colors.text
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5);
    }
  }

  @override
  bool shouldRepaint(_BoardPainter old) => true;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Row(children: [
          Container(width: 9, height: 9, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, color: AppTheme.of(context).textDim)),
        ]),
      );
}

class _HoverCard extends StatelessWidget {
  const _HoverCard({required this.p, required this.m});

  final Placement p;
  final MergedRef? m;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final style = TextStyle(fontSize: 12, color: c.textDim);
    return IgnorePointer(
      child: Container(
        width: 216,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: c.panel, border: Border.all(color: c.borderStrong), borderRadius: BorderRadius.circular(3)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(p.ref, style: const TextStyle(fontWeight: FontWeight.w700)),
            Text('X ${p.x.toStringAsFixed(3)}  Y ${p.y.toStringAsFixed(3)}  R ${p.rotation}', style: style),
            if (m != null) Text('${s.t('col_pn')}: ${m!.smtPartNo.isEmpty ? m!.bomPartNo : m!.smtPartNo}', style: style),
            if (m != null) Text(m!.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: style),
          ],
        ),
      ),
    );
  }
}
