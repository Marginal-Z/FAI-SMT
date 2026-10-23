/// Preview of the generated FAI CAD file with build checks.
library;

import 'package:flutter/widgets.dart';

import 'icons.dart';

import '../app_state.dart';
import '../core/exporters.dart';
import '../core/settings.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'dialogs.dart';
import 'check_view.dart';
import 'theme.dart';
import 'widgets.dart';

class CadView extends StatefulWidget {
  const CadView({super.key, required this.state, this.compact = false});

  final AppState state;

  /// Narrow screens put the build checks under the preview.
  final bool compact;

  @override
  State<CadView> createState() => _CadViewState();
}

class _CadViewState extends State<CadView> {
  final _v = ScrollController();
  final _h = ScrollController();

  @override
  void dispose() {
    _v.dispose();
    _h.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final state = widget.state;
    final cad = state.cad;
    if (cad == null) {
      final noCoords = state.coords == null;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PageHeader(title: s.t('mod_cad')),
        Expanded(
          child: EmptyState(
            icon: Ic.codeSimple,
            text: s.t(noCoords ? 'cad_need_coords_ribbon' : 'cad_need_check'),
            action: noCoords
                ? null
                : FlatButton(
                    label: state.bom != null ? s.t('btn_run') : s.t('go_files'),
                    primary: state.bom != null,
                    onTap: () => state.bom != null ? runCheck(context, state) : state.setModule(Module.files),
                  ),
          ),
        ),
      ]);
    }
    final lines = cad.previewLines();
    final t = state.settings.cad;
    final mono = TextStyle(fontFamily: monoFontFamily, fontFamilyFallback: uiFontFallback, fontSize: 12.5, height: 1.5, color: c.text);
    final gutter = '${lines.length}'.length * 8.0 + 18;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(
          title: '${state.exportBaseName}_FAI.${t.fileExtension}',
          subtitle: '${state.coords!.name}  ·  ${s.t('page_cad_sub', {'n': cad.rows.length})}',
        ),
        Expanded(
          child: Flex(
            direction: widget.compact ? Axis.vertical : Axis.horizontal,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (t.format == CadFormat.xlsx)
                Expanded(
                  child: _CadGrid(cad: cad, v: _v, h: _h),
                )
              else
                Expanded(
                  child: Container(
                    color: c.input,
                    child: ThinScrollbar(
                      controller: _v,
                      child: SingleChildScrollView(
                        controller: _v,
                        child: ThinScrollbar(
                          controller: _h,
                          horizontal: true,
                          child: SingleChildScrollView(
                            controller: _h,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(
                                  width: gutter,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      for (var i = 0; i < lines.length; i++)
                                        Padding(
                                          padding: const EdgeInsets.only(right: 10),
                                          child: Text('${i + 1}', style: mono.copyWith(color: c.textFaint)),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(width: 1, color: c.border),
                                const SizedBox(width: 10),
                                _CadLines(lines: lines, style: mono, headerColor: t.writeHeader ? c.accent : null),
                                const SizedBox(width: 24),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.compact) const HDivider() else const VDivider(),
              if (widget.compact) SizedBox(height: 220, child: _Checks(state: state)) else SizedBox(width: 300, child: _Checks(state: state)),
            ],
          ),
        ),
      ],
    );
  }
}

/// Spreadsheet-like preview of the workbook that will be written.
class _CadGrid extends StatelessWidget {
  const _CadGrid({required this.cad, required this.v, required this.h});

  final CadResult cad;
  final ScrollController v;
  final ScrollController h;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final t = cad.template;
    final header = cad.header ?? [for (final f in t.fields) t.headerOf(f)];
    String fmt(Object o) => o is double ? o.toStringAsFixed(t.decimals) : '$o';
    const cellStyle = TextStyle(fontSize: 12.5);
    final base = DefaultTextStyle.of(context).style;
    double measure(String text, {bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: base.merge(cellStyle).copyWith(fontWeight: bold ? FontWeight.w600 : null)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return tp.width;
    }

    final widths = [
      for (var i = 0; i < header.length; i++)
        (cad.cells.take(300).fold<double>(measure(header[i], bold: true), (m, r) {
                  if (i >= r.length) return m;
                  final w = measure(fmt(r[i]));
                  return w > m ? w : m;
                }) +
                20)
            .clamp(48.0, 380.0)
    ];
    final total = widths.fold<double>(48, (a, b) => a + b);
    Widget cell(String text, double w, {bool head = false, bool num = false}) => Container(
      width: w,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      alignment: num ? Alignment.centerRight : Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: c.border)),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12.5, fontWeight: head ? FontWeight.w600 : FontWeight.w400, color: head ? c.textDim : c.text),
      ),
    );
    return Container(
      color: c.input,
      child: ThinScrollbar(
        controller: h,
        horizontal: true,
        child: SingleChildScrollView(
          controller: h,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: total,
            child: Column(
              children: [
                Container(
                  height: 30,
                  decoration: BoxDecoration(
                    color: c.panelAlt,
                    border: Border(bottom: BorderSide(color: c.borderStrong)),
                  ),
                  child: Row(
                    children: [cell('', 48, head: true), for (var i = 0; i < header.length; i++) cell(header[i], widths[i], head: true)],
                  ),
                ),
                Expanded(
                  child: ThinScrollbar(
                    controller: v,
                    child: ListView.builder(
                      controller: v,
                      itemCount: cad.cells.length,
                      itemExtent: 26,
                      itemBuilder: (context, r) {
                        final row = cad.cells[r];
                        return Container(
                          decoration: BoxDecoration(
                            color: r.isOdd ? c.panelAlt : null,
                            border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.6))),
                          ),
                          child: Row(
                            children: [
                              cell('${r + 1}', 48, num: true),
                              for (var i = 0; i < header.length && i < row.length; i++) cell(fmt(row[i]), widths[i], num: row[i] is num),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Plain text lines; the header line is tinted.
class _CadLines extends StatelessWidget {
  const _CadLines({required this.lines, required this.style, this.headerColor});

  final List<String> lines;
  final TextStyle style;
  final Color? headerColor;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (var i = 0; i < lines.length; i++)
        Text(
          lines[i].replaceAll('\t', '    '),
          style: i == 0 && headerColor != null ? style.copyWith(color: headerColor, fontWeight: FontWeight.w600) : style,
        ),
    ],
  );
}

class _Checks extends StatelessWidget {
  const _Checks({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final cad = state.cad!;
    final groups = [
      (s.t('cad_no_coord', {'n': cad.noCoordRefs.length}), cad.noCoordRefs, c.ng),
      (s.t('cad_not_in_bom', {'n': cad.notInBomRefs.length}), cad.notInBomRefs, c.substitute),
      (s.t('cad_unknown_side', {'n': cad.unknownSide.length}), cad.unknownSide, c.substitute),
      (s.t('cad_side_mismatch', {'n': cad.sideMismatch.length}), cad.sideMismatch, c.ng),
    ];
    final allGood = groups.every((g) => g.$2.isEmpty);
    return DockPanel(
      title: s.t('cad_checks'),
      child: ListView(
        padding: const EdgeInsets.all(10),
        children: [
          if (allGood)
            Row(
              children: [
                Icon(Ic.checkCircle, size: 16, color: c.pass),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(s.t('cad_all_good'), style: TextStyle(color: c.text)),
                ),
              ],
            ),
          for (final (title, refs, color) in groups)
            if (refs.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 6),
                child: Row(
                  children: [
                    Icon(Ic.warning, size: 15, color: color),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [for (final r in refs.take(300)) RefChip(text: r, color: color, soft: color.withValues(alpha: 0.12))],
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}
