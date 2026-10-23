/// Part library page (Settings → Part library): every model the navigator
/// can draw, grouped by family, with a 3D preview, and the user's own model
/// rules. Also the model picker opened from a part in the navigator.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/footprints.dart';
import '../core/part_library.dart';
import '../l10n/strings.dart';
import 'board_view.dart';
import 'glyphs.dart';
import 'icons.dart';
import 'part_render.dart';
import 'theme.dart';
import 'tour.dart';
import 'widgets.dart';

/// Families shown as filters, in legend order.
const libraryGroups = [
  (PartKind.resistor, 'type_resistor'),
  (PartKind.capacitor, 'type_capacitor'),
  (PartKind.inductor, 'type_inductor'),
  (PartKind.diode, 'type_diode'),
  (PartKind.led, 'type_led'),
  (PartKind.transistor, 'type_transistor'),
  (PartKind.ic, 'type_ic'),
  (PartKind.crystal, 'type_crystal'),
  (PartKind.connector, 'type_connector'),
  (PartKind.electromech, 'type_electromech'),
  (PartKind.mechanical, 'type_mechanical'),
  (PartKind.testPoint, 'type_testpoint'),
  (PartKind.fiducial, 'type_fiducial'),
  (PartKind.other, 'type_others'),
];

String fieldLabel(Strings s, String field) => s.t(switch (field) {
  'ref' => 'rule_field_ref',
  'partNo' => 'rule_field_pn',
  _ => 'rule_field_fp',
});

/// Searchable, filterable grid of models; [onPick] makes cards selectable.
class _ModelGrid extends StatefulWidget {
  const _ModelGrid({required this.state, this.onPick, this.selected});

  final AppState state;
  final ValueChanged<PartModel>? onPick;
  final String? selected;

  @override
  State<_ModelGrid> createState() => _ModelGridState();
}

class _ModelGridState extends State<_ModelGrid> {
  final _search = TextEditingController();
  PartKind? _group;
  bool _real = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final palette = PartPalette(widget.state.settings.board);
    final q = _search.text.trim().toUpperCase();
    final models = [
      for (final m in partLibrary)
        if ((_group == null || m.kind == _group) &&
            (q.isEmpty || s.t('pm_${m.id}').toUpperCase().contains(q) || m.keywords.toUpperCase().contains(q) || m.id.toUpperCase().contains(q)))
          m,
    ];
    final board = palette.board ?? (_real ? PartPalette.solderMask : c.panelAlt);
    Widget chip(String label, bool active, VoidCallback onTap) => Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active
              ? c.accent.withValues(alpha: c.dark ? 0.2 : 0.1)
              : hover
              ? c.hover
              : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: active ? c.accent.withValues(alpha: 0.6) : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: active ? c.accent : c.textDim, fontWeight: active ? FontWeight.w600 : null),
        ),
      ),
    );
    final grid = LayoutBuilder(
      builder: (context, box) {
        final cols = (box.maxWidth / 190).floor().clamp(2, 8);
        final w = (box.maxWidth - (cols - 1) * 12) / cols;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final m in models)
              SizedBox(
                width: w,
                child: Hoverable(
                  onTap: widget.onPick == null ? null : () => widget.onPick!(m),
                  cursor: widget.onPick == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
                  builder: (context, hover, _) {
                    final active = m.id == widget.selected;
                    return Container(
                      decoration: BoxDecoration(
                        color: c.well,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: active
                              ? c.blue
                              : hover && widget.onPick != null
                              ? c.lineStrong
                              : c.line,
                          width: active ? 1.6 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
                            child: SizedBox(
                              height: 112,
                              child: PartPreview(model: m, body: _real ? Color(m.realColor) : palette.body(m.kind), real: _real, board: board),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  s.t('pm_${m.id}'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: active ? c.accent : c.text),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  s.t('lib_size', {'w': _mm(m.width), 'h': _mm(m.height), 'z': _mm(m.bodyHeight)}),
                                  style: TextStyle(fontSize: 11, color: c.textDim),
                                ),
                                if (m.keywords.isNotEmpty)
                                  Text(
                                    m.keywords,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 10.5, color: c.textFaint),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: TextInput(controller: _search, hint: s.t('lib_search'), prefix: Ic.magnifyingGlass, onChanged: (_) => setState(() {})),
            ),
            const SizedBox(width: 12),
            Segmented<bool>(value: _real, options: [(true, s.t('color_real')), (false, s.t('color_type'))], onChanged: (v) => setState(() => _real = v)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            chip(s.t('opt_all'), _group == null, () => setState(() => _group = null)),
            for (final (kind, key) in libraryGroups)
              if (partLibrary.any((m) => m.kind == kind)) chip(s.t(key), _group == kind, () => setState(() => _group = kind)),
          ],
        ),
        const SizedBox(height: 14),
        if (models.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              s.t('empty_filter'),
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textFaint),
            ),
          )
        else
          grid,
      ],
    );
  }
}

String _mm(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(v * 10 == (v * 10).roundToDouble() ? 1 : 2);

/// Settings → Part library.
class PartLibraryPage extends StatelessWidget {
  const PartLibraryPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final rules = state.settings.partRules;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.t('set_library'),
            style: TextStyle(fontSize: 26, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: c.tx),
          ),
          const SizedBox(height: 4),
          Text(s.t('lib_intro', {'n': partLibrary.length}), style: TextStyle(fontSize: 14, color: c.tx2, height: 1.5)),
          const SizedBox(height: 20),
          SurfaceCard(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  s.t('lib_rules'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text),
                ),
                const SizedBox(height: 4),
                Text(s.t('lib_rules_hint'), style: TextStyle(fontSize: 12, color: c.textDim)),
                const SizedBox(height: 10),
                if (rules.isEmpty)
                  Text(s.t('lib_rules_empty'), style: TextStyle(fontSize: 12.5, color: c.textFaint))
                else
                  for (final r in rules)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        border: Border(top: BorderSide(color: c.border.withValues(alpha: 0.6))),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 70,
                            child: Text(fieldLabel(s, r.field), style: TextStyle(fontSize: 12.5, color: c.textDim)),
                          ),
                          Expanded(
                            child: Text(
                              r.value,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: c.text, fontFamily: monoFontFamily),
                            ),
                          ),
                          GlyphIcon(Glyph.chevronRight, size: 14, color: c.textFaint),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 200,
                            child: Text(
                              s.t('pm_${r.model}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.text),
                            ),
                          ),
                          IconBtn(icon: Ic.x, tooltip: s.t('lib_rule_remove'), onTap: () => state.setPartRule(r.field, r.value, null)),
                        ],
                      ),
                    ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SurfaceCard(
            key: tourTargets.library,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
            child: _ModelGrid(state: state),
          ),
        ],
      ),
    );
  }
}

/// Lets the user pick the model for a part shown in the navigator. The rule
/// can apply to this designator, its part number or its footprint.
Future<void> showPartModelPicker(
  BuildContext context,
  AppState state, {
  required String ref,
  required String partNo,
  required String footprint,
  required String current,
}) {
  final s = Strings.of(context);
  return showAppDialog<void>(
    context,
    title: s.t('lib_pick_title', {'ref': ref}),
    width: 880,
    body: (ctx) => _PickerBody(state: state, ref: ref, partNo: partNo, footprint: footprint, current: current),
  );
}

class _PickerBody extends StatefulWidget {
  const _PickerBody({required this.state, required this.ref, required this.partNo, required this.footprint, required this.current});

  final AppState state;
  final String ref;
  final String partNo;
  final String footprint;
  final String current;

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  late String _field = widget.footprint.isNotEmpty ? 'footprint' : (widget.partNo.isNotEmpty ? 'partNo' : 'ref');

  String get _value => switch (_field) {
    'footprint' => widget.footprint,
    'partNo' => widget.partNo,
    _ => widget.ref,
  };

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final rules = widget.state.settings.partRules;
    final existing = rules
        .where(
          (r) =>
              (r.field == 'ref' && r.value == widget.ref) ||
              (r.field == 'partNo' && r.value == widget.partNo) ||
              (r.field == 'footprint' && r.value == widget.footprint),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(s.t('lib_apply_to'), style: TextStyle(fontSize: 13, color: c.textDim)),
            const SizedBox(width: 10),
            Segmented<String>(
              value: _field,
              options: [
                ('ref', '${s.t('rule_field_ref')} ${widget.ref}'),
                if (widget.partNo.isNotEmpty) ('partNo', s.t('rule_field_pn')),
                if (widget.footprint.isNotEmpty) ('footprint', s.t('rule_field_fp')),
              ],
              onChanged: (v) => setState(() => _field = v),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: c.text, fontFamily: monoFontFamily),
              ),
            ),
            if (existing.isNotEmpty)
              FlatButton(
                label: s.t('lib_reset_auto'),
                compact: true,
                onTap: () {
                  for (final r in existing) {
                    widget.state.setPartRule(r.field, r.value, null);
                  }
                  Navigator.of(context).pop();
                },
              ),
          ],
        ),
        const SizedBox(height: 12),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.62),
          child: SingleChildScrollView(
            child: _ModelGrid(
              state: widget.state,
              selected: widget.current,
              onPick: (m) {
                widget.state.setPartRule(_field, _value, m.id);
                Navigator.of(context).pop();
              },
            ),
          ),
        ),
      ],
    );
  }
}
