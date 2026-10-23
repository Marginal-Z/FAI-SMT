/// PCB assembly drawing: every placement drawn as its part (chip resistor,
/// capacitor, SOT, IC ...) at its real size and rotation, with view mirror and
/// rotation. Designators appear inside the bodies once they are large enough
/// to read.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/board_layout.dart';
import '../core/footprints.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'check_view.dart';
import 'glyphs.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

/// Part colours for the navigator: refined flat defaults (no gradients),
/// overridable per part type in Settings.
class PartPalette {
  PartPalette(this.style);

  final BoardStyle style;

  static const defaults = {
    PartKind.resistor: Color(0xFF2E9E6A),
    PartKind.capacitor: Color(0xFFD98A3D),
    PartKind.inductor: Color(0xFF5B6575),
    PartKind.diode: Color(0xFF3B4048),
    PartKind.led: Color(0xFFE9EBEE),
    PartKind.transistor: Color(0xFF2F343B),
    PartKind.ic: Color(0xFF3D78D8),
    PartKind.crystal: Color(0xFFB4BAC2),
    PartKind.connector: Color(0xFFCDC4B1),
    PartKind.testPoint: Color(0xFFB59D6B),
    PartKind.fiducial: Color(0xFFBF8A57),
    PartKind.other: Color(0xFF98A0A9),
  };

  static const terminal = Color(0xFFCDD2D8);
  static const copper = Color(0xFFC0844A);

  static const backgrounds = {BoardBackground.green: Color(0xFF1E5E3B), BoardBackground.black: Color(0xFF16181B)};

  Color body(PartKind k) {
    final o = style.partColors[k.name];
    return o != null ? Color(o) : defaults[k]!;
  }

  /// Board fill, or null to follow the canvas (outline only).
  Color? get board => switch (style.background) {
    BoardBackground.canvas => null,
    BoardBackground.custom => Color(style.customBackground),
    final b => backgrounds[b],
  };

  /// Text colour readable on the body colour.
  static Color label(Color body) => body.computeLuminance() > 0.45 ? const Color(0xFF15181C) : const Color(0xFFFFFFFF);
}

class _Part {
  _Part(this.p, this.merged, this.shape, this.side);

  final Placement p;
  final MergedRef? merged;

  /// Body after fitting against its neighbours.
  final PartShape shape;
  final BoardSide side;

  /// Designator width at 10 px, and the last laid-out label.
  double? probeWidth;
  TextPainter? label;
  double labelFont = 0;
  Color? labelColor;
}

/// Parts with fitted bodies in drawing order (bottom side first; on each side
/// unplaced footprints, then larger before smaller), built once per
/// coordinate file and check result instead of on every frame.
class _BoardModel {
  _BoardModel(this.parts) : extents = _View.extents(parts);

  final List<_Part> parts;
  final (double, double, double, double) extents;

  factory _BoardModel.build(List<Placement> items, Map<String, MergedRef> merged, BoardSide Function(Placement, MergedRef?) sideOf) {
    final raw = [
      for (final p in items)
        (
          p,
          merged[p.ref],
          shapeOf(p.ref, footprint: p.footprint, description: '${merged[p.ref]?.description ?? p.description} ${p.value}'),
          sideOf(p, merged[p.ref]),
        ),
    ];
    final fit = fitBodies([
      for (final (p, _, shape, side) in raw)
        BodyBox(x: p.x, y: p.y, rotation: p.rotation, width: shape.width, height: shape.height, side: side.index, exact: shape.exact),
    ]);
    final parts = [for (var i = 0; i < raw.length; i++) _Part(raw[i].$1, raw[i].$2, raw[i].$3.scaled(fit[i].$1, fit[i].$2), raw[i].$4)];
    int rank(_Part e) => (e.side == BoardSide.bottom ? 0 : 2) + (e.merged == null ? 0 : 1);
    parts.sort((a, b) {
      final r = rank(a) - rank(b);
      if (r != 0) return r;
      return (b.shape.width * b.shape.height).compareTo(a.shape.width * a.shape.height);
    });
    return _BoardModel(parts);
  }
}

/// Zoom and pan; changes repaint the drawing without rebuilding the page.
class _Camera {
  const _Camera(this.zoom, this.pan);

  final double zoom;
  final Offset pan;
}

class BoardView extends StatefulWidget {
  const BoardView({super.key, required this.state, this.immersive = false});

  final AppState state;

  /// Full-screen mode: no page header, floating controls instead.
  final bool immersive;

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  final _cam = ValueNotifier(const _Camera(1, Offset.zero));
  final _hover = ValueNotifier<(_Part, Offset)?>(null);
  int _fitSeen = 0;
  double _gestureZoom = 1;

  _BoardModel? _model;
  Object? _modelCoords;
  Object? _modelReport;

  @override
  void initState() {
    super.initState();
    if (widget.immersive && Platform.isAndroid) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    if (widget.immersive && Platform.isAndroid) SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _cam.dispose();
    _hover.dispose();
    super.dispose();
  }

  void _fit() => _cam.value = const _Camera(1, Offset.zero);

  _BoardModel _modelFor(LoadedFile<Placement> coords, CheckReport? report) {
    if (_model == null || !identical(_modelCoords, coords) || !identical(_modelReport, report)) {
      final merged = {for (final m in report?.merged ?? const <MergedRef>[]) m.ref: m};
      _model = _BoardModel.build(coords.result.items, merged, _sideOf);
      _modelCoords = coords;
      _modelReport = report;
      _hover.value = null;
    }
    return _model!;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final state = widget.state;
    final fromFile = state.boardSource == BoardSource.file && state.boardFile != null;
    final coords = fromFile ? state.boardFile : state.coords;
    if (coords == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(title: s.t('mod_board')),
          Expanded(
            child: EmptyState(
              icon: Ic.crosshair,
              text: s.t('board_empty_any'),
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FlatButton(label: s.t('btn_coord'), primary: true, onTap: () => importFile(context, state, InputKind.coords)),
                  const SizedBox(width: 10),
                  FlatButton(label: s.t('btn_open_cad'), onTap: () => importFile(context, state, InputKind.boardCad)),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (state.boardFitRequest != _fitSeen) {
      _fitSeen = state.boardFitRequest;
      _fit();
    }
    final report = fromFile ? null : state.report;
    final model = _modelFor(coords, report);
    final highlight = <String>{...?state.selected?.bomRefs.map((m) => m.ref), ...?state.selected?.smtRefs.map((m) => m.ref)};
    final parts = model.parts
        .where(
          (e) => switch (state.boardSide) {
            BoardSideFilter.both => true,
            BoardSideFilter.top => e.side != BoardSide.bottom,
            BoardSideFilter.bottom => e.side != BoardSide.top,
          },
        )
        .toList();
    final deg = state.boardQuarterTurns * 90;
    final palette = PartPalette(state.settings.board);

    final source = fromFile ? s.t('board_source_file', {'name': coords.name}) : s.t('board_source_check');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.immersive)
          PageHeader(
            title: s.t('mod_board'),
            subtitle: '$source  ·  ${s.t('page_board_sub', {'n': parts.length})}',
            trailing: [
              Text(
                s.t('board_view_state', {'deg': deg, 'mirror': state.boardMirror ? s.t('board_mirrored') : ''}),
                style: TextStyle(fontSize: 12, color: c.textDim, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ],
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final size = Size(box.maxWidth, box.maxHeight);
              _View view() => _View.fit(model.extents, size, state.boardQuarterTurns, state.boardMirror, _cam.value.zoom, _cam.value.pan);
              return Listener(
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) _zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.18 : 1 / 1.18, size);
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  onHover: (e) {
                    final v = view();
                    _Part? best;
                    var bestD = double.infinity;
                    for (final part in parts) {
                      final d = (v.toScreen(part.p.x, part.p.y) - e.localPosition).distance;
                      final reach = math.max(6.0, math.max(part.shape.width, part.shape.height) * v.scale / 2);
                      // Ties go to the later (upper) part.
                      if (d < reach && d <= bestD) {
                        bestD = d;
                        best = part;
                      }
                    }
                    _hover.value = best == null ? null : (best, e.localPosition);
                  },
                  onExit: (_) => _hover.value = null,
                  child: GestureDetector(
                    onScaleStart: (_) => _gestureZoom = _cam.value.zoom,
                    onScaleUpdate: (d) {
                      final cam = _cam.value;
                      final center = Offset(size.width / 2, size.height / 2);
                      final newZoom = (_gestureZoom * d.scale).clamp(0.2, 200.0);
                      final f = newZoom / cam.zoom;
                      _cam.value = _Camera(newZoom, (d.localFocalPoint - center) * (1 - f) + cam.pan * f + d.focalPointDelta);
                    },
                    onDoubleTap: _fit,
                    child: ClipRect(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: RepaintBoundary(
                              child: CustomPaint(
                                isComplex: true,
                                painter: _AssemblyPainter(
                                  model: model,
                                  parts: parts,
                                  cam: _cam,
                                  hover: _hover,
                                  quarter: state.boardQuarterTurns,
                                  mirror: state.boardMirror,
                                  colors: c,
                                  coloring: state.boardColoring,
                                  checked: report != null,
                                  highlight: highlight,
                                  dimBottom: state.boardSide == BoardSideFilter.both,
                                  depth: state.settings.board.depth,
                                  palette: palette,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 14,
                            bottom: 14,
                            child: _LegendCard(coloring: state.boardColoring, checked: report != null, palette: palette),
                          ),
                          if (widget.immersive) Positioned(top: 14, right: 14, child: _FloatingControls(state: state)),
                          ValueListenableBuilder(
                            valueListenable: _hover,
                            builder: (context, hover, _) => hover == null
                                ? const SizedBox.shrink()
                                : Positioned(
                                    left: math.min(hover.$2.dx + 16, size.width - 250),
                                    top: math.min(hover.$2.dy + 16, size.height - 120),
                                    child: _HoverCard(part: hover.$1),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _zoomAt(Offset at, double factor, Size size) {
    final cam = _cam.value;
    final newZoom = (cam.zoom * factor).clamp(0.2, 200.0);
    final f = newZoom / cam.zoom;
    final center = Offset(size.width / 2, size.height / 2);
    _cam.value = _Camera(newZoom, (at - center) * (1 - f) + cam.pan * f);
  }

  static BoardSide _sideOf(Placement p, MergedRef? m) {
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

  /// Screen position of a point given in part coordinates (mm), matching
  /// [applyPart].
  Offset partPoint(Offset at, double rotDeg, double lx, double ly) {
    final a = rotDeg * math.pi / 180;
    var x = lx * math.cos(a) - ly * math.sin(a);
    final y = lx * math.sin(a) + ly * math.cos(a);
    if (mirror) x = -x;
    final t = quarter * math.pi / 2;
    return at + Offset((x * math.cos(t) - y * math.sin(t)) * scale, -(x * math.sin(t) + y * math.cos(t)) * scale);
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

  static _View fit((double, double, double, double) ext, Size size, int quarter, bool mirror, double zoom, Offset pan) {
    final (minX, minY, maxX, maxY) = ext;
    if (!minX.isFinite) return _View(0, 0, quarter, mirror, 1, Offset(size.width / 2, size.height / 2));
    final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
    final odd = quarter.isOdd;
    final w = math.max((odd ? maxY - minY : maxX - minX) + 4, 2.0);
    final h = math.max((odd ? maxX - minX : maxY - minY) + 4, 2.0);
    const margin = 56.0;
    final base = math.max(math.min((size.width - 2 * margin) / w, (size.height - 2 * margin) / h), 0.01);
    return _View(cx, cy, quarter, mirror, base * zoom, Offset(size.width / 2, size.height / 2) + pan);
  }
}

/// Convex hull (monotone chain) of a few points.
List<Offset> _hull(List<Offset> pts) {
  final p = [...pts]..sort((a, b) => a.dx != b.dx ? a.dx.compareTo(b.dx) : a.dy.compareTo(b.dy));
  double cross(Offset o, Offset a, Offset b) => (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
  final lower = <Offset>[], upper = <Offset>[];
  for (final q in p) {
    while (lower.length >= 2 && cross(lower[lower.length - 2], lower.last, q) <= 0) {
      lower.removeLast();
    }
    lower.add(q);
  }
  for (final q in p.reversed) {
    while (upper.length >= 2 && cross(upper[upper.length - 2], upper.last, q) <= 0) {
      upper.removeLast();
    }
    upper.add(q);
  }
  return [...lower..removeLast(), ...upper..removeLast()];
}

class _AssemblyPainter extends CustomPainter {
  _AssemblyPainter({
    required this.model,
    required this.parts,
    required this.cam,
    required this.hover,
    required this.quarter,
    required this.mirror,
    required this.colors,
    required this.coloring,
    required this.checked,
    required this.highlight,
    required this.dimBottom,
    required this.depth,
    required this.palette,
  }) : super(repaint: Listenable.merge([cam, hover]));

  final _BoardModel model;
  final List<_Part> parts;
  final ValueNotifier<_Camera> cam;
  final ValueNotifier<(_Part, Offset)?> hover;
  final int quarter;
  final bool mirror;
  final PartPalette palette;
  final AppColors colors;
  final BoardColoring coloring;
  final bool checked;
  final Set<String> highlight;
  final bool dimBottom;

  /// Raised parts with walls and shadows instead of flat footprints.
  final bool depth;

  /// Screen direction of a part's top face (up and a little right) and of
  /// its shadow (down-right), per mm of body height.
  static const _lift = Offset(0.2, -0.5);
  static const _shadow = Offset(0.45, 0.4);

  // Canvas dot grid, rebuilt only when the size changes.
  static Float32List? _dots;
  static Size? _dotsSize;

  Color get _boardFill => palette.board ?? colors.window;
  Color get _boardEdge => palette.board == null
      ? colors.borderStrong
      : Color.lerp(palette.board, palette.board!.computeLuminance() > 0.3 ? const Color(0xFF000000) : const Color(0xFFFFFFFF), 0.25)!;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = colors.window);
    if (_dotsSize != size) {
      _dotsSize = size;
      _dots = Float32List.fromList([
        for (var x = 12.0; x < size.width; x += 24)
          for (var y = 12.0; y < size.height; y += 24) ...[x, y],
      ]);
    }
    canvas.drawRawPoints(
      PointMode.points,
      _dots!,
      Paint()
        ..color = colors.border.withValues(alpha: 0.7)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    if (model.parts.isEmpty) return;
    final view = _View.fit(model.extents, size, quarter, mirror, cam.value.zoom, cam.value.pan);

    // Board outline: extents of all placements plus a margin.
    final (minX, minY, maxX, maxY) = model.extents;
    final board = Rect.fromPoints(view.toScreen(minX - 2, minY - 2), view.toScreen(maxX + 2, maxY + 2));
    final rr = RRect.fromRectAndRadius(board, Radius.circular(math.min(12, view.scale * 1.5)));
    canvas.drawRRect(rr, Paint()..color = _boardFill);
    canvas.drawRRect(
      rr,
      Paint()
        ..color = _boardEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // Visible parts with their screen centres, in drawing order.
    final visible = <(_Part, Offset)>[];
    for (final part in parts) {
      final at = view.toScreen(part.p.x, part.p.y);
      final r = math.max(part.shape.width, part.shape.height) * view.scale + 40;
      if (at.dx < -r || at.dy < -r || at.dx > size.width + r || at.dy > size.height + r) continue;
      visible.add((part, at));
    }
    final px = 1 / view.scale; // one screen pixel in mm
    final bottom = visible.where((e) => e.$1.side == BoardSide.bottom).toList();
    final top = visible.where((e) => e.$1.side != BoardSide.bottom).toList();
    // Screen bounds of filled bodies in drawing order, for label occlusion.
    final drawn = <(_Part, Rect)>[];
    for (final (group, dim) in [(bottom, dimBottom), (top, false)]) {
      if (group.isEmpty) continue;
      if (depth) {
        // Nearer (lower on screen) parts are drawn last so their raised tops
        // cover what lies behind them.
        group.sort((a, b) => (a.$2.dy - a.$2.dx * 0.4).compareTo(b.$2.dy - b.$2.dx * 0.4));
      }
      if (dim) canvas.saveLayer(Offset.zero & size, Paint()..color = const Color(0x8C000000));
      if (depth) {
        for (final (part, at) in group) {
          _drawShadow(canvas, part, at, view);
        }
      }
      for (final (part, at) in group) {
        var face = at;
        final fill = _fill(part);
        if (depth && fill != null) face = _drawWalls(canvas, part, at, view, fill);
        canvas.save();
        view.applyPart(canvas, face, part.p.rotation);
        _drawPart(canvas, part, px, fill);
        canvas.restore();
        if (fill != null) {
          final pts = [..._corners(part, at, view), if (face != at) ..._corners(part, face, view)];
          drawn.add((
            part,
            Rect.fromPoints(
              pts.reduce((a, b) => Offset(math.min(a.dx, b.dx), math.min(a.dy, b.dy))),
              pts.reduce((a, b) => Offset(math.max(a.dx, b.dx), math.max(a.dy, b.dy))),
            ),
          ));
        }
      }
      if (dim) canvas.restore();
    }
    if (cam.value.zoom > 1.05) _drawLabels(canvas, size, view, visible, drawn);
  }

  double _liftPx(_Part part, _View view) => part.shape.bodyHeight * view.scale;

  List<Offset> _corners(_Part part, Offset at, _View view) {
    final w = part.shape.width / 2, h = part.shape.height / 2;
    return [
      for (final (x, y) in [(-w, -h), (w, -h), (w, h), (-w, h)]) view.partPoint(at, part.p.rotation, x, y),
    ];
  }

  Path _poly(List<Offset> pts) => Path()..addPolygon(pts, true);

  void _drawShadow(Canvas canvas, _Part part, Offset at, _View view) {
    final lift = _liftPx(part, view);
    if (lift <= 0 || _fill(part) == null) return;
    final base = _corners(part, at, view);
    final off = _shadow * lift;
    canvas.drawPath(_poly(_hull([...base, for (final p in base) p + off])), Paint()..color = Color.fromRGBO(0, 0, 0, colors.dark ? 0.42 : 0.2));
  }

  /// Side walls of a raised body; returns the screen centre of its top face.
  Offset _drawWalls(Canvas canvas, _Part part, Offset at, _View view, Color fill) {
    final lift = _liftPx(part, view);
    if (lift <= 0) return at;
    final off = _lift * lift;
    final base = _corners(part, at, view);
    final wall = Color.lerp(fill, const Color(0xFF000000), 0.38)!;
    canvas.drawPath(_poly(_hull([...base, for (final p in base) p + off])), Paint()..color = wall);
    return at + off;
  }

  /// Fill colour for a part in the current colouring mode, or null to draw
  /// it as an empty footprint (not placed / not in the BOM).
  Color? _fill(_Part part) {
    final m = part.merged;
    if (checked && m == null) return null;
    if (coloring == BoardColoring.status && checked) return colors.category(m!.category);
    return palette.body(part.shape.kind);
  }

  void _drawPart(Canvas canvas, _Part part, double px, Color? fill) {
    final sh = part.shape;
    final w = sh.width, h = sh.height;
    final body = Rect.fromCenter(center: Offset.zero, width: w, height: h);
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
        canvas.drawCircle(Offset(-w / 2 + small * 0.14, h / 2 - small * 0.14), small * 0.06, Paint()..color = PartPalette.label(fill).withValues(alpha: 0.6));
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

    // Lit top edge of a raised body.
    if (depth && sh.bodyHeight > 0) {
      canvas.drawRect(
        body.deflate(px * 0.6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = px * 1.2
          ..color = Color.lerp(fill, const Color(0xFFFFFFFF), 0.28)!.withValues(alpha: 0.7),
      );
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
    if (identical(hover.value?.$1, part)) canvas.drawRect(body.inflate(px * 3.5), ring(colors.text, 1.2));
  }

  /// Designators inside bodies, along the body's long axis, kept upright.
  /// Top-side and placed parts come first; a label that would cover one
  /// already drawn, or sits under a body drawn above its own part, is left out.
  void _drawLabels(Canvas canvas, Size size, _View view, List<(_Part, Offset)> visible, List<(_Part, Rect)> drawn) {
    final drawIndex = {for (var i = 0; i < drawn.length; i++) drawn[i].$1: i};
    final order = [...visible]
      ..sort((a, b) {
        int rank(_Part e) => (e.side == BoardSide.bottom ? 0 : 2) + (e.merged == null ? 0 : 1);
        final r = rank(b.$1) - rank(a.$1);
        if (r != 0) return r;
        return (b.$1.shape.width * b.$1.shape.height).compareTo(a.$1.shape.width * a.$1.shape.height);
      });
    final placed = <Rect>[];
    for (final (part, at) in order) {
      final sh = part.shape;
      final long = math.max(sh.width, sh.height) * view.scale;
      final short = math.min(sh.width, sh.height) * view.scale;
      if (short < 7) continue;
      final fill = _fill(part);
      final color = fill == null ? colors.textDim : PartPalette.label(fill);
      // Width at 10 px, measured once, then scaled to fit inside the body.
      final probe = part.probeWidth ??= (TextPainter(
        text: TextSpan(
          text: part.p.ref,
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, fontFamily: uiFontFamily),
        ),
        textDirection: TextDirection.ltr,
      )..layout()).width;
      final font = math.min(math.min(short * 0.62, 10 * (long * 0.84) / probe), 22.0);
      if (font < 6.5) continue;
      final rounded = (font * 2).round() / 2;
      if (part.label == null || part.labelFont != rounded || part.labelColor != color) {
        part.label = TextPainter(
          text: TextSpan(
            text: part.p.ref,
            style: TextStyle(fontSize: rounded, fontWeight: FontWeight.w700, color: color, fontFamily: uiFontFamily, height: 1),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        part.labelFont = rounded;
        part.labelColor = color;
      }
      final tp = part.label!;
      var angle = view.screenAngle(part.p.rotation);
      if (sh.height > sh.width) angle += math.pi / 2;
      while (angle > math.pi / 2) {
        angle -= math.pi;
      }
      while (angle <= -math.pi / 2) {
        angle += math.pi;
      }
      final centre = depth && fill != null ? at + _lift * _liftPx(part, view) : at;
      final ca = math.cos(angle).abs(), sa = math.sin(angle).abs();
      final box = Rect.fromCenter(center: centre, width: tp.width * ca + tp.height * sa, height: tp.width * sa + tp.height * ca);
      if (placed.any((r) => r.overlaps(box.deflate(1)))) continue;
      final own = drawIndex[part] ?? -1;
      final inner = box.deflate(2);
      var covered = false;
      for (var k = own + 1; k < drawn.length && !covered; k++) {
        final other = drawn[k].$2;
        // Covered when a later body hides a good part of the label.
        if (other.overlaps(inner)) covered = other.intersect(inner).width * other.intersect(inner).height > inner.width * inner.height * 0.25;
      }
      if (covered) continue;
      placed.add(box);
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(angle);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AssemblyPainter old) => true;
}

class _LegendCard extends StatelessWidget {
  const _LegendCard({required this.coloring, required this.checked, required this.palette});

  final BoardColoring coloring;
  final bool checked;
  final PartPalette palette;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final items = coloring == BoardColoring.status && checked
        ? <(Color?, String)>[(c.pass, s.t('cat_pass')), (c.ng, s.t('cat_ng')), (c.substitute, s.t('cat_substitute')), (null, s.t('board_not_in_bom'))]
        : <(Color?, String)>[
            for (final (k, key) in [
              (PartKind.resistor, 'type_resistor'),
              (PartKind.capacitor, 'type_capacitor'),
              (PartKind.inductor, 'type_inductor'),
              (PartKind.diode, 'type_diode'),
              (PartKind.transistor, 'type_transistor'),
              (PartKind.ic, 'type_ic'),
              (PartKind.crystal, 'type_crystal'),
              (PartKind.connector, 'type_connector'),
            ])
              (palette.body(k), s.t(key)),
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
        child: Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            for (final (color, label) in items)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                ],
              ),
            if (coloring == BoardColoring.type && checked)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 14,
                    height: 8,
                    decoration: BoxDecoration(border: Border.all(color: c.ng, width: 1.5)),
                  ),
                  const SizedBox(width: 6),
                  Text(s.t('cat_ng'), style: TextStyle(fontSize: 11.5, color: c.textDim)),
                ],
              ),
          ],
        ),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  p.ref,
                  style: TextStyle(fontWeight: FontWeight.w700, color: c.text),
                ),
                const SizedBox(width: 8),
                Text(part.side == BoardSide.bottom ? s.t('side_bottom') : s.t('side_top'), style: style),
              ],
            ),
            const SizedBox(height: 3),
            Text('X ${p.x.toStringAsFixed(3)}  Y ${p.y.toStringAsFixed(3)}  ${p.rotation.toStringAsFixed(0)}°', style: style),
            if (m != null) Text('${s.t('col_pn')}: ${m.smtPartNo.isEmpty ? m.bomPartNo : m.smtPartNo}', style: style),
            if (m != null) Text(m.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: style),
            if (m == null && p.partNo.isNotEmpty) Text('${s.t('col_pn')}: ${p.partNo}', style: style),
            if (m == null && p.description.isNotEmpty) Text(p.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: style),
            if (m == null && p.footprint.isNotEmpty) Text(p.footprint, style: style),
          ],
        ),
      ),
    );
  }
}

/// Controls floating over the full-screen view.
class _FloatingControls extends StatelessWidget {
  const _FloatingControls({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    Widget button(Glyph g, String tip, VoidCallback onTap, {bool active = false}) => Hoverable(
      onTap: onTap,
      tooltip: tip,
      builder: (context, hover, _) => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? c.accent.withValues(alpha: 0.16)
              : hover
              ? c.hover
              : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: GlyphIcon(g, size: 20, color: active ? c.accent : c.text),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.panel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          button(Glyph.layersBoth, s.t('side_both'), () => state.setBoardSide(BoardSideFilter.both), active: state.boardSide == BoardSideFilter.both),
          button(Glyph.layerTop, s.t('side_top'), () => state.setBoardSide(BoardSideFilter.top), active: state.boardSide == BoardSideFilter.top),
          button(Glyph.layerBottom, s.t('side_bottom'), () => state.setBoardSide(BoardSideFilter.bottom), active: state.boardSide == BoardSideFilter.bottom),
          Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 4), color: c.border),
          button(Glyph.mirror, s.t('board_mirror'), state.toggleBoardMirror, active: state.boardMirror),
          button(Glyph.rotateLeft, s.t('board_rotate_left'), () => state.rotateBoard(1)),
          button(Glyph.rotateRight, s.t('board_rotate_right'), () => state.rotateBoard(3)),
          button(Glyph.fit, s.t('board_fit'), state.fitBoard),
          button(Glyph.reset, s.t('btn_reset_view'), state.resetBoardView),
          button(Glyph.cube, s.t('render_3d'), () => state.setBoardDepth(!state.settings.board.depth), active: state.settings.board.depth),
          Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 4), color: c.border),
          button(Glyph.exitFullscreen, s.t('btn_exit_fullscreen'), () => state.setBoardFullscreen(false)),
        ],
      ),
    );
  }
}
