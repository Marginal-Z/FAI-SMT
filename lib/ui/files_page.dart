/// Files module: banner, progress steps, the three input cards, a per-file
/// check summary, and the readiness bar with Run Check.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'glyphs.dart';
import 'icons.dart';
import 'theme.dart';
import 'widgets.dart';

class FilesPage extends StatelessWidget {
  const FilesPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final ready = state.bom != null && (state.stationA != null || state.stationB != null);
    final inputs = [
      _Input(InputKind.bom, s.t('in_bom_title'), s.t('in_bom_hint'), state.bom, false),
      _Input(InputKind.stationA, s.t('btn_station_a'), s.t('step_station_a'), state.stationA, false),
      _Input(InputKind.stationB, s.t('btn_station_b'), s.t('in_station_b_hint'), state.stationB, true),
    ];

    return Container(
      color: c.window,
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 980;
          Widget row(List<Widget> children) => wide
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 16), Expanded(child: children[i])],
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
                  ],
                );
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageBanner(title: s.t('mod_files'), subtitle: s.t('files_banner_sub')),
                const SizedBox(height: 18),
                _Steps(state: state, ready: ready),
                const SizedBox(height: 18),
                row([for (final i in inputs) _InputCard(state: state, input: i)]),
                const SizedBox(height: 18),
                SurfaceCard(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          _Tile(glyph: Glyph.fileCheck, color: c.accent, size: 44),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.t('files_check_title'),
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text),
                              ),
                              const SizedBox(height: 2),
                              Text(s.t('files_check_sub'), style: TextStyle(fontSize: 12.5, color: c.textDim)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      row([for (final i in inputs) _CheckColumn(input: i)]),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _ReadyBar(state: state, ready: ready),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Input {
  _Input(this.kind, this.title, this.hint, this.file, this.optional);

  final InputKind kind;
  final String title;
  final String hint;
  final LoadedFile<Object?>? file;
  final bool optional;
}

/// Rounded tile with a glyph, used for file and section icons.
class _Tile extends StatelessWidget {
  const _Tile({required this.glyph, required this.color, this.size = 46, this.solid = false});

  final Glyph glyph;
  final Color color;
  final double size;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: c.dark ? 0.16 : 0.1),
        borderRadius: BorderRadius.circular(size * 0.24),
      ),
      child: GlyphIcon(glyph, size: size * 0.52, filled: solid, color: solid ? const Color(0xFFFFFFFF) : color),
    );
  }
}

/// 1 Import files → 2 BOM check → 3 Generate FAI coordinates.
class _Steps extends StatelessWidget {
  const _Steps({required this.state, required this.ready});

  final AppState state;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final checked = state.report != null;
    final cadReady = checked && state.coords != null;
    final steps = [
      (s.t('step1_title'), s.t('step1_sub'), ready, !ready, null),
      (s.t('step2_title'), s.t('step2_sub'), checked, ready && !checked, () => state.setModule(Module.check)),
      (s.t('step3_title'), s.t('step3_sub'), cadReady, checked && !cadReady, () => state.setModule(Module.cad)),
    ];
    return Row(
      children: [
        for (var i = 0; i < steps.length; i++) ...[
          if (i > 0)
            Expanded(
              child: Container(height: 2, margin: const EdgeInsets.symmetric(horizontal: 16), color: steps[i - 1].$3 ? c.pass : c.border),
            ),
          Hoverable(
            onTap: steps[i].$5,
            builder: (context, hover, _) {
              final (title, sub, done, active, _) = steps[i];
              final color = done
                  ? c.pass
                  : active
                  ? c.accent
                  : c.textFaint;
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done || active ? color : c.panel,
                      border: done || active ? null : Border.all(color: c.borderStrong, width: 1.5),
                    ),
                    child: done
                        ? const GlyphIcon(Glyph.okCircle, size: 20, filled: true, color: Color(0xFFFFFFFF))
                        : Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: active ? const Color(0xFFFFFFFF) : c.textDim,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: done || active ? (hover ? c.accent : c.text) : c.textDim,
                        ),
                      ),
                      Text(sub, style: TextStyle(fontSize: 12, color: c.textFaint)),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _InputCard extends StatelessWidget {
  const _InputCard({required this.state, required this.input});

  final AppState state;
  final _Input input;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final f = input.file;
    final loaded = f != null;
    final issues = f?.result.issues.length ?? 0;
    final count = f?.result.items.length ?? 0;
    final refs = switch (f?.result.items) {
      final List<StationItem> st => st.fold<int>(0, (n, e) => n + e.refs.length),
      final List<BomItem> b => b.fold<int>(0, (n, e) => n + e.refs.length),
      _ => 0,
    };
    final summary = input.kind == InputKind.bom
        ? s.t('in_bom_parsed', {'n': count, 'r': refs})
        : s.t('in_station_parsed', {'n': count, 'r': refs});

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: loaded ? c.pass.withValues(alpha: 0.5) : c.border, width: loaded ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Tile(glyph: Glyph.modCad, color: c.pass, solid: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            input.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text),
                          ),
                        ),
                        if (input.optional) Text('  ${s.t('in_optional')}', style: TextStyle(fontSize: 12.5, color: c.textFaint)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      input.hint,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.textDim),
                    ),
                  ],
                ),
              ),
              if (loaded) GlyphIcon(Glyph.okCircle, size: 24, filled: true, color: c.pass),
            ],
          ),
          const SizedBox(height: 16),
          if (loaded) ...[
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              decoration: BoxDecoration(
                color: c.panelAlt,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  _Tile(glyph: Glyph.modCad, color: c.pass, size: 32, solid: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${s.t('file_items', {'n': count})}  ·  ${formatSize(f.size)}  ·  ${formatTime(f.loadedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.textDim),
                        ),
                      ],
                    ),
                  ),
                  IconBtn(
                    icon: Ic.arrowCounterClockwise,
                    tooltip: s.t('step_replace'),
                    onTap: () => importFile(context, state, input.kind),
                  ),
                  IconBtn(icon: Ic.x, tooltip: s.t('file_remove'), onTap: () => state.unload(input.kind)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: (issues == 0 ? c.pass : c.substitute).withValues(alpha: c.dark ? 0.14 : 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  GlyphIcon(
                    issues == 0 ? Glyph.okCircle : Glyph.discrepancies,
                    size: 17,
                    filled: true,
                    color: issues == 0 ? c.pass : c.substitute,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      issues == 0 ? summary : '$summary  ·  ${s.t('in_issues', {'n': issues})}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.text),
                    ),
                  ),
                ],
              ),
            ),
          ] else
            Hoverable(
              onTap: () => importFile(context, state, input.kind),
              builder: (context, hover, _) => CustomPaint(
                painter: _DashedBorder(hover ? c.accent : c.borderStrong),
                child: Container(
                  height: 104,
                  alignment: Alignment.center,
                  color: hover ? c.accent.withValues(alpha: 0.04) : null,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlyphIcon(Glyph.openFile, size: 26, color: hover ? c.accent : c.textDim),
                      const SizedBox(height: 8),
                      Text(
                        s.t('in_click_import'),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: hover ? c.accent : c.text),
                      ),
                      const SizedBox(height: 2),
                      Text(s.t('in_formats'), style: TextStyle(fontSize: 11.5, color: c.textFaint)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DashedBorder extends CustomPainter {
  _DashedBorder(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)));
    for (final metric in path.computeMetrics()) {
      for (var d = 0.0; d < metric.length; d += 9) {
        canvas.drawPath(metric.extractPath(d, d + 5), p);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) => old.color != color;
}

/// Format, sheets, recognised columns and structure findings for one file.
class _CheckColumn extends StatelessWidget {
  const _CheckColumn({required this.input});

  final _Input input;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final f = input.file;
    final ext = f == null ? '' : f.name.split('.').last.toLowerCase();
    final columns = f?.result.columns.entries.where((e) => e.key != 'unit').map((e) => e.value).toList() ?? const <String>[];
    final issues = f?.result.issues ?? const [];
    final rows = f == null
        ? <(Status, String, String)>[]
        : [
            (
              Status.ok,
              s.t('chk_format', {'ext': '.$ext'}),
              input.kind == InputKind.bom
                  ? s.t('in_bom_count', {'n': f.result.items.length})
                  : s.t('in_station_count', {'n': f.result.items.length}),
            ),
            (Status.ok, s.t('chk_sheets'), s.t('chk_sheets_n', {'n': f.sheets})),
            (
              columns.length >= 2 ? Status.ok : Status.warning,
              s.t(input.kind == InputKind.bom ? 'chk_bom_cols' : 'chk_station_cols'),
              columns.take(4).join(' / '),
            ),
            (
              issues.isEmpty ? Status.ok : Status.warning,
              s.t('chk_structure'),
              issues.isEmpty ? s.t('chk_passed') : s.t('in_issues', {'n': issues.length}),
            ),
          ];
    final overall = f == null
        ? Status.idle
        : rows.any((r) => r.$1 == Status.warning)
        ? Status.warning
        : Status.ok;
    Color tone(Status st) => switch (st) {
      Status.ok => c.pass,
      Status.warning => c.substitute,
      Status.error => c.ng,
      Status.idle => c.textFaint,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.panelAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: tone(overall).withValues(alpha: c.dark ? 0.18 : 0.12),
                ),
                child: GlyphIcon(
                  overall == Status.idle ? Glyph.info : (overall == Status.ok ? Glyph.okCircle : Glyph.discrepancies),
                  size: 22,
                  filled: true,
                  color: tone(overall),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      input.title,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text),
                    ),
                    Text(
                      f?.name ?? s.t('file_none'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: c.textDim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (f == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                input.optional ? s.t('chk_optional_missing') : s.t('chk_missing'),
                style: TextStyle(fontSize: 12.5, color: c.textFaint),
              ),
            ),
          for (final (st, label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  GlyphIcon(st == Status.ok ? Glyph.okCircle : Glyph.discrepancies, size: 17, filled: true, color: tone(st)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label, style: TextStyle(fontSize: 13, color: c.text)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 12.5, color: c.textDim),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ReadyBar extends StatelessWidget {
  const _ReadyBar({required this.state, required this.ready});

  final AppState state;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final tone = ready ? c.accent : c.textFaint;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      decoration: BoxDecoration(
        color: ready ? c.accent.withValues(alpha: c.dark ? 0.1 : 0.05) : c.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ready ? c.accent.withValues(alpha: 0.35) : c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: tone),
            child: const GlyphIcon(Glyph.info, size: 22, filled: true, color: Color(0xFFFFFFFF)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.t(ready ? 'ready_title' : 'not_ready_title'),
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ready ? c.accent : c.text),
                ),
                const SizedBox(height: 2),
                Text(s.t(ready ? 'ready_sub' : 'files_not_ready'), style: TextStyle(fontSize: 12.5, color: c.textDim)),
              ],
            ),
          ),
          Hoverable(
            onTap: state.clearAll,
            builder: (context, hover, _) => Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: hover ? c.hover : c.panel,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.borderStrong),
              ),
              child: Row(
                children: [
                  GlyphIcon(Glyph.trash, size: 18, color: c.textDim),
                  const SizedBox(width: 8),
                  Text(s.t('btn_clear'), style: TextStyle(fontSize: 14, color: c.text)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Hoverable(
            onTap: ready ? () => runCheck(context, state) : null,
            builder: (context, hover, pressed) => Container(
              height: 48,
              padding: const EdgeInsets.only(left: 22, right: 12),
              decoration: BoxDecoration(
                color: !ready
                    ? c.border
                    : pressed
                    ? c.accent.withValues(alpha: 0.85)
                    : hover
                    ? c.accent.withValues(alpha: 0.92)
                    : c.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  GlyphIcon(Glyph.play, size: 18, filled: true, color: ready ? const Color(0xFFFFFFFF) : c.textFaint),
                  const SizedBox(width: 10),
                  Text(
                    s.t('btn_run'),
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ready ? const Color(0xFFFFFFFF) : c.textFaint),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(5)),
                    child: Text('F5', style: TextStyle(fontSize: 12, color: ready ? const Color(0xFFFFFFFF) : c.textFaint)),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
