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
import '../core/part_library.dart';
import '../core/models.dart';
import '../core/settings.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'check_view.dart';
import 'glyphs.dart';
import 'icons.dart';
import 'library_page.dart';
import 'part_render.dart';
import 'theme.dart';
import 'tour.dart';
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
    PartKind.electromech: Color(0xFF3E8E8A),
    PartKind.mechanical: Color(0xFFAAB0B7),
    PartKind.testPoint: Color(0xFFB59D6B),
    PartKind.fiducial: Color(0xFFBF8A57),
    PartKind.other: Color(0xFF98A0A9),
  };

  static const terminal = Color(0xFFCDD2D8);

  /// Green solder mask, the board under real colours.
  static const solderMask = Color(0xFF1F5A3B);
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

  /// The drawing built from its library model, for [buildColor].
  PartBuild? build;
  Color? buildColor;

  /// Designator width at 10 px, and the last laid-out label.
  double? probeWidth;
  TextPainter? label;
  double labelFont = 0;
  Color? labelColor;
}

/// Parts with fitted bodies in drawing order (bottom side first; on each side
/// unplaced footprints, then larger before smaller), built once per
/// coordinate file, check result and side filter instead of on every frame.
class _BoardModel {
  _BoardModel(this.parts) : extents = _extents(parts);

  final List<_Part> parts;
  final (double, double, double, double) extents;

  /// [allSides]: both sides are shown together, so bottom parts also make
  /// way for top parts drawn over them.
  factory _BoardModel.build(
    List<Placement> items,
    Map<String, MergedRef> merged,
    BoardSide Function(Placement, MergedRef?) sideOf, {
    required bool allSides,
    required bool checked,
    List<PartModelRule> rules = const [],
  }) {
    final raw = [
      for (final p in items)
        (
          p,
          merged[p.ref],
          shapeOf(
            p.ref,
            footprint: p.footprint,
            description: '${merged[p.ref]?.description ?? p.description} ${p.value}',
            model: ruleModel(rules, ref: p.ref, partNo: _partNo(p, merged[p.ref]), footprint: p.footprint),
          ),
          sideOf(p, merged[p.ref]),
        ),
    ];
    final fit = fitBodies([
      for (final (p, m, shape, side) in raw)
        BodyBox(
          x: p.x,
          y: p.y,
          rotation: p.rotation,
          width: shape.width,
          height: shape.height,
          side: side.index,
          exact: shape.exact,
          solid: !checked || m != null,
        ),
    ], yieldingSides: allSides ? {BoardSide.bottom.index} : const {});
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

/// Part number shown for a placement: what is loaded on the line, else the
/// BOM's, else the coordinate file's.
String _partNo(Placement p, MergedRef? m) {
  if (m != null && m.smtPartNo.isNotEmpty) return m.smtPartNo;
  if (m != null && m.bomPartNo.isNotEmpty) return m.bomPartNo;
  return p.partNo;
}

/// Default tilt of the 3D view, degrees from straight down.
const _defaultPitch = 50.0;

/// Zoom, pan and the 3D viewing angle; changes repaint the drawing without
/// rebuilding the page.
class _Camera {
  const _Camera(this.zoom, this.pan, {this.yaw = 0, this.pitch = _defaultPitch});

  final double zoom;
  final Offset pan;

  /// Extra rotation about the board normal and tilt, in degrees (3D only).
  final double yaw;
  final double pitch;

  _Camera copyWith({double? zoom, Offset? pan, double? yaw, double? pitch}) =>
      _Camera(zoom ?? this.zoom, pan ?? this.pan, yaw: yaw ?? this.yaw, pitch: pitch ?? this.pitch);
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
  int _resetSeen = 0;
  _Camera _gestureStart = const _Camera(1, Offset.zero);
  Offset _gestureFocal = Offset.zero;

  _BoardModel? _model;
  Object? _modelCoords;
  Object? _modelReport;
  bool? _modelAllSides;
  int? _modelRules;

  /// Part under a screen point, preferring the one drawn on top.
  _Part? _partAt(Offset pos, List<_Part> parts, _View v, bool depth, BoardSide raisedSide) {
    _Part? best;
    var bestD = double.infinity;
    for (final part in parts) {
      final h = depth && (part.side == BoardSide.bottom) == (raisedSide == BoardSide.bottom) ? part.shape.bodyHeight : 0.0;
      final d = (v.project(part.p.x, part.p.y, h) - pos).distance;
      final reach = math.max(6.0, math.max(part.shape.width, part.shape.height) * v.scale / 2);
      if (d < reach && d <= bestD) {
        bestD = d;
        best = part;
      }
    }
    return best;
  }

  void _pickModel(BuildContext context, _Part part) {
    _hover.value = null;
    showPartModelPicker(context, widget.state, ref: part.p.ref, partNo: _partNo(part.p, part.merged), footprint: part.p.footprint, current: part.shape.model);
  }

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

  void _fit() => _cam.value = _cam.value.copyWith(zoom: 1, pan: Offset.zero);

  void _orbit({double yaw = 0, double pitch = 0}) {
    final cam = _cam.value;
    _cam.value = cam.copyWith(yaw: (cam.yaw + yaw) % 360, pitch: (cam.pitch + pitch).clamp(0.0, 80.0));
  }

  _BoardModel _modelFor(LoadedFile<Placement> coords, CheckReport? report, bool allSides) {
    final rules = widget.state.partRulesVersion;
    if (_model == null || !identical(_modelCoords, coords) || !identical(_modelReport, report) || _modelAllSides != allSides || _modelRules != rules) {
      final merged = {for (final m in report?.merged ?? const <MergedRef>[]) m.ref: m};
      _model = _BoardModel.build(coords.result.items, merged, _sideOf, allSides: allSides, checked: report != null, rules: widget.state.settings.partRules);
      _modelCoords = coords;
      _modelReport = report;
      _modelAllSides = allSides;
      _modelRules = rules;
      _hover.value = null;
    }
    return _model!;
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final m = Metrics.of(context);
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
    if (state.boardResetRequest != _resetSeen) {
      _resetSeen = state.boardResetRequest;
      _cam.value = const _Camera(1, Offset.zero);
    }
    if (state.boardFitRequest != _fitSeen) {
      _fitSeen = state.boardFitRequest;
      _fit();
    }
    final report = fromFile ? null : state.report;
    final depth = state.settings.board.depth;
    final model = _modelFor(coords, report, state.boardSide == BoardSideFilter.both);
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
    // The side being looked at stands up in 3D; the other lies flat under it.
    final raisedSide = state.boardSide == BoardSideFilter.bottom ? BoardSide.bottom : BoardSide.top;
    final deg = state.boardQuarterTurns * 90;
    final palette = PartPalette(state.settings.board);

    final source = fromFile ? s.t('board_source_file', {'name': coords.name}) : s.t('board_source_check');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.immersive)
          PageHeader(
            title: s.t('mod_board'),
            subtitle: '$source  ·  ${s.t(depth ? (m.touch ? 'page_board_sub_3d_touch' : 'page_board_sub_3d') : 'page_board_sub', {'n': parts.length})}',
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
              _View view() => _fitView(model.extents, size, state.boardQuarterTurns, state.boardMirror, _cam.value, tilt: depth);
              return Listener(
                onPointerSignal: (e) {
                  if (e is PointerScrollEvent) _zoomAt(e.localPosition, e.scrollDelta.dy < 0 ? 1.18 : 1 / 1.18, size);
                },
                // Right or middle drag orbits the 3D view.
                onPointerMove: (e) {
                  if (depth && e.kind == PointerDeviceKind.mouse && e.buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0) {
                    _orbit(yaw: -e.delta.dx * 0.4, pitch: e.delta.dy * 0.35);
                  }
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  onHover: (e) {
                    final best = _partAt(e.localPosition, parts, view(), depth, raisedSide);
                    _hover.value = best == null ? null : (best, e.localPosition);
                  },
                  onExit: (_) => _hover.value = null,
                  child: GestureDetector(
                    // Right-click or long-press a part to choose its model.
                    onSecondaryTapUp: (d) {
                      final part = _partAt(d.localPosition, parts, view(), depth, raisedSide);
                      if (part != null) _pickModel(context, part);
                    },
                    onLongPressStart: (d) {
                      final part = _partAt(d.localPosition, parts, view(), depth, raisedSide);
                      if (part != null) _pickModel(context, part);
                    },
                    onScaleStart: (d) {
                      _gestureStart = _cam.value;
                      _gestureFocal = d.localFocalPoint;
                    },
                    onScaleUpdate: (d) {
                      final cam = _cam.value;
                      final center = Offset(size.width / 2, size.height / 2);
                      final newZoom = (_gestureStart.zoom * d.scale).clamp(0.2, 200.0);
                      final f = newZoom / cam.zoom;
                      var next = cam.copyWith(zoom: newZoom, pan: (d.localFocalPoint - center) * (1 - f) + cam.pan * f + d.focalPointDelta);
                      // Touch: two fingers turn the 3D view, three fingers tilt it.
                      if (depth && d.pointerCount >= 2) {
                        next = next.copyWith(yaw: (_gestureStart.yaw - d.rotation * 180 / math.pi) % 360);
                        if (d.pointerCount >= 3) {
                          next = next.copyWith(pan: cam.pan, pitch: (_gestureStart.pitch + (d.localFocalPoint.dy - _gestureFocal.dy) * 0.3).clamp(0.0, 80.0));
                        }
                      }
                      _cam.value = next;
                    },
                    onDoubleTap: _fit,
                    child: ClipRect(
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: RepaintBoundary(
                              key: tourTargets.boardCanvas,
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
                                  dimOther: state.boardSide == BoardSideFilter.both,
                                  raisedSide: raisedSide,
                                  depth: depth,
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
                          if (depth)
                            Positioned(
                              right: 14,
                              bottom: 14,
                              child: ValueListenableBuilder(
                                valueListenable: _cam,
                                builder: (context, cam, _) => _OrbitControls(
                                  cam: cam,
                                  onOrbit: _orbit,
                                  onTop: () => _cam.value = cam.copyWith(yaw: 0, pitch: 0),
                                  onDefault: () => _cam.value = cam.copyWith(yaw: 0, pitch: _defaultPitch),
                                ),
                              ),
                            ),
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
    _cam.value = cam.copyWith(zoom: newZoom, pan: (at - center) * (1 - f) + cam.pan * f);
  }

  static BoardSide _sideOf(Placement p, MergedRef? m) {
    if (p.side != BoardSide.unknown) return p.side;
    if (m?.side == StationSide.a) return BoardSide.top;
    if (m?.side == StationSide.b) return BoardSide.bottom;
    return BoardSide.unknown;
  }
}

typedef _View = BoardProjection;

/// Board extents including each part's body (half its longest side).
(double, double, double, double) _extents(List<_Part> parts) {
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

_View _fitView((double, double, double, double) ext, Size size, int quarter, bool mirror, _Camera cam, {required bool tilt}) {
  final pitch = tilt ? cam.pitch * math.pi / 180 : 0.0;
  final theta = quarter * math.pi / 2 + (tilt ? cam.yaw * math.pi / 180 : 0.0);
  final (minX, minY, maxX, maxY) = ext;
  final centre = Offset(size.width / 2, size.height / 2);
  if (!minX.isFinite) return _View(0, 0, theta, mirror, pitch, 1, centre);
  final cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  // Fit the quarter-turned board; turning it further keeps the scale so
  // the board does not pulse while it is orbited.
  final odd = quarter.isOdd;
  final w = math.max((odd ? maxY - minY : maxX - minX) + 4, 2.0);
  final h = math.max((odd ? maxX - minX : maxY - minY) * math.cos(pitch) + 4, 2.0);
  const margin = 56.0;
  final base = math.max(math.min((size.width - 2 * margin) / w, (size.height - 2 * margin) / h), 0.01);
  return _View(cx, cy, theta, mirror, pitch, base * cam.zoom, centre + cam.pan);
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
    required this.dimOther,
    required this.raisedSide,
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

  /// Both sides shown: the side not looked at is drawn dimmed underneath.
  final bool dimOther;
  final BoardSide raisedSide;

  /// 3D view: tilted camera, raised bodies with lit faces and shadows.
  final bool depth;

  /// Board thickness drawn as the slab edge in 3D, mm.
  static const _boardThickness = 1.6;

  // Canvas dot grid, rebuilt only when the size changes.
  static Float32List? _dots;
  static Size? _dotsSize;

  /// Board colour: the user's choice; real colours put parts on green solder
  /// mask; otherwise the canvas.
  Color? get _board => palette.board ?? (coloring == BoardColoring.real ? PartPalette.solderMask : null);
  Color get _boardFill => _board ?? colors.window;
  Color get _boardEdge => _board == null
      ? colors.borderStrong
      : Color.lerp(_board, _board!.computeLuminance() > 0.3 ? const Color(0xFF000000) : const Color(0xFFFFFFFF), 0.25)!;

  /// Parts of the side being looked at stand up in 3D (unknown counts as top).
  bool _raised(_Part part) => depth && (part.side == BoardSide.bottom) == (raisedSide == BoardSide.bottom);

  double _height(_Part part) => _raised(part) && _fill(part) != null ? part.shape.bodyHeight : 0;

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
    final view = _fitView(model.extents, size, quarter, mirror, cam.value, tilt: depth);
    _drawBoard(canvas, view);

    // Visible parts with their screen centres on the board.
    final visible = <(_Part, Offset)>[];
    for (final part in parts) {
      final at = view.project(part.p.x, part.p.y);
      final r = math.max(part.shape.width, part.shape.height) * view.scale + 60;
      if (at.dx < -r || at.dy < -r || at.dx > size.width + r || at.dy > size.height + r) continue;
      visible.add((part, at));
    }
    final px = 1 / view.scale; // one screen pixel in mm
    final flat = visible.where((e) => !_raised(e.$1)).toList();
    final raised = visible.where((e) => _raised(e.$1)).toList();
    // Screen bounds of filled bodies in drawing order, for label occlusion.
    final drawn = <(_Part, Rect)>[];

    // Flat parts in model order; in the all-sides view the far side is dimmed.
    if (flat.isNotEmpty) {
      bool far((_Part, Offset) e) => dimOther && e.$1.side == BoardSide.bottom && raisedSide == BoardSide.top;
      final dimmed = flat.where(far).toList();
      final normal = flat.where((e) => !far(e)).toList();
      for (final (group, dim) in [(dimmed, true), (normal, false)]) {
        if (group.isEmpty) continue;
        if (dim) canvas.saveLayer(Offset.zero & size, Paint()..color = const Color(0x8C000000));
        for (final (part, at) in group) {
          final fill = _fill(part);
          if (fill == null) {
            _drawEmpty(canvas, part, at, view, px);
          } else {
            renderPart(canvas, view, at, part.p.rotation, _build(part, fill), raised: false, px: px);
            drawn.add((part, _bounds(_corners(part, at, view))));
          }
          _drawRings(canvas, part, at, view, px);
        }
        if (dim) canvas.restore();
      }
    }

    if (raised.isNotEmpty) {
      // Unplaced footprints lie flat; shadows next; then bodies far to near.
      raised.sort((a, b) => view.depthOf(b.$1.p.x, b.$1.p.y).compareTo(view.depthOf(a.$1.p.x, a.$1.p.y)));
      for (final (part, at) in raised) {
        if (_fill(part) != null) continue;
        _drawEmpty(canvas, part, at, view, px);
        _drawRings(canvas, part, at, view, px);
      }
      final shadow = Paint()..color = Color.fromRGBO(0, 0, 0, colors.dark ? 0.4 : 0.18);
      for (final (part, at) in raised) {
        final h = _height(part);
        if (h <= 0) continue;
        final base = _corners(part, at, view);
        final off = _shadowOffset(view, h);
        canvas.drawPath(Path()..addPolygon(convexHull([...base, for (final p in base) p + off]), true), shadow);
      }
      for (final (part, at) in raised) {
        final fill = _fill(part);
        if (fill == null) continue;
        final b = _build(part, fill);
        renderPart(canvas, view, at, part.p.rotation, b, raised: true, px: px);
        final top = at + view.lift(b.top);
        _drawRings(canvas, part, top, view, px);
        drawn.add((part, _bounds([..._corners(part, at, view), ..._corners(part, top, view)])));
      }
    }
    if (cam.value.zoom > 1.05) _drawLabels(canvas, size, view, visible, drawn);
  }

  /// Where a point [h] mm above the board casts its shadow, relative to its
  /// foot, on screen.
  Offset _shadowOffset(_View view, double h) {
    final dx = -h * lightDir.$1 / lightDir.$3, dy = -h * lightDir.$2 / lightDir.$3;
    return Offset(dx * view.scale, -dy * view.cosP * view.scale);
  }

  Rect _bounds(List<Offset> pts) {
    var l = double.infinity, t = double.infinity, r = -double.infinity, b = -double.infinity;
    for (final p in pts) {
      l = math.min(l, p.dx);
      t = math.min(t, p.dy);
      r = math.max(r, p.dx);
      b = math.max(b, p.dy);
    }
    return Rect.fromLTRB(l, t, r, b);
  }

  List<Offset> _corners(_Part part, Offset at, _View view) {
    final w = part.shape.width / 2, h = part.shape.height / 2;
    return [
      for (final (x, y) in [(-w, -h), (w, -h), (w, h), (-w, h)]) at + view.localDelta(part.p.rotation, x, y),
    ];
  }

  /// Board top with its outline, plus the slab edge facing the viewer in 3D.
  void _drawBoard(Canvas canvas, _View view) {
    final (minX, minY, maxX, maxY) = model.extents;
    final pts = [(minX - 2, minY - 2), (maxX + 2, minY - 2), (maxX + 2, maxY + 2), (minX - 2, maxY + 2)];
    final edge = Paint()
      ..color = _boardEdge
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final straight = !depth || (cam.value.yaw % 90 == 0 && !view.tilted);
    if (straight) {
      final rect = Rect.fromPoints(view.project(pts[0].$1, pts[0].$2), view.project(pts[2].$1, pts[2].$2));
      final rr = RRect.fromRectAndRadius(rect, Radius.circular(math.min(12, view.scale * 1.5)));
      canvas.drawRRect(rr, Paint()..color = _boardFill);
      canvas.drawRRect(rr, edge);
      return;
    }
    final top = [for (final (x, y) in pts) view.project(x, y)];
    if (view.tilted) {
      final side = Color.lerp(_board ?? colors.borderStrong, const Color(0xFF000000), 0.35)!;
      for (var i = 0; i < 4; i++) {
        final j = (i + 1) % 4;
        // Outward normal of edge i→j in board coordinates, then on the plane.
        final ex = pts[j].$1 - pts[i].$1, ey = pts[j].$2 - pts[i].$2;
        final n = view.plane(ey, -ex);
        if (n.dy >= 0) continue;
        final drop = Offset(0, _boardThickness * view.sinP * view.scale);
        canvas.drawPath(Path()..addPolygon([top[i], top[j], top[j] + drop, top[i] + drop], true), Paint()..color = side);
      }
    }
    final path = Path()..addPolygon(top, true);
    canvas.drawPath(path, Paint()..color = _boardFill);
    canvas.drawPath(path, edge);
  }

  /// Fill colour for a part in the current colouring mode, or null to draw
  /// it as an empty footprint (not placed / not in the BOM).
  Color? _fill(_Part part) {
    final m = part.merged;
    if (checked && m == null) return null;
    if (coloring == BoardColoring.status && checked) return colors.category(m!.category);
    if (coloring == BoardColoring.real) return Color(partModel(part.shape.model).realColor);
    return palette.body(part.shape.kind);
  }

  /// The part's model, built once per body colour.
  PartBuild _build(_Part part, Color fill) {
    if (part.build == null || part.buildColor != fill) {
      part.build = buildPart(part.shape, fill, real: coloring == BoardColoring.real);
      part.buildColor = fill;
    }
    return part.build!;
  }

  /// Empty footprint: outline only.
  void _drawEmpty(Canvas canvas, _Part part, Offset at, _View view, double px) {
    canvas.save();
    view.applyPart(canvas, at, part.p.rotation);
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: part.shape.width, height: part.shape.height),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px * 1.2
        ..color = colors.textFaint,
    );
    canvas.restore();
  }

  /// Status outline in part-type and real-colour modes; selection and hover
  /// in every mode. [at] is the screen point of the body's top.
  void _drawRings(Canvas canvas, _Part part, Offset at, _View view, double px) {
    final m = part.merged;
    final status = checked && m != null && coloring != BoardColoring.status && m.category != CheckCategory.pass;
    final selected = highlight.contains(part.p.ref);
    final hovered = identical(hover.value?.$1, part);
    if (!status && !selected && !hovered) return;
    final body = Rect.fromCenter(center: Offset.zero, width: part.shape.width, height: part.shape.height);
    Paint ring(Color c, double width) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = px * width;
    canvas.save();
    view.applyPart(canvas, at, part.p.rotation);
    if (status) canvas.drawRect(body.inflate(px * 2.5), ring(m.category == CheckCategory.ng ? colors.ng : colors.substitute, 2));
    if (selected) canvas.drawRect(body.inflate(px * 5), ring(colors.accent, 2.2));
    if (hovered) canvas.drawRect(body.inflate(px * 3.5), ring(colors.text, 1.2));
    canvas.restore();
  }

  /// Designators on the top face, along the body's long axis and kept
  /// readable. Top-side and placed parts come first; a label that would cover
  /// one already drawn, or lies under a body drawn above its own, is left out.
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
      // Text frame on the top face: x along the long axis pointing right,
      // y turned so the text is never mirrored; one unit = one pixel of an
      // untilted view.
      final along = sh.width >= sh.height;
      var e1 = view.localDelta(part.p.rotation, along ? 1 : 0, along ? 0 : 1) / view.scale;
      var e2 = view.localDelta(part.p.rotation, along ? 0 : 1, along ? 1 : 0) / view.scale;
      if (e1.dx < -1e-6 || (e1.dx.abs() <= 1e-6 && e1.dy < 0)) e1 = -e1;
      if (e1.dx * e2.dy - e1.dy * e2.dx < 0) e2 = -e2;
      final centre = at + Offset(0, -_height(part) * view.sinP * view.scale);
      final hw = tp.width / 2, hh = tp.height / 2;
      final box = _bounds([
        for (final (x, y) in [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]) centre + e1 * x + e2 * y,
      ]);
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
      canvas.transform(Float64List.fromList([e1.dx, e1.dy, 0, 0, e2.dx, e2.dy, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
      tp.paint(canvas, Offset(-hw, -hh));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_AssemblyPainter old) => true;
}

/// 3D view angle controls: tilt, turn, top view and default view.
class _OrbitControls extends StatelessWidget {
  const _OrbitControls({required this.cam, required this.onOrbit, required this.onTop, required this.onDefault});

  final _Camera cam;
  final void Function({double yaw, double pitch}) onOrbit;
  final VoidCallback onTop;
  final VoidCallback onDefault;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final m = Metrics.of(context);
    final size = m.touch ? 40.0 : 34.0;
    Widget button(Glyph g, String tip, VoidCallback onTap) => Hoverable(
      onTap: onTap,
      tooltip: tip,
      builder: (context, hover, _) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: hover ? c.hover : null, borderRadius: BorderRadius.circular(7)),
        child: GlyphIcon(g, size: 18, color: c.text),
      ),
    );
    Widget text(String label, VoidCallback onTap, bool active) => Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        height: size,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active
              ? c.accent.withValues(alpha: 0.14)
              : hover
              ? c.hover
              : null,
          borderRadius: BorderRadius.circular(7),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: active ? c.accent : c.text),
        ),
      ),
    );
    final yaw = cam.yaw > 180 ? cam.yaw - 360 : cam.yaw;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.panel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
        boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              s.t('orbit_state', {'tilt': cam.pitch.round(), 'turn': yaw.round()}),
              style: TextStyle(fontSize: 12, color: c.textDim, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
          button(Glyph.chevronUp, s.t('orbit_tilt_less'), () => onOrbit(pitch: -10)),
          button(Glyph.chevronDown, s.t('orbit_tilt_more'), () => onOrbit(pitch: 10)),
          button(Glyph.rotateLeft, s.t('orbit_turn_left'), () => onOrbit(yaw: 15)),
          button(Glyph.rotateRight, s.t('orbit_turn_right'), () => onOrbit(yaw: -15)),
          Container(width: 1, height: 20, margin: const EdgeInsets.symmetric(horizontal: 4), color: c.border),
          text(s.t('orbit_top'), onTop, cam.pitch == 0 && cam.yaw == 0),
          text(s.t('orbit_default'), onDefault, cam.pitch == _defaultPitch && cam.yaw == 0),
        ],
      ),
    );
  }
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
    if (coloring == BoardColoring.real) {
      return IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: c.panel.withValues(alpha: 0.95),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.t('color_real'),
                style: TextStyle(fontSize: 11.5, color: c.textDim, fontWeight: FontWeight.w600),
              ),
              if (checked) ...[
                const SizedBox(width: 14),
                Container(
                  width: 14,
                  height: 8,
                  decoration: BoxDecoration(border: Border.all(color: c.ng, width: 1.5)),
                ),
                const SizedBox(width: 6),
                Text(s.t('cat_ng'), style: TextStyle(fontSize: 11.5, color: c.textDim)),
                const SizedBox(width: 14),
                Container(
                  width: 14,
                  height: 8,
                  decoration: BoxDecoration(border: Border.all(color: c.textFaint)),
                ),
                const SizedBox(width: 6),
                Text(s.t('board_not_in_bom'), style: TextStyle(fontSize: 11.5, color: c.textDim)),
              ],
            ],
          ),
        ),
      );
    }
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
              (PartKind.electromech, 'type_electromech'),
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
            if (coloring != BoardColoring.status && checked)
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
            const SizedBox(height: 4),
            Text(
              s.t('hover_model', {'m': s.t('pm_${part.shape.model}')}),
              style: style.copyWith(color: c.text, fontWeight: FontWeight.w600),
            ),
            Text(s.t('hover_model_hint'), style: style.copyWith(fontSize: 11, color: c.textFaint)),
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
