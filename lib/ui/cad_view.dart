/// CAD 坐标 page: control cards (coordinate file, unit, CAD format, build and
/// report), the searchable preview of the FAI CAD file, and the build checks
/// with file information.
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
import 'design.dart';
import 'dialogs.dart';
import 'icons.dart';
import 'lucide.dart';
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
    final pad = EdgeInsets.fromLTRB(widget.compact ? 16 : 24, 6, widget.compact ? 16 : 24, 0);

    final Widget body;
    (Widget, Widget)? wideBody;
    if (cad == null) {
      final noCoords = state.coords == null;
      body = DCard(
        child: EmptyState(
          icon: Ic.codeSimple,
          text: s.t(noCoords ? 'cad_need_coords_ribbon' : 'cad_need_check'),
          action: noCoords
              ? FlatButton(label: s.t('btn_coord'), primary: true, onTap: () => importFile(context, state, InputKind.coords))
              : FlatButton(
                  label: state.bom != null ? s.t('btn_run') : s.t('go_files'),
                  primary: state.bom != null,
                  onTap: () => state.bom != null ? runCheck(context, state) : state.setModule(Module.check),
                ),
        ),
      );
    } else {
      final t = state.settings.cad;
      final fileName = '${state.exportBaseName}_FAI.${t.fileExtension}';
      final q = _search.text.trim().toUpperCase();
      final indices = [
        for (var i = 0; i < cad.rows.length; i++)
          if (q.isEmpty || _matches(cad.rows[i], cad.cells[i], q)) i,
      ];
      final preview = DCard(
        key: tourTargets.cadPreview,
        clip: true,
        padding: const EdgeInsets.fromLTRB(12, 28, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.end,
                spacing: 24,
                runSpacing: 14,
                children: [
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName,
                          style: TextStyle(fontSize: 26, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.65, color: c.tx),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${state.coords!.name} · ${s.t(t.format == CadFormat.xlsx ? 'cad_type_xlsx' : 'cad_type_text')} · ${s.t('cad_rows', {'n': cad.rows.length})}',
                          style: TextStyle(fontSize: 13, height: 1.6, color: c.tx2),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 300,
                    child: PillSearch(controller: _search, hint: s.t('cad_search_hint'), flat: true, onChanged: (_) => setState(() {})),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: c.r(20),
                child: _CadGrid(cad: cad, indices: indices, v: _v, h: _h),
              ),
            ),
          ],
        ),
      );
      final aside = _Checks(state: state, cad: cad, fileName: fileName);
      wideBody = (preview, aside);
      if (isPhoneLayout(context)) return _phonePage(context, cad, indices, fileName);
      body = widget.compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: preview),
                const SizedBox(height: 20),
                SizedBox(height: 320, child: aside),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: preview),
                const SizedBox(width: 20),
                SizedBox(width: 380, child: aside),
              ],
            );
    }

    // Wide pages: the input cards over the preview on the left; the build
    // and report card over the checks on the right, sharing their edges.
    if (cad != null && !widget.compact && MediaQuery.sizeOf(context).width >= 1100) {
      return Padding(
        padding: EdgeInsets.fromLTRB(pad.left, pad.top, pad.right, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Controls(state: state, part: _ControlsPart.inputs),
                  const SizedBox(height: 16),
                  Expanded(child: wideBody!.$1),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 380,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Controls(state: state, part: _ControlsPart.actions),
                  const SizedBox(height: 16),
                  Expanded(child: wideBody.$2),
                ],
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Controls(state: state),
          const SizedBox(height: 20),
          Expanded(child: body),
        ],
      ),
    );
  }

  /// Phones: one scrolling column with the controls, the checks and the
  /// output rows as cards (every template column, labelled).
  Widget _phonePage(BuildContext context, CadResult cad, List<int> indices, String fileName) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final state = widget.state;
    final t = cad.template;
    final header = cad.header ?? [for (final f in t.fields) t.headerOf(f)];
    String fmt(Object o) => o is double ? o.toStringAsFixed(t.decimals) : '$o';
    final head = <Widget>[
      _Controls(state: state),
      const SizedBox(height: 14),
      _Checks(state: state, cad: cad, fileName: fileName, embedded: true),
      const SizedBox(height: 14),
      KeyedSubtree(
        key: tourTargets.cadPreview,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              fileName,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: c.tx),
            ),
            const SizedBox(height: 4),
            Text(s.t('cad_rows', {'n': cad.rows.length}), style: TextStyle(fontSize: 13, color: c.tx2)),
            const SizedBox(height: 10),
            PillSearch(controller: _search, hint: s.t('cad_search_hint'), onChanged: (_) => setState(() {})),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ];
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottomInset(context)),
      itemCount: head.length + indices.length,
      itemBuilder: (context, i) {
        if (i < head.length) return head[i];
        final k = indices[i - head.length];
        final cells = cad.cells[k];
        final row = cad.rows[k];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: DCard(
            radius: 18,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        cells.isEmpty ? row.placement.ref : fmt(cells.first),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.tx),
                      ),
                    ),
                    if (row.merged?.slot case final slot?) DotChip(text: slot, color: c.okTx, background: c.okTint),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    for (var j = 1; j < cells.length && j < header.length; j++)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${header[j]} ',
                              style: TextStyle(color: c.tx3),
                            ),
                            TextSpan(text: fmt(cells[j])),
                          ],
                        ),
                        style: TextStyle(fontSize: 12.5, color: c.tx, fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
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

/// Coordinate file, unit, CAD format, and the build / report actions.
/// Which cards [_Controls] builds: all of them, or (wide pages) the input
/// cards and the action card apart.
enum _ControlsPart { all, inputs, actions }

class _Controls extends StatelessWidget {
  const _Controls({required this.state, this.part = _ControlsPart.all});

  final AppState state;
  final _ControlsPart part;

  void _setUnit(BuildContext context, CoordUnit u) {
    try {
      state.setCoordUnit(u);
    } catch (e) {
      showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final f = state.coords;
    final t = state.settings.cad;
    final canBuild = state.report != null && f != null;
    final unit = state.settings.coordUnit;
    final unitText = f == null ? '' : (f.result.columns['unit'] ?? (unit == CoordUnit.auto ? 'mm' : unit.name));
    // Phones: no icon tiles, so the unit choices fit.
    final tight = MediaQuery.sizeOf(context).width < 600;
    Widget label(String text) => Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.tx2),
    );
    Widget card(Widget child, {EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 18, vertical: 14)}) =>
        DCard(radius: 22, padding: padding, child: child);

    final fileCard = KeyedSubtree(
      key: tourTargets.cadFile,
      child: card(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        Row(
          children: [
            GradientTile(
              icon: Lucide.fileText,
              colors: f == null ? GradientTile.gray : GradientTile.teal,
              glow: f == null ? GradientTile.grayGlow : GradientTile.tealGlow,
              size: 56,
              radius: 17,
              iconSize: 26,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label(s.t('btn_coord')),
                  const SizedBox(height: 3),
                  Text(
                    f?.name ?? s.t('cad_no_coords_yet'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.15, color: c.tx),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    f == null ? s.t('cad_pick_hint') : '${s.t('cad_n_refs', {'n': f.result.items.length})} · $unitText',
                    style: TextStyle(fontSize: 13, color: c.tx2),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                PillButton(
                  label: f == null ? s.t('cad_import_file') : s.t('btn_replace_file'),
                  icon: f == null ? Lucide.folderOpen : Lucide.refresh,
                  height: 32,
                  fontSize: 13,
                  iconSize: 14,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  onTap: () => importFile(context, state, InputKind.coords),
                ),
                if (f != null) ...[
                  const SizedBox(height: 6),
                  PillButton(
                    label: s.t('file_remove'),
                    icon: Lucide.trash,
                    height: 32,
                    fontSize: 13,
                    iconSize: 14,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    onTap: () => state.unload(InputKind.coords),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    final unitCard = card(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!tight) ...[const TintTile(icon: Lucide.ruler), const SizedBox(width: 16)],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label(s.t('grp_coord_import')),
              const SizedBox(height: 6),
              SegmentedPill<CoordUnit>(
                value: unit,
                options: [
                  for (final u in [CoordUnit.auto, CoordUnit.mm, CoordUnit.mil, CoordUnit.inch]) (u, s.t('unit_${u.name}')),
                ],
                onChanged: (u) => _setUnit(context, u),
              ),
            ],
          ),
        ],
      ),
    );

    final formatCard = card(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!tight) ...[const TintTile(icon: Lucide.grid), const SizedBox(width: 16)],
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label(s.t('btn_cad_template')),
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownSelect<CadFormat>(
                    value: t.format,
                    width: 168,
                    flat: true,
                    options: [(CadFormat.xlsx, s.t('fmt_fai_cad')), (CadFormat.text, s.t('fmt_text'))],
                    onChanged: (v) {
                      t.format = v;
                      state.updateCadTemplate(t);
                    },
                  ),
                  const SizedBox(width: 8),
                  Hoverable(
                    onTap: () => showCadTemplateDialog(context, state),
                    tooltip: s.t('cad_title'),
                    builder: (context, hover, _) => Container(
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: hover ? c.hover : null, shape: BoxShape.circle),
                      child: LucideIcon(Lucide.gear, size: 18, color: c.tx2),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );

    Widget action(Widget button, String caption) => Column(mainAxisSize: MainAxisSize.min, children: [button, const SizedBox(height: 6), Caption(caption)]);
    final actionsCard = card(
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(
            key: tourTargets.cadBuild,
            child: action(
              PillButton(
                label: s.t('btn_gen_cad'),
                icon: Lucide.exportArrow,
                kind: PillKind.primary,
                height: 48,
                fontSize: 16,
                padding: const EdgeInsets.symmetric(horizontal: 26),
                onTap: canBuild ? () => exportCad(context, state) : null,
              ),
              s.t('cap_gen_cad'),
            ),
          ),
          const SizedBox(width: 14),
          action(
            PillButton(
              label: s.t('btn_export_report'),
              icon: Lucide.fileCheck,
              height: 48,
              fontSize: 16,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              onTap: state.report == null ? null : () => exportReport(context, state),
            ),
            s.t('cap_report'),
          ),
        ],
      ),
    );

    if (part == _ControlsPart.actions) {
      // Top of the right column, as wide as the checks under it.
      return card(
        Row(
          children: [
            Expanded(
              child: KeyedSubtree(
                key: tourTargets.cadBuild,
                child: action(
                  PillButton(
                    label: s.t('btn_gen_cad'),
                    icon: Lucide.exportArrow,
                    kind: PillKind.primary,
                    height: 46,
                    fontSize: 15.5,
                    onTap: canBuild ? () => exportCad(context, state) : null,
                  ),
                  s.t('cap_gen_cad'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: action(
                PillButton(
                  label: s.t('btn_export_report'),
                  icon: Lucide.fileCheck,
                  height: 46,
                  fontSize: 15.5,
                  onTap: state.report == null ? null : () => exportReport(context, state),
                ),
                s.t('cap_report'),
              ),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      );
    }

    return LayoutBuilder(
      builder: (context, box) {
        // Cards keep their natural width, left aligned: one row when they
        // fit, the action card on its own row next, then everything stacks.
        Widget row(List<Widget> children) => IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(width: 12), children[i]],
            ],
          ),
        );
        final file = SizedBox(width: 380, child: fileCard);
        final formats = KeyedSubtree(key: tourTargets.cadFormat, child: row([unitCard, formatCard]));
        if (part == _ControlsPart.inputs) {
          // Narrow left columns: the file card above the unit and format cards.
          if (box.maxWidth < 1000) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                fileCard,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerLeft, child: SingleChildScrollView(scrollDirection: Axis.horizontal, child: formats)),
              ],
            );
          }
          // The file card takes the room the unit and format cards leave.
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: fileCard),
                const SizedBox(width: 12),
                unitCard,
                const SizedBox(width: 12),
                KeyedSubtree(key: tourTargets.cadFormat, child: formatCard),
              ],
            ),
          );
        }
        if (box.maxWidth >= 1340) {
          return Align(
            alignment: Alignment.centerLeft,
            child: row([file, unitCard, KeyedSubtree(key: tourTargets.cadFormat, child: formatCard), actionsCard]),
          );
        }
        if (box.maxWidth >= 1010) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row([file, unitCard, KeyedSubtree(key: tourTargets.cadFormat, child: formatCard)]),
              const SizedBox(height: 12),
              actionsCard,
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            fileCard,
            const SizedBox(height: 14),
            if (box.maxWidth < 600) ...[
              unitCard,
              const SizedBox(height: 14),
              KeyedSubtree(key: tourTargets.cadFormat, child: formatCard),
            ] else
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: formats),
            const SizedBox(height: 14),
            Align(alignment: Alignment.centerLeft, child: actionsCard),
          ],
        );
      },
    );
  }
}

/// The output columns, then footprint and the placement status (station
/// slot), in the design's rounded rows.
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

    final base = DefaultTextStyle.of(context).style;
    double measure(String text, {bool bold = false}) {
      final tp = TextPainter(
        text: TextSpan(
          text: text,
          style: base.copyWith(fontSize: 13, fontWeight: bold ? FontWeight.w600 : null, fontFeatures: const [FontFeature.tabularFigures()]),
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
                  final w = col < row.length ? measure(row[col], bold: col == 0) + (col == header.length - 1 ? 22 : 0) : 0.0;
                  return w > mx ? w : mx;
                }) +
                22)
            .clamp(44.0, 360.0),
    ];
    const numberCol = 44.0;
    Widget cell(Widget child, double w) => SizedBox(
      width: w,
      child: Padding(padding: const EdgeInsets.only(right: 10), child: child),
    );
    Widget text(String v, {bool head = false, Color? color, FontWeight? weight}) => Text(
      v,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: head ? 12 : 13,
        fontWeight: weight ?? (head ? FontWeight.w600 : FontWeight.w400),
        color: color ?? (head ? c.tx2 : c.tx),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        // Squeeze the widest column (normally Specification) so the status
        // column stays visible; the grid still scrolls when that is not enough.
        var total = widths.fold<double>(numberCol + 24, (a, b) => a + b);
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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    constraints: const BoxConstraints(minHeight: 38),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: c.solid, borderRadius: c.r(12)),
                    child: Row(
                      children: [cell(text('#', head: true), numberCol), for (var i = 0; i < header.length; i++) cell(text(header[i], head: true), widths[i])],
                    ),
                  ),
                  Expanded(
                    child: ThinScrollbar(
                      controller: v,
                      child: ListView.builder(
                        controller: v,
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        itemCount: indices.length,
                        itemExtent: m.touch ? 48 : 44,
                        itemBuilder: (context, k) {
                          final i = indices[k];
                          final row = rowText(i);
                          final merged = cad.rows[i].merged;
                          final ng = merged?.category == CheckCategory.ng;
                          final statusColor = merged == null ? c.tx3 : (ng ? c.ngTx : c.okTx);
                          final dotColor = merged == null ? c.tx3 : (ng ? c.ngSolid : c.okSolid);
                          return Hoverable(
                            cursor: SystemMouseCursors.basic,
                            builder: (context, hover, _) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(color: hover ? c.hover : null, borderRadius: c.r(12)),
                              child: Row(
                                children: [
                                  cell(text('${i + 1}', color: c.tx2), numberCol),
                                  for (var col = 0; col < header.length; col++)
                                    if (col == header.length - 1)
                                      cell(
                                        Row(
                                          children: [
                                            Container(
                                              width: 7,
                                              height: 7,
                                              decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                                            ),
                                            const SizedBox(width: 7),
                                            Flexible(
                                              child: text(row[col], color: statusColor, weight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                        widths[col],
                                      )
                                    else
                                      cell(text(row[col], weight: col == 0 ? FontWeight.w600 : null), widths[col]),
                                ],
                              ),
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
  const _Checks({required this.state, required this.cad, required this.fileName, this.embedded = false});

  final AppState state;
  final CadResult cad;
  final String fileName;

  /// Laid out inside a page that scrolls itself (phones).
  final bool embedded;

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
      (s.t('cad_no_coord', {'n': cad.noCoordRefs.length}), cad.noCoordRefs, c.ngTint, c.ngTx),
      (s.t('cad_side_mismatch', {'n': cad.sideMismatch.length}), cad.sideMismatch, c.ngTint, c.ngTx),
      (s.t('cad_unknown_side', {'n': cad.unknownSide.length}), cad.unknownSide, c.warnTint, c.warnTx),
      (s.t('cad_not_in_bom', {'n': cad.notInBomRefs.length}), cad.notInBomRefs, c.grayTint, c.tx2),
    ];
    final t = state.settings.cad;
    final unit = state.settings.coordUnit;
    final info = [
      (s.t('info_file'), fileName),
      (s.t('info_type'), s.t(t.format == CadFormat.xlsx ? 'cad_type_xlsx' : 'cad_type_text')),
      (s.t('info_count'), '${cad.rows.length}'),
      (s.t('info_unit'), coords.result.columns['unit'] ?? (unit == CoordUnit.auto ? 'mm' : unit.name)),
      (s.t('info_coords'), coords.name),
      (s.t('info_time'), formatTime(coords.loadedAt)),
    ];
    Widget title(Lucide icon, Color color, String text) => Row(
      children: [
        LucideIcon(icon, size: 22, color: color, stroke: 2.2),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: c.tx),
          ),
        ),
      ],
    );

    final cards = <Widget>[
      DCard(
        padding: EdgeInsets.all(embedded ? 20 : 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title(allGood ? Lucide.check : Lucide.alert, allGood ? c.okSolid : c.ngSolid, s.t('cad_checks')),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
              decoration: BoxDecoration(color: allGood ? c.okTint : c.ngTint, borderRadius: c.r(22)),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: allGood ? c.okSolid : c.ngSolid),
                    child: LucideIcon(allGood ? Lucide.check : Lucide.x, size: 20, color: const Color(0xFFFFFFFF), stroke: 2.6),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.t(allGood ? 'cad_all_good' : 'cad_has_problems'),
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: allGood ? c.okTx : c.ngTx),
                        ),
                        const SizedBox(height: 2),
                        Text(s.t('cad_matched_n', {'a': placed, 'b': expected}), style: TextStyle(fontSize: 13, color: c.tx2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            for (final (ok, label) in checks)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: ok ? c.okSolid : c.ngSolid),
                      child: LucideIcon(ok ? Lucide.check : Lucide.x, size: 12, color: const Color(0xFFFFFFFF), stroke: 3.2),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(label, style: TextStyle(fontSize: 14, color: c.tx)),
                    ),
                  ],
                ),
              ),
            for (final (head, refs, tint, color) in groups)
              if (refs.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  head,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.tx),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final r in refs.take(120)) DotChip(text: r, background: tint, color: color),
                    if (refs.length > 120) Text('+${refs.length - 120}', style: TextStyle(fontSize: 12, color: c.tx2)),
                  ],
                ),
              ],
          ],
        ),
      ),
      const SizedBox(height: 20),
      DCard(
        padding: const EdgeInsets.all(26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            title(Lucide.info, c.blue, s.t('info_title')),
            const SizedBox(height: 18),
            for (final (k, v) in info)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 84,
                      child: Text(k, style: TextStyle(fontSize: 14, height: 1.45, color: c.tx2)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(v, style: TextStyle(fontSize: 14, height: 1.45, color: c.tx)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
    if (embedded) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: cards);
    return ListView(padding: const EdgeInsets.only(bottom: 24), children: cards);
  }
}
