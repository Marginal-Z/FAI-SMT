/// CAD坐标 page: searchable preview of the FAI CAD file on the left, build
/// checks and file information on the right.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/exporters.dart';
import '../core/models.dart';
import '../core/parsers.dart';
import '../core/settings.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'check_view.dart';
import 'glyphs.dart';
import 'icons.dart';
import 'theme.dart';
import 'tour.dart';
import 'widgets.dart';

class CadView extends StatefulWidget {
  const CadView({super.key, required this.state, this.compact = false});

  final AppState state;

  /// Narrow screens put the checks under the preview.
  final bool compact;

  @override
  State<CadView> createState() => _CadViewState();
}

class _CadViewState extends State<CadView> {
  final _search = TextEditingController();
  final _v = ScrollController();
  final _h = ScrollController();

  @override
  void dispose() {
    _search.dispose();
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
      return EmptyState(
        icon: Ic.codeSimple,
        text: s.t(noCoords ? 'cad_need_coords_ribbon' : 'cad_need_check'),
        action: noCoords
            ? FlatButton(label: s.t('btn_coord'), primary: true, onTap: () => importFile(context, state, InputKind.coords))
            : FlatButton(
                label: state.bom != null ? s.t('btn_run') : s.t('go_files'),
                primary: state.bom != null,
                onTap: () => state.bom != null ? runCheck(context, state) : state.setModule(Module.files),
              ),
      );
    }
    final t = state.settings.cad;
    final fileName = '${state.exportBaseName}_FAI.${t.fileExtension}';
    final q = _search.text.trim().toUpperCase();
    final indices = [
      for (var i = 0; i < cad.rows.length; i++)
        if (q.isEmpty || _matches(cad.rows[i], cad.cells[i], q)) i,
    ];

    final preview = Container(
      key: tourTargets.cadPreview,
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: c.text),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${state.coords!.name}   ·   ${s.t(t.format == CadFormat.xlsx ? 'cad_type_xlsx' : 'cad_type_text')}   ·   ${s.t('cad_rows', {'n': cad.rows.length})}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: c.textDim),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 300,
                  child: TextInput(controller: _search, hint: s.t('cad_search_hint'), prefix: Ic.magnifyingGlass, onChanged: (_) => setState(() {})),
                ),
              ],
            ),
          ),
          Expanded(
            child: _CadGrid(cad: cad, indices: indices, v: _v, h: _h),
          ),
        ],
      ),
    );

    final side = _Checks(state: state, cad: cad, fileName: fileName);
    return Container(
      color: c.window,
      padding: const EdgeInsets.all(16),
      child: widget.compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: preview),
                const SizedBox(height: 12),
                SizedBox(height: 300, child: side),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: preview),
                const SizedBox(width: 16),
                SizedBox(width: 340, child: side),
              ],
            ),
    );
  }

  bool _matches(CadRow r, List<Object> cells, String q) {
    if (r.placement.ref.toUpperCase().contains(q)) return true;
    if (r.placement.footprint.toUpperCase().contains(q)) return true;
    for (final v in cells) {
      if ('$v'.toUpperCase().contains(q)) return true;
    }
    return false;
  }
}

/// Spreadsheet-like preview: the output columns, then footprint and the
/// placement status (station slot) for reference.
class _CadGrid extends StatelessWidget {
  const _CadGrid({required this.cad, required this.indices, required this.v, required this.h});

  final CadResult cad;
  final List<int> indices;
  final ScrollController v;
  final ScrollController h;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final m = Metrics.of(context);
    final t = cad.template;
    final header = [
      ...(cad.header ?? [for (final f in t.fields) t.headerOf(f)]),
      'Footprint',
      s.t('cad_status'),
    ];
    String fmt(Object o) => o is double ? o.toStringAsFixed(t.decimals) : '$o';
    List<String> rowText(int i) => [...cad.cells[i].map(fmt), cad.rows[i].placement.footprint, cad.rows[i].merged?.slot ?? '-'];

    const cellStyle = TextStyle(fontSize: 12.5);
    final base = DefaultTextStyle.of(context).style;
    double measure(String text, {bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: base.merge(cellStyle).copyWith(fontWeight: bold ? FontWeight.w600 : null),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      return tp.width;
    }

    final sample = indices.take(300).toList();
    final widths = [
      for (var col = 0; col < header.length; col++)
        (sample.fold<double>(measure(header[col], bold: true), (mx, i) {
                  final row = rowText(i);
                  final w = col < row.length ? measure(row[col]) + (col == header.length - 1 ? 22 : 0) : 0.0;
                  return w > mx ? w : mx;
                }) +
                24)
            .clamp(56.0, 360.0),
    ];
    Widget cell(Widget child, double w, {bool right = false}) =>
        Container(width: w, padding: const EdgeInsets.symmetric(horizontal: 10), alignment: right ? Alignment.centerRight : Alignment.centerLeft, child: child);
    Widget text(String v, {bool head = false, Color? color}) => Text(
      v,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 12.5, fontWeight: head ? FontWeight.w600 : FontWeight.w400, color: color ?? (head ? c.textDim : c.text)),
    );

    return LayoutBuilder(
      builder: (context, box) {
        // Squeeze the widest column (normally Specification) so the status
        // column stays visible; the grid still scrolls when that is not enough.
        var total = widths.fold<double>(52, (a, b) => a + b);
        if (total > box.maxWidth) {
          var widest = 0;
          for (var i = 1; i < widths.length; i++) {
            if (widths[i] > widths[widest]) widest = i;
          }
          final squeezed = (widths[widest] - (total - box.maxWidth)).clamp(180.0, widths[widest]);
          total -= widths[widest] - squeezed;
          widths[widest] = squeezed;
        }
        return ThinScrollbar(
          controller: h,
          horizontal: true,
          child: SingleChildScrollView(
            controller: h,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: total < box.maxWidth ? box.maxWidth : total,
              child: Column(
                children: [
                  Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: c.panelAlt,
                      border: Border(
                        top: BorderSide(color: c.border),
                        bottom: BorderSide(color: c.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        cell(text('#', head: true), 52, right: true),
                        for (var i = 0; i < header.length; i++) cell(text(header[i], head: true), widths[i]),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ThinScrollbar(
                      controller: v,
                      child: ListView.builder(
                        controller: v,
                        itemCount: indices.length,
                        itemExtent: m.touch ? 40 : 34,
                        itemBuilder: (context, k) {
                          final i = indices[k];
                          final row = rowText(i);
                          final merged = cad.rows[i].merged;
                          final ng = merged?.category == CheckCategory.ng;
                          return Container(
                            decoration: BoxDecoration(
                              color: k.isOdd ? c.panelAlt : c.panel,
                              border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.6))),
                            ),
                            child: Row(
                              children: [
                                cell(text('${i + 1}', color: c.textFaint), 52, right: true),
                                for (var col = 0; col < header.length; col++)
                                  if (col == header.length - 1)
                                    cell(
                                      Row(
                                        children: [
                                          GlyphIcon(
                                            merged == null ? Glyph.info : (ng ? Glyph.errorCircle : Glyph.okCircle),
                                            size: 15,
                                            filled: true,
                                            color: merged == null ? c.textFaint : (ng ? c.ng : c.pass),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(child: text(row[col], color: c.textDim)),
                                        ],
                                      ),
                                      widths[col],
                                    )
                                  else
                                    cell(text(row[col]), widths[col], right: cad.cells[i].length > col && cad.cells[i][col] is num),
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
        );
      },
    );
  }
}

/// Build checks and file information.
class _Checks extends StatelessWidget {
  const _Checks({required this.state, required this.cad, required this.fileName});

  final AppState state;
  final CadResult cad;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final coords = state.coords!;
    final issues = coords.result.issues;
    final dup = issues.where((i) => i.code == 'parse_dup_ref').length;
    final badXy = issues.where((i) => i.code == 'parse_bad_xy').length;
    final placed = cad.rows.length - cad.notInBomRefs.where((r) => cad.rows.any((x) => x.placement.ref == r)).length;
    final expected = placed + cad.noCoordRefs.length;
    final allGood = cad.noCoordRefs.isEmpty && cad.sideMismatch.isEmpty && cad.unknownSide.isEmpty;

    final checks = <(bool, String)>[
      (true, s.t('cad_chk_parsed')),
      (cad.noCoordRefs.isEmpty, cad.noCoordRefs.isEmpty ? s.t('cad_chk_matched') : s.t('cad_no_coord', {'n': cad.noCoordRefs.length})),
      (dup == 0, dup == 0 ? s.t('cad_chk_no_dup') : s.t('cad_chk_dup', {'n': dup})),
      (badXy == 0, badXy == 0 ? s.t('cad_chk_xy_ok') : s.t('cad_chk_xy_bad', {'n': badXy})),
      (cad.sideMismatch.isEmpty, cad.sideMismatch.isEmpty ? s.t('cad_chk_side_ok') : s.t('cad_side_mismatch', {'n': cad.sideMismatch.length})),
    ];
    final groups = [
      (s.t('cad_no_coord', {'n': cad.noCoordRefs.length}), cad.noCoordRefs, c.ng),
      (s.t('cad_side_mismatch', {'n': cad.sideMismatch.length}), cad.sideMismatch, c.ng),
      (s.t('cad_unknown_side', {'n': cad.unknownSide.length}), cad.unknownSide, c.substitute),
      (s.t('cad_not_in_bom', {'n': cad.notInBomRefs.length}), cad.notInBomRefs, c.textDim),
    ];
    final t = state.settings.cad;
    final info = [
      (s.t('info_file'), fileName),
      (s.t('info_type'), s.t(t.format == CadFormat.xlsx ? 'cad_type_xlsx' : 'cad_type_text')),
      (s.t('info_count'), '${cad.rows.length}'),
      (s.t('info_unit'), t.unit == CoordUnit.auto ? 'mm' : t.unit.name),
      (s.t('info_coords'), coords.name),
      (s.t('info_time'), formatTime(coords.loadedAt)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            children: [
              GlyphIcon(allGood ? Glyph.okCircle : Glyph.discrepancies, size: 20, filled: true, color: allGood ? c.pass : c.ng),
              const SizedBox(width: 8),
              Text(
                s.t('cad_checks'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (allGood ? c.pass : c.ng).withValues(alpha: c.dark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: allGood ? c.pass : c.ng),
                  child: GlyphIcon(allGood ? Glyph.okCircle : Glyph.errorCircle, size: 22, filled: true, color: const Color(0xFFFFFFFF)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.t(allGood ? 'cad_all_good' : 'cad_has_problems'),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text),
                      ),
                      const SizedBox(height: 2),
                      Text(s.t('cad_matched_n', {'a': placed, 'b': expected}), style: TextStyle(fontSize: 12.5, color: c.textDim)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          for (final (ok, label) in checks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  GlyphIcon(ok ? Glyph.okCircle : Glyph.errorCircle, size: 18, filled: true, color: ok ? c.pass : c.ng),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(label, style: TextStyle(fontSize: 13, color: c.text)),
                  ),
                ],
              ),
            ),
          for (final (title, refs, color) in groups)
            if (refs.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                title,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.textDim),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final r in refs.take(120)) RefChip(text: r, color: color, soft: color.withValues(alpha: 0.12)),
                  if (refs.length > 120) Text('+${refs.length - 120}', style: TextStyle(fontSize: 12, color: c.textDim)),
                ],
              ),
            ],
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
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
                    GlyphIcon(Glyph.info, size: 16, filled: true, color: c.accent),
                    const SizedBox(width: 8),
                    Text(
                      s.t('info_title'),
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: c.text),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                for (final (k, v) in info)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 76,
                          child: Text(k, style: TextStyle(fontSize: 12.5, color: c.textDim)),
                        ),
                        Expanded(
                          child: Text(v, style: TextStyle(fontSize: 12.5, color: c.text)),
                        ),
                      ],
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
