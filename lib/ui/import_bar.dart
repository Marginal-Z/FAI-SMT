/// Top of the BOM check page: one compact card per input file (click or drop
/// a file on it) and the run / export / clear actions.
library;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'design.dart';
import 'lucide.dart';
import 'theme.dart';
import 'tour.dart';
import 'widgets.dart';

class ImportBar extends StatelessWidget {
  const ImportBar({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final phone = isPhoneLayout(context);
    final next = state.bom == null ? InputKind.bom : (state.stationA == null && state.stationB == null ? InputKind.stationA : null);
    final cards = [
      _ImportCard(
        key: tourTargets.bomCard,
        state: state,
        kind: InputKind.bom,
        title: s.t('in_bom_title'),
        help: s.t('in_bom_help'),
        file: state.bom,
        optional: false,
        icon: Lucide.clipboardCheck,
        colors: GradientTile.blue,
        glow: GradientTile.blueGlow,
        next: next == InputKind.bom,
      ),
      _ImportCard(
        key: tourTargets.stationCard,
        state: state,
        kind: InputKind.stationA,
        title: s.t('btn_station_a'),
        help: s.t('in_station_help'),
        file: state.stationA,
        optional: false,
        icon: Lucide.fileText,
        colors: GradientTile.teal,
        glow: GradientTile.tealGlow,
        next: next == InputKind.stationA,
      ),
      _ImportCard(
        state: state,
        kind: InputKind.stationB,
        title: s.t('btn_station_b'),
        help: s.t('in_station_help'),
        file: state.stationB,
        optional: true,
        icon: Lucide.fileText,
        colors: GradientTile.orange,
        glow: GradientTile.orangeGlow,
        next: false,
      ),
    ];
    final actions = _Actions(state: state, compact: phone);
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
                  for (final card in cards) ...[Expanded(child: card), const SizedBox(width: gap)],
                  SizedBox(width: 250, child: actions),
                ],
              ),
            );
          }
          if (box.maxWidth >= 640) {
            final w = (box.maxWidth - gap) / 2;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [for (final card in cards) SizedBox(width: w, child: card), SizedBox(width: w, child: actions)],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final card in cards) ...[card, const SizedBox(height: 10)],
              actions,
            ],
          );
        },
      ),
    );
  }
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
  final LoadedFile<Object?>? file;
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
    final issues = f?.result.issues.length ?? 0;
    final bom = widget.kind == InputKind.bom;

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
        : Row(
            children: [
              LucideIcon(issues == 0 ? Lucide.check : Lucide.alert, size: 13, color: issues == 0 ? c.okTx : c.warnTx, stroke: 2.6),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  [
                    issues == 0 ? s.t('chk_passed') : s.t('in_issues', {'n': issues}),
                    s.t(bom ? 'card_count_bom' : 'card_count_station', {'n': f.result.items.length}),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: issues == 0 ? c.okTx : c.warnTx),
                ),
              ),
            ],
          );

    final card = Hoverable(
      onTap: f == null ? () => importFile(context, state, widget.kind) : null,
      builder: (context, hover, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
        decoration: BoxDecoration(
          color: _dragging || (hover && f == null) ? Color.alphaBlend(c.blueTint, c.card) : c.card,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: widget.next || _dragging ? c.blue : const Color(0x00000000), width: 1.5),
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
                        decoration: BoxDecoration(color: widget.optional ? c.grayTint : c.blueTint, borderRadius: BorderRadius.circular(999)),
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

/// Run Check (F5), Export Excel and Clear.
class _Actions extends StatelessWidget {
  const _Actions({required this.state, required this.compact});

  final AppState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final ready = state.bom != null && (state.stationA != null || state.stationB != null);
    final run = PillButton(
      key: tourTargets.runButton,
      label: s.t('btn_run'),
      icon: Lucide.play,
      kind: PillKind.primary,
      height: 40,
      fontSize: 14.5,
      iconSize: 15,
      padding: EdgeInsets.fromLTRB(16, 0, compact ? 16 : 8, 0),
      trailing: compact ? null : const KeyHint('F5'),
      onTap: ready ? () => runCheck(context, state) : null,
    );
    final export = PillButton(
      key: tourTargets.checkExport,
      label: s.t('btn_export_excel'),
      icon: Lucide.download,
      kind: PillKind.soft,
      height: 36,
      fontSize: 13.5,
      iconSize: 14,
      color: c.blueTx,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      onTap: state.report == null ? null : () => exportReport(context, state),
    );
    final clear = PillButton(
      label: s.t('btn_clear'),
      icon: Lucide.trash,
      kind: PillKind.ghost,
      height: 36,
      fontSize: 13.5,
      iconSize: 14,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      onTap: state.clearAll,
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(22), boxShadow: c.shadowSm),
      child: compact
          ? Row(
              children: [
                Expanded(child: run),
                const SizedBox(width: 8),
                export,
                clear,
              ],
            )
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                run,
                const SizedBox(height: 6),
                Wrap(alignment: WrapAlignment.center, spacing: 2, runSpacing: 4, children: [export, clear]),
              ],
            ),
    );
  }
}
