/// First-run guided tour: a dimmed overlay with a spotlight on one control at
/// a time and a callout explaining it. Targets register a [GlobalKey] from
/// [tourTargets]; a step whose target is not on screen shows its callout in
/// the middle of the window.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../l10n/strings.dart';
import 'glyphs.dart';
import 'theme.dart';
import 'widgets.dart';

class TourTargets {
  final tabs = GlobalKey(debugLabel: 'tour-tabs');
  final checkTab = GlobalKey(debugLabel: 'tour-check-tab');
  final singleCard = GlobalKey(debugLabel: 'tour-single');
  final aCard = GlobalKey(debugLabel: 'tour-a');
  final bCard = GlobalKey(debugLabel: 'tour-b');
  final fileChecks = GlobalKey(debugLabel: 'tour-file-checks');
  final runButton = GlobalKey(debugLabel: 'tour-run');
  final aiSwitch = GlobalKey(debugLabel: 'tour-ai-switch');
  final modeSelector = GlobalKey(debugLabel: 'tour-mode');
  final checkCards = GlobalKey(debugLabel: 'tour-check-cards');
  final checkFilters = GlobalKey(debugLabel: 'tour-check-filters');
  final checkTable = GlobalKey(debugLabel: 'tour-check-table');
  final checkExport = GlobalKey(debugLabel: 'tour-check-export');
  final aiSettings = GlobalKey(debugLabel: 'tour-ai-settings');
  final guide = GlobalKey(debugLabel: 'tour-guide');
  final help = GlobalKey(debugLabel: 'tour-help');
}

final tourTargets = TourTargets();

/// Where a step happens: the check page (null), or a Settings page.
class _Place {
  const _Place.check() : section = null;
  const _Place.settings(this.section);

  final SettingsSection? section;
}

class _Step {
  const _Step(this.key, this.place, this.target);

  /// Text keys `tour_<key>_title` / `tour_<key>_body`.
  final String key;
  final _Place place;
  final GlobalKey? Function() target;
}

const _check = _Place.check();

final _steps = <_Step>[
  _Step('welcome', _check, () => null),
  _Step('single', _check, () => tourTargets.singleCard),
  _Step('a', _check, () => tourTargets.aCard),
  _Step('b', _check, () => tourTargets.bCard),
  _Step('run', _check, () => tourTargets.runButton),
  _Step('ai_switch', _check, () => tourTargets.aiSwitch),
  _Step('check_cards', _check, () => tourTargets.checkCards),
  _Step('check_filters', _check, () => tourTargets.checkFilters),
  _Step('check_table', _check, () => tourTargets.checkTable),
  _Step('check_export', _check, () => tourTargets.checkExport),
  _Step('ai_settings', const _Place.settings(SettingsSection.ai), () => tourTargets.aiSettings),
  _Step('guide', const _Place.settings(SettingsSection.guide), () => tourTargets.guide),
  _Step('help', _check, () => tourTargets.help),
  _Step('done', _check, () => null),
];

/// The sample files the tour uses when nothing is loaded.
const _demo = [
  (InputKind.single, 'demo_A_BOM.xlsx'),
  (InputKind.a, 'demo_B_BOM.xlsx'),
  (InputKind.b, 'demo_C_BOM.xlsx'),
];

/// Loads the bundled sample files so every page has something to show.
Future<void> loadTourDemo(AppState state) async {
  if (state.loadedCount > 0) return;
  for (final (kind, name) in _demo) {
    final data = await rootBundle.load('samples/demo/$name');
    state.load(kind, name, data.buffer.asUint8List());
  }
  state.tourDemo = true;
}

/// Opens the page of [step] and prepares what it shows.
Future<void> _enter(AppState state, int step) async {
  final s = _steps[step];
  if (step == 0) await loadTourDemo(state);
  // From the check results on, the comparison is there to look at.
  if (step >= 5 && state.report == null && state.ready) {
    try {
      state.runCheckNow();
    } catch (_) {}
  }
  if (s.place.section != null) {
    if (!state.settingsOpen || state.settingsSection != s.place.section) state.openSettings(s.place.section!);
  } else if (state.settingsOpen) {
    state.closeSettings();
  }
}

int get tourLength => _steps.length;

class TourOverlay extends StatefulWidget {
  const TourOverlay({super.key, required this.state});

  final AppState state;

  @override
  State<TourOverlay> createState() => _TourOverlayState();
}

class _TourOverlayState extends State<TourOverlay> {
  Rect? _target;
  int _measured = -1;
  int _entered = -1;

  void _measure() {
    final step = widget.state.tourStep;
    if (step == null || !mounted) return;
    final ctx = _steps[step].target()?.currentContext;
    final box = ctx?.findRenderObject() as RenderBox?;
    final me = context.findRenderObject() as RenderBox?;
    Rect? rect;
    if (box != null && box.hasSize && me != null && box.attached) {
      final topLeft = box.localToGlobal(Offset.zero, ancestor: me);
      rect = topLeft & box.size;
    }
    if (rect != _target || _measured != step) {
      setState(() {
        _target = rect;
        _measured = step;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final step = state.tourStep;
    if (step == null) return const SizedBox.shrink();
    if (_entered != step) {
      _entered = step;
      WidgetsBinding.instance.addPostFrameCallback((_) => _enter(state, step));
    }
    // Measure after layout: targets move with the window and the page.
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final target = _measured == step ? _target : null;
    return LayoutBuilder(
      builder: (context, box) {
        const cardW = 360.0;
        final size = box.biggest;
        final visible = target?.intersect(Offset.zero & size);
        final hole = visible != null && !visible.isEmpty ? visible.inflate(6) : null;
        // Callout below the target when it fits, else above, else beside it,
        // else inside its lower right corner (targets as large as the page).
        const cardH = 250.0;
        Offset pos;
        if (hole == null) {
          pos = Offset((size.width - cardW) / 2, size.height / 2 - cardH / 2);
        } else {
          double clampX(double x) => x.clamp(16.0, math.max(16.0, size.width - cardW - 16)).toDouble();
          double clampY(double y) => y.clamp(16.0, math.max(16.0, size.height - cardH - 16)).toDouble();
          if (hole.bottom + 14 + cardH < size.height) {
            pos = Offset(clampX(hole.center.dx - cardW / 2), clampY(hole.bottom + 14));
          } else if (hole.top - 14 - cardH > 0) {
            pos = Offset(clampX(hole.center.dx - cardW / 2), clampY(hole.top - 14 - cardH));
          } else if (hole.right + 14 + cardW < size.width) {
            pos = Offset(hole.right + 14, clampY(hole.center.dy - cardH / 2));
          } else if (hole.left - 14 - cardW > 0) {
            pos = Offset(hole.left - 14 - cardW, clampY(hole.center.dy - cardH / 2));
          } else {
            pos = Offset(clampX(hole.right - cardW - 24), clampY(hole.bottom - cardH - 24));
          }
        }
        final last = step == _steps.length - 1;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: CustomPaint(painter: _Backdrop(hole, c.accent)),
              ),
            ),
            Positioned(
              left: pos.dx,
              top: pos.dy,
              width: cardW,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
                decoration: BoxDecoration(
                  color: c.solid,
                  borderRadius: c.r(26),
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 48, offset: Offset(0, 18))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Progress through the tour.
                    Row(
                      children: [
                        for (var i = 0; i < _steps.length; i++)
                          Expanded(
                            child: Container(
                              height: 3,
                              margin: const EdgeInsets.only(right: 2),
                              decoration: BoxDecoration(color: i <= step ? c.blue : c.track, borderRadius: c.r(2)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _placeLabel(s, _steps[step].place),
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: c.accent, letterSpacing: 0.3),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        GlyphIcon(Glyph.tip, size: 18, filled: true, color: c.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.t('tour_${_steps[step].key}_title'),
                            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: c.tx),
                          ),
                        ),
                        Text('${step + 1} / ${_steps.length}', style: TextStyle(fontSize: 12, color: c.textFaint)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(s.t('tour_${_steps[step].key}_body'), style: TextStyle(fontSize: 14, color: c.tx2, height: 1.55)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        // The first-run tour is gone through once; later runs can be skipped.
                        if (!last && state.settings.tourDone)
                          Hoverable(
                            onTap: state.endTour,
                            builder: (context, hover, _) => Text(s.t('tour_skip'), style: TextStyle(fontSize: 13, color: hover ? c.text : c.textFaint)),
                          ),
                        const Spacer(),
                        if (step > 0 && !last) ...[
                          FlatButton(label: s.t('tour_back'), compact: true, onTap: () => state.setTourStep(step - 1)),
                          const SizedBox(width: 8),
                        ],
                        FlatButton(
                          label: s.t(last ? 'tour_finish' : (step == 0 ? 'tour_start' : 'tour_next')),
                          primary: true,
                          compact: true,
                          onTap: last ? state.endTour : () => state.setTourStep(step + 1),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

String _placeLabel(Strings s, _Place place) {
  final section = place.section;
  if (section != null) {
    return '${s.t('mod_settings')} · ${s.t(section == SettingsSection.ai ? 'set_ai' : 'set_guide')}';
  }
  return s.t('mod_check');
}

class _Backdrop extends CustomPainter {
  _Backdrop(this.hole, this.accent);

  final Rect? hole;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (hole != null) path.addRRect(RRect.fromRectAndRadius(hole!, const Radius.circular(10)));
    canvas.drawPath(path, Paint()..color = const Color(0x8C0B0D10));
    if (hole != null) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(hole!, const Radius.circular(10)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(_Backdrop old) => old.hole != hole || old.accent != accent;
}
