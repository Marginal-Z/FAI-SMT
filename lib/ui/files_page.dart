/// Files module: banner, the three input cards (click or drop a file), a
/// per-file check table, and the readiness bar with Run Check. On a tall
/// window the cards and the table share the height.
library;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'glyphs.dart';
import 'icons.dart';
import 'theme.dart';
import 'tour.dart';
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
      _Input(1, InputKind.bom, s.t('in_bom_title'), s.t('in_bom_hint'), s.t('in_bom_help'), state.bom, false, c.accent),
      _Input(2, InputKind.stationA, s.t('btn_station_a'), s.t('step_station_a'), s.t('in_station_help'), state.stationA, false, c.pass),
      _Input(3, InputKind.stationB, s.t('btn_station_b'), s.t('in_station_b_hint'), s.t('in_station_help'), state.stationB, true, c.substitute),
    ];
    // The next file to import is highlighted.
    final next = inputs.where((i) => i.file == null && !i.optional).firstOrNull?.kind;

    return Container(
      color: c.window,
      child: LayoutBuilder(
        builder: (context, box) {
          final wide = box.maxWidth >= 980;
          // Tall enough: cards and checks share the height; otherwise scroll.
          final fill = wide && box.maxHeight >= 740;
          Widget row(List<Widget> children) {
            if (!wide) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 12), children[i]],
                ],
              );
            }
            final r = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 16), Expanded(child: children[i])],
              ],
            );
            // Scrolling page: the row takes its tallest card's height.
            return fill ? r : IntrinsicHeight(child: r);
          }

          final cards = row([
            for (final i in inputs)
              _InputCard(
                key: switch (i.kind) {
                  InputKind.bom => tourTargets.bomCard,
                  InputKind.stationA => tourTargets.stationCard,
                  _ => null,
                },
                state: state,
                input: i,
                highlight: i.kind == next,
                fill: fill,
              ),
          ]);
          final checks = SurfaceCard(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    _Tile(glyph: Glyph.fileCheck, color: c.accent, size: 40, solid: true),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.t('files_check_title'),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text),
                        ),
                        Text(s.t('files_check_sub'), style: TextStyle(fontSize: 12.5, color: c.textDim)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (fill)
                  Expanded(child: row([for (final i in inputs) _CheckTable(input: i, fill: true)]))
                else
                  row([for (final i in inputs) _CheckTable(input: i, fill: false)]),
              ],
            ),
          );
          final children = <Widget>[
            _Hero(title: s.t('mod_files'), subtitle: s.t('files_banner_sub')),
            const SizedBox(height: 16),
            if (fill) Expanded(flex: 5, child: cards) else cards,
            const SizedBox(height: 16),
            if (fill) Expanded(flex: 5, child: checks) else checks,
            const SizedBox(height: 16),
            _ReadyBar(state: state, ready: ready),
          ];
          const pad = EdgeInsets.fromLTRB(20, 18, 20, 20);
          return fill
              ? Padding(
                  padding: pad,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                )
              : SingleChildScrollView(
                  padding: pad,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
                );
        },
      ),
    );
  }
}

class _Input {
  _Input(this.index, this.kind, this.title, this.hint, this.help, this.file, this.optional, this.tint);

  final int index;
  final InputKind kind;
  final String title;
  final String hint;

  /// What the file must contain, shown from the "?" button.
  final String help;
  final LoadedFile<Object?>? file;
  final bool optional;

  /// Colour of the drop-zone document icon.
  final Color tint;
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

/// Page banner with a flat drawing of stacked spreadsheets.
class _Hero extends StatelessWidget {
  const _Hero({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _HeroArt(c))),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 24, 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: c.text, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                Text(subtitle, style: TextStyle(fontSize: 14, color: c.textDim)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroArt extends CustomPainter {
  _HeroArt(this.c);

  final AppColors c;

  @override
  void paint(Canvas canvas, Size size) {
    // Faint perspective grid towards the right.
    final grid = Paint()
      ..color = c.accent.withValues(alpha: c.dark ? 0.08 : 0.06)
      ..strokeWidth = 1;
    final x0 = size.width * 0.55;
    for (var i = 0; i < 9; i++) {
      final x = x0 + i * (size.width - x0) / 8;
      canvas.drawLine(Offset(x, size.height), Offset(x + 60, 0), grid);
    }
    for (var j = 1; j < 5; j++) {
      final y = size.height * j / 5;
      canvas.drawLine(Offset(x0 + 30, y), Offset(size.width, y), grid);
    }
    // Three sheets standing in a row, each a skewed card with a table on it.
    final right = size.width - 70;
    for (var k = 2; k >= 0; k--) {
      final dx = right - 150 + k * 46, top = 22.0 + k * 6;
      final h = size.height - top - 16;
      final face = Path()..addPolygon([Offset(dx, top + 18), Offset(dx + 70, top), Offset(dx + 70, top + h - 22), Offset(dx, top + h)], true);
      final edge = Path()..addPolygon([Offset(dx + 70, top), Offset(dx + 80, top + 4), Offset(dx + 80, top + h - 18), Offset(dx + 70, top + h - 22)], true);
      final tint = [0.35, 0.55, 0.85][k];
      canvas.drawPath(edge, Paint()..color = Color.lerp(c.accent, const Color(0xFF000000), 0.25)!.withValues(alpha: tint));
      canvas.drawPath(face, Paint()..color = c.accent.withValues(alpha: tint * (c.dark ? 0.7 : 0.55)));
      if (k == 0) {
        final line = Paint()
          ..color = const Color(0xCCFFFFFF)
          ..strokeWidth = 2;
        for (var r = 0; r < 4; r++) {
          final y = top + 30 + r * 16.0;
          canvas.drawLine(Offset(dx + 12, y + 2 - r * 0.0), Offset(dx + 58, y - 10), line);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HeroArt old) => old.c != c;
}

/// Document with a plus badge, the drop-zone icon.
class _DocIcon extends StatelessWidget {
  const _DocIcon({required this.color, this.size = 40});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _DocPainter(color)),
  );
}

class _DocPainter extends CustomPainter {
  _DocPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 40;
    final doc = Path()
      ..moveTo(7 * s, 3 * s)
      ..lineTo(23 * s, 3 * s)
      ..lineTo(31 * s, 11 * s)
      ..lineTo(31 * s, 35 * s)
      ..arcToPoint(Offset(29 * s, 37 * s), radius: Radius.circular(2 * s))
      ..lineTo(9 * s, 37 * s)
      ..arcToPoint(Offset(7 * s, 35 * s), radius: Radius.circular(2 * s))
      ..close();
    canvas.drawPath(doc, Paint()..color = color);
    canvas.drawPath(
      Path()..addPolygon([Offset(23 * s, 3 * s), Offset(31 * s, 11 * s), Offset(23 * s, 11 * s)], true),
      Paint()..color = Color.lerp(color, const Color(0xFFFFFFFF), 0.45)!,
    );
    final line = Paint()
      ..color = const Color(0xE6FFFFFF)
      ..strokeWidth = 2 * s
      ..strokeCap = StrokeCap.round;
    for (final y in [17.0, 22.0, 27.0]) {
      canvas.drawLine(Offset(12 * s, y * s), Offset((y == 27 ? 19 : 25) * s, y * s), line);
    }
    // Plus badge.
    canvas.drawCircle(Offset(30 * s, 31 * s), 8 * s, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawCircle(Offset(30 * s, 31 * s), 6.5 * s, Paint()..color = color);
    canvas.drawLine(Offset(27 * s, 31 * s), Offset(33 * s, 31 * s), line);
    canvas.drawLine(Offset(30 * s, 28 * s), Offset(30 * s, 34 * s), line);
  }

  @override
  bool shouldRepaint(_DocPainter old) => old.color != color;
}

class _InputCard extends StatefulWidget {
  const _InputCard({super.key, required this.state, required this.input, required this.highlight, required this.fill});

  final AppState state;
  final _Input input;
  final bool highlight;

  /// The card stretches to the row height (drop zone fills the rest).
  final bool fill;

  @override
  State<_InputCard> createState() => _InputCardState();
}

class _InputCardState extends State<_InputCard> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final state = widget.state;
    final input = widget.input;
    final f = input.file;
    final loaded = f != null;
    final issues = f?.result.issues.length ?? 0;
    final count = f?.result.items.length ?? 0;
    final refs = switch (f?.result.items) {
      final List<StationItem> st => st.fold<int>(0, (n, e) => n + e.refs.length),
      final List<BomItem> b => b.fold<int>(0, (n, e) => n + e.refs.length),
      _ => 0,
    };
    final summary = input.kind == InputKind.bom ? s.t('in_bom_parsed', {'n': count, 'r': refs}) : s.t('in_station_parsed', {'n': count, 'r': refs});
    final accent = _dragging || widget.highlight;

    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const _SheetIcon(size: 46),
            const SizedBox(width: 14),
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: c.accent),
              child: Text(
                '${input.index}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFFFFFFF), height: 1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      input.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _Chip(text: input.optional ? s.t('in_optional_chip') : s.t('in_required_chip'), color: input.optional ? c.textDim : c.accent),
                ],
              ),
            ),
            if (loaded) ...[GlyphIcon(Glyph.okCircle, size: 22, filled: true, color: c.pass), const SizedBox(width: 6)],
            Hoverable(
              tooltip: input.help,
              builder: (context, hover, _) => GlyphIcon(Glyph.help, size: 20, color: hover ? c.accent : c.textFaint),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 60, top: 4),
          child: Row(
            children: [
              GlyphIcon(Glyph.info, size: 14, color: c.textFaint),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  input.hint,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: c.textDim),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final Widget content;
    if (loaded) {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            decoration: BoxDecoration(
              color: c.panelAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                const _SheetIcon(size: 32),
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
                IconBtn(icon: Ic.arrowCounterClockwise, tooltip: s.t('step_replace'), onTap: () => importFile(context, state, input.kind)),
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
                GlyphIcon(issues == 0 ? Glyph.okCircle : Glyph.discrepancies, size: 17, filled: true, color: issues == 0 ? c.pass : c.substitute),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    issues == 0 ? summary : '$summary  ·  ${s.t('in_issues', {'n': issues})}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.text),
                  ),
                ),
              ],
            ),
          ),
          if (dropSupported) ...[
            const SizedBox(height: 10),
            Text(
              s.t('in_drop_replace'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: c.textFaint),
            ),
          ],
        ],
      );
    } else {
      content = Hoverable(
        onTap: () => importFile(context, state, input.kind),
        builder: (context, hover, _) => CustomPaint(
          painter: _DashedBorder(hover || _dragging ? c.accent : c.borderStrong),
          child: Container(
            constraints: const BoxConstraints(minHeight: 120),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: hover || _dragging ? c.accent.withValues(alpha: 0.05) : null, borderRadius: BorderRadius.circular(8)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DocIcon(color: input.tint, size: 44),
                const SizedBox(height: 10),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: s.t('in_click_choose')),
                      if (dropSupported) ...[
                        TextSpan(
                          text: s.t('in_or'),
                          style: TextStyle(color: c.textDim, fontWeight: FontWeight.w400),
                        ),
                        TextSpan(
                          text: s.t('in_drop_here'),
                          style: TextStyle(color: c.accent),
                        ),
                      ],
                    ],
                  ),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: hover ? c.accent : c.text),
                ),
                const SizedBox(height: 4),
                Text(s.t('in_formats'), style: TextStyle(fontSize: 12, color: c.textFaint)),
              ],
            ),
          ),
        ),
      );
    }

    final card = Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: accent
              ? c.accent.withValues(alpha: 0.8)
              : loaded
              ? c.pass.withValues(alpha: 0.5)
              : c.border,
          width: accent || loaded ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 16),
          if (widget.fill)
            Expanded(
              child: loaded ? Center(child: SingleChildScrollView(child: content)) : content,
            )
          else
            content,
        ],
      ),
    );
    if (!dropSupported) return card;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (detail) async {
        setState(() => _dragging = false);
        if (detail.files.isEmpty) return;
        final file = detail.files.first;
        final bytes = await file.readAsBytes();
        if (!context.mounted) return;
        await loadDropped(context, state, input.kind, file.name, bytes);
      },
      child: card,
    );
  }
}

/// Green spreadsheet tile.
class _SheetIcon extends StatelessWidget {
  const _SheetIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.pass, borderRadius: BorderRadius.circular(size * 0.22)),
      child: GlyphIcon(Glyph.stationA, size: size * 0.56, filled: true, color: const Color(0xFFFFFFFF)),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: c.dark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
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

Widget _flex(bool fill, Widget child) => fill ? Flexible(child: child) : child;

/// One file's check results as a two-column table.
class _CheckTable extends StatelessWidget {
  const _CheckTable({required this.input, required this.fill});

  final _Input input;

  /// Rows share the available height.
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final f = input.file;
    final ext = f == null ? '' : f.name.split('.').last.toLowerCase();
    final columns = f?.result.columns.entries.where((e) => e.key != 'unit').map((e) => e.value).toList() ?? const <String>[];
    final issues = f?.result.issues ?? const [];
    final refs = switch (f?.result.items) {
      final List<StationItem> st => st.fold<int>(0, (n, e) => n + e.refs.length),
      final List<BomItem> b => b.fold<int>(0, (n, e) => n + e.refs.length),
      _ => 0,
    };
    final bom = input.kind == InputKind.bom;
    final status = f == null
        ? Status.idle
        : issues.isNotEmpty || columns.length < 2
        ? Status.warning
        : Status.ok;
    final (statusText, statusColor) = switch (status) {
      Status.idle => (s.t('chk_not_imported'), c.textFaint),
      Status.ok => (s.t('chk_passed'), c.pass),
      _ => (s.t('in_issues', {'n': issues.length}), c.substitute),
    };
    final rows = [
      (s.t('row_file_name'), f?.name),
      (s.t('row_file_format'), f == null ? null : '.$ext'),
      (
        s.t(bom ? 'row_bom_count' : 'row_station_count'),
        f == null ? null : s.t(bom ? 'row_count_bom' : 'row_count_station', {'n': f.result.items.length, 'r': refs}),
      ),
      (s.t('row_sheets'), f == null ? null : s.t('chk_sheets_n', {'n': f.sheets})),
      (s.t('row_columns'), f == null ? null : columns.take(4).join(' / ')),
      (s.t('row_status'), f == null ? null : statusText),
    ];
    return Container(
      decoration: BoxDecoration(
        color: c.panelAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
            child: Row(
              children: [
                const _SheetIcon(size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    input.title,
                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.text),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.fromLTRB(8, 3, 10, 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: c.dark ? 0.16 : 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GlyphIcon(
                        status == Status.idle ? Glyph.circle : (status == Status.ok ? Glyph.okCircle : Glyph.discrepancies),
                        size: 14,
                        filled: status != Status.idle,
                        color: statusColor,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        statusText,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final (label, value) in rows)
            _flex(
              fill,
              Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.border.withValues(alpha: 0.7))),
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(label, style: TextStyle(fontSize: 12.5, color: c.textDim)),
                    ),
                    Expanded(
                      child: Text(
                        value ?? '—',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: value == null ? c.textFaint : c.text, fontWeight: value == null ? null : FontWeight.w500),
                      ),
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
            key: tourTargets.runButton,
            onTap: () => runCheck(context, state),
            builder: (context, hover, pressed) => Container(
              height: 48,
              padding: const EdgeInsets.only(left: 22, right: 12),
              decoration: BoxDecoration(
                color: !ready
                    ? c.accent.withValues(alpha: 0.55)
                    : pressed
                    ? c.accent.withValues(alpha: 0.85)
                    : hover
                    ? c.accent.withValues(alpha: 0.92)
                    : c.accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const GlyphIcon(Glyph.play, size: 18, filled: true, color: Color(0xFFFFFFFF)),
                  const SizedBox(width: 10),
                  Text(
                    s.t('btn_run'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFFFFFFFF)),
                  ),
                  const SizedBox(width: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: const Color(0x33FFFFFF), borderRadius: BorderRadius.circular(5)),
                    child: const Text('F5', style: TextStyle(fontSize: 12, color: Color(0xFFFFFFFF))),
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
