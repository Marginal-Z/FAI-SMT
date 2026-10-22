/// Docked side panels: project files / summary and the row inspector.
library;

import 'package:flutter/widgets.dart';
import 'icons.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'theme.dart';
import 'widgets.dart';

class InspectorPanel extends StatelessWidget {
  const InspectorPanel({super.key, required this.state, this.onClose});

  final AppState state;

  /// Shown as a close button when the inspector floats over the workspace.
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final row = state.selected;
    return DockPanel(
      title: s.t('panel_inspector'),
      actions: [if (onClose != null) IconBtn(icon: Ic.x, onTap: onClose)],
      child: row == null
          ? Padding(padding: const EdgeInsets.all(12), child: Text(s.t('inspector_empty'), style: TextStyle(color: c.textFaint, fontSize: 12)))
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Text(row.partNo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(row.description, style: TextStyle(color: c.textDim, fontSize: 12.5)),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ResultBadge(
                    text: categoryLabel(s, row.category),
                    color: c.category(row.category),
                    icon: row.category == CheckCategory.pass ? IcBold.checkCircle : IcBold.info,
                  ),
                ),
                const SizedBox(height: 12),
                _Prop(label: s.t('col_bom_qty'), value: row.bomQty == null ? '-' : _fmt(row.bomQty!)),
                _Prop(label: s.t('col_smt_qty'), value: row.smtQty?.toString() ?? '-'),
                _Prop(label: s.t('col_smt_pn'), value: row.smtPartNos.isEmpty ? '-' : row.smtPartNos.join('\n')),
                _Prop(
                    label: s.t('col_side'),
                    value: row.sides.isEmpty ? '-' : (row.sides.toList()..sort((a, b) => a.index - b.index)).map((e) => s.t(e == StationSide.a ? 'side_a' : 'side_b')).join(' / ')),
                _Prop(label: s.t('col_slot'), value: row.slots.isEmpty ? '-' : row.slots.join(', ')),
                const SizedBox(height: 8),
                Text(s.t('col_reason'), style: TextStyle(color: c.textDim, fontSize: 12)),
                const SizedBox(height: 4),
                if (row.reasons.isEmpty) Text('-', style: TextStyle(color: c.textFaint)),
                for (final r in row.reasons)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: r.info ? c.panelAlt : c.ngSoft,
                      border: Border(left: BorderSide(color: r.info ? c.substitute : c.ng, width: 2)),
                    ),
                    child: Text(s.t(r.code, r.args), style: TextStyle(fontSize: 12.5, color: c.text)),
                  ),
              ],
            ),
    );
  }
}

String _fmt(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();

class _Prop extends StatelessWidget {
  const _Prop({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 112, child: Text(label, style: TextStyle(color: c.textDim, fontSize: 12))),
          Expanded(child: Text(value, style: TextStyle(fontSize: 12.5, color: c.text))),
        ],
      ),
    );
  }
}
