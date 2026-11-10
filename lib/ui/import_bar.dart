/// Top of the BOM check page: one compact card per input file (click or drop
/// a file on it) and the run / export / clear actions.
library;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/bom.dart';
import '../core/settings.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'design.dart';
import 'lucide.dart';
import 'local_model_controls.dart';
import 'theme.dart';
import 'tour.dart';
import 'widgets.dart';

class ImportBar extends StatefulWidget {
  const ImportBar({
    super.key,
    required this.state,
    this.actions = true,
    this.compact = false,
  });
  final AppState state;
  final bool actions;
  final bool compact;
  @override
  State<ImportBar> createState() => _ImportBarState();
}

class _ImportBarState extends State<ImportBar> {
  bool _showFiles = false;
  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final s = Strings.of(context);
    final c = AppTheme.of(context);
    final phone = widget.compact || isPhoneLayout(context);
    final running = state.localBusy || state.cloudRunning;
    final collapsed = phone && (state.report != null || running) && !_showFiles;
    final files = [
      state.single,
      state.bomA,
      state.bomB,
    ].whereType<LoadedFile>().toList();
    final issues = files.fold<int>(
      0,
      (n, file) => n + file.bom.warnings.length,
    );
    final cards = importCards(context, state);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        KeyedSubtree(
          key: tourTargets.fileChecks,
          child: collapsed
              ? Hoverable(
                  key: const ValueKey('input-files-summary'),
                  onTap: () => setState(() => _showFiles = true),
                  tooltip: s.t('files_expand'),
                  builder: (context, hover, _) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    constraints: const BoxConstraints(minHeight: 48),
                    decoration: BoxDecoration(
                      color: hover ? c.hover : c.card,
                      borderRadius: c.r(14),
                      border: c.cardBorder,
                    ),
                    child: Row(
                      children: [
                        LucideIcon(Lucide.fileCheck, size: 18, color: c.blueTx),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.t('files_loaded_brief', {'n': files.length}) +
                                    (issues == 0
                                        ? ''
                                        : ' · ${s.t('in_issues', {'n': issues})}'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: c.tx,
                                ),
                              ),
                              Text(
                                files.map((f) => f.name).join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11.5, color: c.tx2),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        LucideIcon(Lucide.chevronDown, size: 16, color: c.tx2),
                      ],
                    ),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, box) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (box.maxWidth >= 760)
                        ImportCardsRow(state: state)
                      else
                        for (var i = 0; i < cards.length; i++) ...[
                          if (i > 0) const SizedBox(height: 8),
                          cards[i],
                        ],
                      if (phone && (state.report != null || running))
                        Align(
                          alignment: Alignment.centerRight,
                          child: PillButton(
                            label: s.t('files_collapse'),
                            kind: PillKind.ghost,
                            height: 44,
                            onTap: () => setState(() => _showFiles = false),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        if (widget.actions) ...[
          const SizedBox(height: 8),
          ImportActions(state: state, compact: phone),
        ],
      ],
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
        children: [for (final card in cards) Expanded(child: card)],
      ),
    );
  }
}

/// BOM, station list A and station list B import cards.
List<Widget> importCards(BuildContext context, AppState state) {
  final s = Strings.of(context);
  final next = state.single == null
      ? InputKind.single
      : (state.bomA == null ? InputKind.a : null);
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
    final touch = Metrics.of(context).touch;

    Widget iconButton(Lucide icon, String tip, VoidCallback onTap) => Hoverable(
      onTap: onTap,
      tooltip: tip,
      builder: (context, hover, _) => Container(
        width: touch ? 44 : 30,
        height: touch ? 44 : 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hover ? c.hover : null,
          shape: BoxShape.circle,
        ),
        child: LucideIcon(icon, size: 15, color: c.tx2),
      ),
    );

    final card = Hoverable(
      onTap: f == null ? () => importFile(context, state, widget.kind) : null,
      builder: (context, hover, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        key: ValueKey('import-card-${widget.kind.name}'),
        constraints: const BoxConstraints(minHeight: 44),
        padding: EdgeInsets.fromLTRB(10, touch ? 0.5 : 6, 6, touch ? 0.5 : 6),
        decoration: BoxDecoration(
          color: _dragging || (hover && f == null)
              ? Color.alphaBlend(c.blueTint, c.card)
              : c.card,
          borderRadius: c.r(22),
          border: Border.all(
            color: widget.next || _dragging ? c.blue : c.lineStrong,
            width: widget.next || _dragging ? 1.5 : 1,
          ),
          boxShadow: c.shadowSm,
        ),
        child: Row(
          children: [
            Hoverable(
              tooltip: widget.help,
              cursor: SystemMouseCursors.help,
              builder: (context, hover, _) => GradientTile(
                icon: widget.icon,
                colors: widget.colors,
                glow: widget.glow,
                size: 28,
                radius: 9,
                iconSize: 15,
              ),
            ),
            const SizedBox(width: 8),
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
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.2,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                            color: c.tx,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: widget.optional ? c.grayTint : c.blueTint,
                          borderRadius: c.r(999),
                        ),
                        child: Text(
                          widget.optional
                              ? s.t('in_optional_chip')
                              : s.t('in_required_chip'),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w600,
                            height: 1.5,
                            color: widget.optional ? c.tx2 : c.blueTx,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          f?.name ?? s.t('well_formats'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.2,
                            color: c.tx2,
                          ),
                        ),
                      ),
                      if (f != null) ...[
                        const SizedBox(width: 6),
                        Hoverable(
                          tooltip: '${f.name}\n${_details(s, f.bom)}',
                          builder: (context, hover, _) => Text(
                            issues == 0
                                ? s.t('file_read_count', {
                                    'n': f.bom.parts.length,
                                  })
                                : s.t('in_issues', {'n': issues}),
                            style: TextStyle(
                              fontSize: 11.5,
                              height: 1.2,
                              color: issues == 0 ? c.tx3 : c.warnTx,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (f != null) ...[
              const SizedBox(width: 4),
              iconButton(
                Lucide.refresh,
                s.t('step_replace'),
                () => importFile(context, state, widget.kind),
              ),
              iconButton(
                Lucide.trash,
                s.t('file_remove'),
                () => state.unload(widget.kind),
              ),
            ] else
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: LucideIcon(
                  Lucide.plus,
                  size: 18,
                  color: c.blue,
                  stroke: 2.2,
                ),
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
    final touch = Metrics.of(context).touch;
    final run = PillButton(
      key: tourTargets.runButton,
      label: s.t('btn_run'),
      icon: Lucide.play,
      kind: PillKind.primary,
      height: 44,
      fontSize: 14,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      trailing: compact ? null : const KeyHint('F5'),
      onTap: state.ready && !state.localBusy && !state.cloudRunning
          ? () => runCheck(context, state)
          : null,
    );
    final export = compact
        ? KeyedSubtree(
            key: tourTargets.checkExport,
            child: GlassButton(
              icon: Lucide.download,
              size: 44,
              tooltip: s.t('btn_export_excel'),
              onTap: state.canExportReport
                  ? () => exportReport(context, state)
                  : null,
            ),
          )
        : PillButton(
            key: tourTargets.checkExport,
            label: s.t('btn_export_excel'),
            icon: Lucide.download,
            kind: PillKind.soft,
            height: 44,
            fontSize: 13,
            color: c.blueTx,
            onTap: state.canExportReport
                ? () => exportReport(context, state)
                : null,
          );
    final clear = GlassButton(
      icon: Lucide.trash,
      size: 44,
      tooltip: s.t('btn_clear'),
      onTap: state.clearAll,
    );
    return Container(
      key: const ValueKey('check-command-bar'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: c.r(16),
        border: c.cardBorder,
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final inline = !compact && box.maxWidth >= 640;
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  if (inline) run else Expanded(child: run),
                  const SizedBox(width: 12),
                  if (inline) ...[
                    SizedBox(
                      width: touch ? 270 : 244,
                      child: ModeSelector(state: state),
                    ),
                    const Spacer(),
                  ],
                  export,
                  const SizedBox(width: 6),
                  clear,
                ],
              ),
              if (!inline) ...[
                const SizedBox(height: 8),
                ModeSelector(state: state),
              ],
              if (!state.localAnalysisRequired) ...[
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AiSwitch(state: state),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Model controls and the immutable evidence for the displayed check.
class LocalModelIndicator extends StatefulWidget {
  const LocalModelIndicator({
    super.key,
    required this.state,
    this.compact = false,
    this.alwaysExpanded = false,
    this.registerTour = true,
  });
  final AppState state;
  final bool compact;
  final bool alwaysExpanded;
  final bool registerTour;
  @override
  State<LocalModelIndicator> createState() => _LocalModelIndicatorState();
}

class _LocalModelIndicatorState extends State<LocalModelIndicator> {
  bool _showOptions = false;
  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final c = AppTheme.of(context);
    final state = widget.state;
    final usage =
        state.report?.localModel ??
        (state.localAnalysisRequired && state.localStatus != LocalStatus.idle
            ? state.currentLocalUsage
            : null);
    final status = usage?.state ?? 'idle';
    final color = status == 'failed' || status == 'unavailable'
        ? c.warnTx
        : status == 'done'
        ? c.okTx
        : c.tx2;
    return Container(
      key: widget.registerTour ? tourTargets.localModels : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: c.r(18),
        border: c.cardBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.alwaysExpanded &&
              (widget.compact || isPhoneLayout(context)) &&
              (state.report != null ||
                  state.localBusy ||
                  state.cloudRunning)) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    s.t(
                      state.localAnalysisRequired
                          ? 'local_analysis_required'
                          : 'local_usage_title',
                    ),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.tx,
                    ),
                  ),
                ),
                PillButton(
                  key: const ValueKey('model-options-expand'),
                  label: s.t('local_options'),
                  kind: PillKind.ghost,
                  height: 44,
                  onTap: () => setState(() => _showOptions = !_showOptions),
                ),
              ],
            ),
            if (_showOptions) LocalModelControls(state: state, compact: true),
          ] else
            LocalModelControls(state: state, compact: true),
          if (usage != null) ...[
            const SizedBox(height: 2),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (usage.kind != 'analysis' || status != 'done')
                  Text(
                    s.t('local_usage_title'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: c.tx,
                    ),
                  ),
                if (usage.kind != 'analysis' || status != 'done')
                  Text(
                    s.t(
                      usage.kind == 'analysis' &&
                              (status == 'unavailable' || status == 'failed')
                          ? 'local_analysis_no_result'
                          : 'local_state_$status',
                    ),
                    style: TextStyle(fontSize: 12, height: 1.4, color: color),
                  ),
                if (usage.model.isNotEmpty &&
                    (widget.compact ||
                        isPhoneLayout(context) ||
                        usage.kind != 'analysis'))
                  Text(
                    usage.model,
                    style: TextStyle(fontSize: 11.5, height: 1.4, color: c.tx2),
                  ),
                if (status == 'done')
                  Text(
                    s.t(
                      usage.kind == 'analysis'
                          ? 'local_analysis_brief'
                          : 'local_usage_counts',
                      {
                        'n': usage.kind == 'analysis'
                            ? usage.rows
                            : usage.texts,
                        'all': usage.total,
                        'b': usage.calls,
                        's': (usage.millis / 1000).toStringAsFixed(1),
                        'p': usage.paired,
                        'ms': usage.millis,
                      },
                    ),
                    style: TextStyle(fontSize: 11.5, color: color),
                  ),
                if (status == 'failed')
                  Text(
                    s.t(usage.error),
                    style: TextStyle(fontSize: 11.5, color: color),
                  ),
              ],
            ),
            if (status == 'running') ...[
              const SizedBox(height: 6),
              TrackBar(
                value: state.localProgress.clamp(0.0, 1.0),
                color: c.blue,
                height: 3,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class ModeSelector extends StatelessWidget {
  const ModeSelector({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final mode = state.settings.checkMode;
    final run = state.cloudRun;
    return Column(
      key: tourTargets.modeSelector,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Hoverable(
          tooltip: s.t('mode_${mode.name}_hint'),
          cursor: SystemMouseCursors.basic,
          builder: (context, hover, _) => Segmented<CheckMode>(
            expand: true,
            value: mode,
            options: [
              for (final m in CheckMode.values) (m, s.t('mode_${m.name}')),
            ],
            onChanged: (m) {
              if (state.localBusy || state.cloudRunning) return;
              state.setCheckMode(m);
              if (m != CheckMode.local && !state.cloudReady) {
                state.openSettings(SettingsSection.ai);
              }
            },
          ),
        ),
        if (state.cloudRunning || (run != null && !run.complete)) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              if (state.cloudRunning) ...[
                const Spinner(size: 13),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  run == null
                      ? s.t('cloud_starting')
                      : s.t('cloud_progress', {
                          'done': run.batchesDone,
                          'all': run.batches,
                          'failed': run.batchesFailed,
                        }),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: run != null && run.batchesFailed > 0
                        ? c.ngTx
                        : c.tx2,
                  ),
                ),
              ),
              if (state.cloudRunning)
                Hoverable(
                  onTap: state.cancelCloud,
                  builder: (context, hover, _) => Text(
                    s.t('dlg_cancel'),
                    style: TextStyle(fontSize: 12, color: c.blueTx),
                  ),
                ),
            ],
          ),
        ],
      ],
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
    final configured = state.cloudReady;
    final (String sub, Color color) = !configured
        ? (s.t('ai_not_set'), c.warnTx)
        : !on
        ? (s.t('ai_off'), c.tx3)
        : switch (state.aiStatus) {
            AiStatus.running => (s.t('ai_running'), c.blueTx),
            AiStatus.done => (
              s.t('ai_done', {'n': state.ai?.findings.length ?? 0}),
              c.okTx,
            ),
            AiStatus.failed => (s.t('ai_failed'), c.ngTx),
            AiStatus.idle => (s.t('ai_on'), c.tx2),
          };
    return Hoverable(
      key: tourTargets.aiSwitch,
      onTap: () => configured
          ? state.setAiEnabled(!on)
          : state.openSettings(SettingsSection.ai),
      tooltip: configured ? null : s.t('ai_setup_hint'),
      builder: (context, hover, _) => Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
        decoration: BoxDecoration(
          color: hover ? c.hover : c.well,
          borderRadius: c.r(14),
        ),
        child: Row(
          children: [
            LucideIcon(
              Lucide.sparkles,
              size: 16,
              color: on && configured ? c.blueTx : c.tx2,
              stroke: 2,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.t('ai_check'),
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: c.tx,
                    ),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: color),
                  ),
                ],
              ),
            ),
            if (state.aiStatus == AiStatus.running && on) ...[
              const Spinner(size: 14),
              const SizedBox(width: 8),
            ],
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
  final lines = <String>[
    bom.headerRow < 0
        ? s.t('det_sheet_nohead', {'sheet': bom.sheet})
        : s.t('det_sheet', {'sheet': bom.sheet, 'row': bom.headerRow + 1}),
  ];
  for (final col in bom.columns) {
    if (col.role == BomRole.serial) continue;
    final role = col.role == BomRole.other
        ? s.t('role_other')
        : s.t('role_${col.role.name}');
    final head = col.header.isEmpty ? s.t('det_no_header') : col.header;
    lines.add('${_colName(col.index)} · $head → $role');
  }
  if (bom.warnings.isNotEmpty) {
    lines.add('');
    for (final w in bom.warnings.take(8)) {
      lines.add(s.t(w.code, {'row': w.row, 'detail': w.detail}));
    }
    if (bom.warnings.length > 8) {
      lines.add(s.t('det_more', {'n': bom.warnings.length - 8}));
    }
  }
  return lines.join('\n');
}
