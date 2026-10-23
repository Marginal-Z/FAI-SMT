/// First-run guided tour: a dimmed overlay with a spotlight on one control at
/// a time and a callout explaining it. Targets register a [GlobalKey] from
/// [tourTargets]; a step whose target is not on screen shows its callout in
/// the middle of the window.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../l10n/strings.dart';
import 'glyphs.dart';
import 'theme.dart';
import 'widgets.dart';

class TourTargets {
  final _modules = {for (final m in Module.values) m: GlobalKey(debugLabel: 'tour-${m.name}')};

  GlobalKey module(Module m) => _modules[m]!;

  final bomCard = GlobalKey(debugLabel: 'tour-bom');
  final stationCard = GlobalKey(debugLabel: 'tour-station');
  final runButton = GlobalKey(debugLabel: 'tour-run');
  final settings = GlobalKey(debugLabel: 'tour-settings');
  final help = GlobalKey(debugLabel: 'tour-help');
}

final tourTargets = TourTargets();

class _Step {
  const _Step(this.key, this.target, {this.module});

  /// Text keys `tour_<key>_title` / `tour_<key>_body`.
  final String key;
  final GlobalKey? Function() target;

  /// Module to show while this step is open.
  final Module? module;
}

final _steps = <_Step>[
  _Step('welcome', () => null, module: Module.files),
  _Step('modules', () => tourTargets.module(Module.files), module: Module.files),
  _Step('bom', () => tourTargets.bomCard, module: Module.files),
  _Step('station', () => tourTargets.stationCard, module: Module.files),
  _Step('run', () => tourTargets.runButton, module: Module.files),
  _Step('check', () => tourTargets.module(Module.check), module: Module.files),
  _Step('cad', () => tourTargets.module(Module.cad), module: Module.files),
  _Step('board', () => tourTargets.module(Module.board), module: Module.files),
  _Step('help', () => tourTargets.help, module: Module.files),
  _Step('done', () => null, module: Module.files),
];

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
    final want = _steps[step].module;
    if (want != null && state.module != want && !state.settingsOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) => state.setModule(want));
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
        final hole = target?.inflate(6);
        // Callout below the target when it fits, otherwise above, else centred.
        Offset pos;
        if (hole == null) {
          pos = Offset((size.width - cardW) / 2, size.height / 2 - 110);
        } else {
          final x = (hole.center.dx - cardW / 2).clamp(16.0, math.max(16.0, size.width - cardW - 16)).toDouble();
          pos = hole.bottom + 230 < size.height ? Offset(x, hole.bottom + 14) : Offset(x, math.max(16.0, hole.top - 14 - 220));
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
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.borderStrong),
                  boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 24, offset: Offset(0, 8))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        GlyphIcon(Glyph.tip, size: 18, filled: true, color: c.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.t('tour_${_steps[step].key}_title'),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.text),
                          ),
                        ),
                        Text('${step + 1} / ${_steps.length}', style: TextStyle(fontSize: 12, color: c.textFaint)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(s.t('tour_${_steps[step].key}_body'), style: TextStyle(fontSize: 13, color: c.textDim, height: 1.55)),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        if (!last)
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
