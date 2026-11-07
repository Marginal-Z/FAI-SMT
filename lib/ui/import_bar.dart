/// Top of the BOM check page: one compact card per input file (click or drop
/// a file on it) and the run / export / clear actions.
library;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/bom.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'design.dart';
import 'lucide.dart';
import 'theme.dart';
import 'tour.dart';
import 'widgets.dart';

class ImportBar extends StatelessWidget {
  const ImportBar({super.key, required this.state, this.actions = true});

  final AppState state;

  /// Include the run / export / clear card (the check page places it
  /// itself when the statistics row is shown).
  final bool actions;

  @override
  Widget build(BuildContext context) {
    final phone = isPhoneLayout(context);
    final cards = importCards(context, state);
    final actionsCard = ImportActions(state: state, compact: phone);
    return KeyedSubtree(
      key: tourTargets.fileChecks,
      child: LayoutBuilder(
        builder: (context, box) {
          const gap = 12.0;
          if (box.maxWidth >= 1080) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ImportCardsRow(state: state)),
                  if (actions) ...[const SizedBox(width: gap), SizedBox(width: 220, child: actionsCard)],
                ],
              ),
            );
          }
          if (box.maxWidth >= 640) {
            final w = (box.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final card in cards) SizedBox(width: w, child: card),
                if (actions) SizedBox(width: w, child: actionsCard),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[card, const SizedBox(height: 10)],
              if (actions) actionsCard,
            ],
          );
        },
      ),
    );
  }
}

/// The three import cards side by side, equal height (no layout builder, so
/// it can sit inside intrinsic-height rows).
class ImportCardsRow extends StatelessWidget {
  const ImportCardsRow({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final cards = importCards(context, state);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 12), Expanded(child: cards[i])],
        ],
      ),
    );
  }
}

/// BOM, station list A and station list B import cards.
List<Widget> importCards(BuildContext context, AppState state) {
  final s = Strings.of(context);
  final next = state.single == null ? InputKind.single : (state.bomA == null ? InputKind.a : null);
  return [
    _ImportCard(
      key: tourTargets.singleCard,
      state: state,
      kind: InputKind.single,
      title: s.t('in_single'),
      help: s.t('in_single_help'),
      file: state.single,
      optional: false,
      icon: Lucide.clipboardCheck,
      colors: GradientTile.blue,
      glow: GradientTile.blueGlow,
      next: next == InputKind.single,
    ),
    _ImportCard(
      key: tourTargets.aCard,
      state: state,
      kind: InputKind.a,
      title: s.t('in_a'),
      help: s.t('in_ab_help'),
      file: state.bomA,
      optional: false,
      icon: Lucide.fileText,
      colors: GradientTile.teal,
      glow: GradientTile.tealGlow,
      next: next == InputKind.a,
    ),
    _ImportCard(
      key: tourTargets.bCard,
      state: state,
      kind: InputKind.b,
      title: s.t('in_b'),
      help: s.t('in_ab_help'),
      file: state.bomB,
      optional: true,
      icon: Lucide.fileText,
      colors: GradientTile.orange,
      glow: GradientTile.orangeGlow,
      next: false,
    ),
  ];
}

class _ImportCard extends StatefulWidget {
  const _ImportCard({
    super.key,
    required this.state,
    required this.kind,
    required this.title,
    required this.help,
    required this.file,
    required this.optional,
    required this.icon,
    required this.colors,
    required this.glow,
    required this.next,
  });

  final AppState state;
  final InputKind kind;
  final String title;

  /// What the file must contain, shown on the icon.
  final String help;
  final LoadedFile? file;
  final bool optional;
  final Lucide icon;
  final (Color, Color) colors;
  final Color glow;

  /// The file to import next: outlined in blue.
  final bool next;

  @override
  State<_ImportCard> createState() => _ImportCardState();
}

class _ImportCardState extends State<_ImportCard> {
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final state = widget.state;
    final f = widget.file;
    final issues = f?.bom.warnings.length ?? 0;

    Widget iconButton(Lucide icon, String tip, VoidCallback onTap) => Hoverable(
      onTap: onTap,
      tooltip: tip,
      builder: (context, hover, _) => Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: hover ? c.hover : null, shape: BoxShape.circle),
        child: LucideIcon(icon, size: 15, color: c.tx2),
      ),
    );

    final status = f == null
        ? Text(
            dropSupported ? s.t('in_drop_or_click') : s.t('well_tap'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: c.blueTx),
          )
        : Hoverable(
            tooltip: _details(s, f.bom),
            cursor: SystemMouseCursors.help,
            builder: (context, hover, _) => Row(
            children: [
              LucideIcon(issues == 0 ? Lucide.check : Lucide.alert, size: 13, color: issues == 0 ? c.okTx : c.warnTx, stroke: 2.6),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  [
                    issues == 0 ? s.t('chk_passed') : s.t('in_issues', {'n': issues}),
                    s.t('card_count_bom', {'n': f.bom.parts.length}),
                    s.t('card_cols', {'n': f.bom.columns.where((c) => c.role != BomRole.serial).length}),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: issues == 0 ? c.okTx : c.warnTx),
                ),
              ),
            ],
          ),
          );

    final card = Hoverable(
      onTap: f == null ? () => importFile(context, state, widget.kind) : null,
      builder: (context, hover, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: _dragging || (hover && f == null) ? Color.alphaBlend(c.blueTint, c.card) : c.card,
          borderRadius: c.r(22),
          border: Border.all(color: widget.next || _dragging ? c.blue : (c.industrial ? c.lineStrong : const Color(0x00000000)), width: widget.next || _dragging || !c.industrial ? 1.5 : 1),
          boxShadow: c.shadowSm,
        ),
        child: Row(
          children: [
            Hoverable(
              tooltip: widget.help,
              cursor: SystemMouseCursors.help,
              builder: (context, hover, _) => GradientTile(icon: widget.icon, colors: widget.colors, glow: widget.glow, size: 42, radius: 13, iconSize: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: c.tx),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                        decoration: BoxDecoration(color: widget.optional ? c.grayTint : c.blueTint, borderRadius: c.r(999)),
                        child: Text(
                          widget.optional ? s.t('in_optional_chip') : s.t('in_required_chip'),
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, height: 1.5, color: widget.optional ? c.tx2 : c.blueTx),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    f?.name ?? s.t('well_formats'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.tx2),
                  ),
                  const SizedBox(height: 3),
                  status,
                ],
              ),
            ),
            if (f != null) ...[
              const SizedBox(width: 4),
              iconButton(Lucide.refresh, s.t('step_replace'), () => importFile(context, state, widget.kind)),
              iconButton(Lucide.trash, s.t('file_remove'), () => state.unload(widget.kind)),
            ] else
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: LucideIcon(Lucide.plus, size: 18, color: c.blue, stroke: 2.2),
              ),
          ],
        ),
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
        await loadDropped(context, state, widget.kind, file.name, bytes);
      },
      child: card,
    );
  }
}

/// Run Check (F5), Export Excel and Clear, stacked with room between them;
/// on phones one row with round icon buttons.
class ImportActions extends StatelessWidget {
  const ImportActions({super.key, required this.state, this.compact = false});

  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final ready = state.ready;
    final run = PillButton(
      key: tourTargets.runButton,
      label: s.t('btn_run'),
      icon: Lucide.play,
      kind: PillKind.primary,
      height: compact ? 40 : 44,
      fontSize: 15,
      iconSize: 15,
      padding: EdgeInsets.fromLTRB(16, 0, compact ? 16 : 10, 0),
      trailing: compact ? null : const KeyHint('F5'),
      onTap: ready ? () => runCheck(context, state) : null,
    );
    final export = PillButton(
      key: compact ? null : tourTargets.checkExport,
      label: s.t('btn_export_excel'),
      icon: Lucide.download,
      kind: PillKind.soft,
      height: 40,
      fontSize: 14,
      iconSize: 15,
      color: c.blueTx,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      onTap: state.report == null ? null : () => exportReport(context, state),
    );
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(color: c.card, borderRadius: c.r(22), boxShadow: c.shadowSm, border: c.cardBorder),
      child: compact
          // Phones: export and clear as round icon buttons beside Run.
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
              children: [
                Expanded(child: run),
                const SizedBox(width: 8),
                KeyedSubtree(
                  key: tourTargets.checkExport,
                  child: GlassButton(
                    icon: Lucide.download,
                    size: 40,
                    tooltip: s.t('btn_export_excel'),
                    onTap: state.report == null ? null : () => exportReport(context, state),
                  ),
                ),
                const SizedBox(width: 6),
                GlassButton(icon: Lucide.trash, size: 40, tooltip: s.t('btn_clear'), onTap: state.clearAll),
              ],
            ),
                const SizedBox(height: 10),
                AiSwitch(state: state),
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                run,
                const SizedBox(height: 10),
                AiSwitch(state: state),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: export),
                    const SizedBox(width: 6),
                    GlassButton(icon: Lucide.trash, size: 40, tooltip: s.t('btn_clear'), onTap: state.clearAll),
                  ],
                ),
              ],
            ),
    );
  }
}

/// The AI check switch with its state: off, not set up (opens the AI
/// settings), running, done with N findings, or failed.
class AiSwitch extends StatelessWidget {
  const AiSwitch({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final on = state.settings.aiEnabled;
    final configured = state.settings.ai.ready;
    final (String sub, Color color) = !configured
        ? (s.t('ai_not_set'), c.warnTx)
        : !on
        ? (s.t('ai_off'), c.tx3)
        : switch (state.aiStatus) {
            AiStatus.running => (s.t('ai_running'), c.blueTx),
            AiStatus.done => (s.t('ai_done', {'n': state.ai?.findings.length ?? 0}), c.okTx),
            AiStatus.failed => (s.t('ai_failed'), c.ngTx),
            AiStatus.idle => (s.t('ai_on'), c.tx2),
          };
    return Hoverable(
      key: tourTargets.aiSwitch,
      onTap: () => configured ? state.setAiEnabled(!on) : state.openSettings(SettingsSection.ai),
      tooltip: configured ? null : s.t('ai_setup_hint'),
      builder: (context, hover, _) => Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
        decoration: BoxDecoration(color: hover ? c.hover : c.well, borderRadius: c.r(14)),
        child: Row(
          children: [
            LucideIcon(Lucide.sparkles, size: 16, color: on && configured ? c.blueTx : c.tx2, stroke: 2),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(s.t('ai_check'), style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.tx)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: color)),
                ],
              ),
            ),
            if (state.aiStatus == AiStatus.running && on) ...[const Spinner(size: 14), const SizedBox(width: 8)],
            ToggleSwitch(value: on && configured),
          ],
        ),
      ),
    );
  }
}

/// Excel-style column letter of a 0-based index.
String _colName(int i) {
  var n = i + 1, out = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    out = String.fromCharCode(65 + r) + out;
    n = (n - 1) ~/ 26;
  }
  return out;
}

/// What was read from a BOM: the sheet and header row, the column found for
/// each role (by content, not only by header), and the warnings.
String _details(Strings s, BomDocument bom) {
  final lines = <String>[bom.headerRow < 0 ? s.t('det_sheet_nohead', {'sheet': bom.sheet}) : s.t('det_sheet', {'sheet': bom.sheet, 'row': bom.headerRow + 1})];
  for (final col in bom.columns) {
    if (col.role == BomRole.serial) continue;
    final role = col.role == BomRole.other ? s.t('role_other') : s.t('role_${col.role.name}');
    final head = col.header.isEmpty ? s.t('det_no_header') : col.header;
    lines.add('${_colName(col.index)} · $head → $role');
  }
  if (bom.warnings.isNotEmpty) {
    lines.add('');
    for (final w in bom.warnings.take(8)) {
      lines.add(s.t(w.code, {'row': w.row, 'detail': w.detail}));
    }
    if (bom.warnings.length > 8) lines.add(s.t('det_more', {'n': bom.warnings.length - 8}));
  }
  return lines.join('\n');
}
