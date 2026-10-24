/// Files module: centred hero with the three steps, one large card per input
/// file (click or drop a file into its well), and the floating action bar
/// with Clear and Run Check.
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

class FilesPage extends StatelessWidget {
  const FilesPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final c = AppTheme.of(context);
    final ready = state.bom != null && (state.stationA != null || state.stationB != null);
    final inputs = [
      _Input(
        InputKind.bom,
        s.t('in_bom_title'),
        s.t('in_bom_hint'),
        s.t('in_bom_help'),
        state.bom,
        false,
        Lucide.clipboardCheck,
        GradientTile.blue,
        GradientTile.blueGlow,
      ),
      _Input(
        InputKind.stationA,
        s.t('btn_station_a'),
        s.t('step_station_a'),
        s.t('in_station_help'),
        state.stationA,
        false,
        Lucide.sheetTop,
        GradientTile.teal,
        GradientTile.tealGlow,
      ),
      _Input(
        InputKind.stationB,
        s.t('btn_station_b'),
        s.t('in_station_b_hint'),
        s.t('in_station_help'),
        state.stationB,
        true,
        Lucide.sheetBottom,
        GradientTile.orange,
        GradientTile.orangeGlow,
      ),
    ];
    final next = state.bom == null ? InputKind.bom : (state.stationA == null && state.stationB == null ? InputKind.stationA : null);

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final cards = [
          for (final i in inputs)
            _InputCard(
              key: switch (i.kind) {
                InputKind.bom => tourTargets.bomCard,
                InputKind.stationA => tourTargets.stationCard,
                _ => null,
              },
              state: state,
              input: i,
              next: i.kind == next,
            ),
        ];
        // Phones and portrait tablets keep the run bar pinned at the bottom.
        final phone = MediaQuery.sizeOf(context).width < 900;
        final page = SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1200),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 16),
                child: Column(
                  children: [
                    SizedBox(height: wide ? 48 : 24),
                    Text(
                      s.t('app_subtitle'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 1.04, color: c.blueTx),
                    ),
                    const SizedBox(height: 14),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Text(
                        s.t('files_hero_sub'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: wide ? 20 : 17, height: 1.5, color: c.tx2),
                      ),
                    ),
                    const SizedBox(height: 32),
                    _Steps(state: state, ready: ready),
                    const SizedBox(height: 52),
                    KeyedSubtree(
                      key: tourTargets.fileChecks,
                      child: wide
                          ? IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: 24), Expanded(child: cards[i])],
                                ],
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(height: 20), cards[i]],
                              ],
                            ),
                    ),
                    if (!phone) ...[const SizedBox(height: 48), _ActionBar(state: state, ready: ready)],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        );
        if (!phone) return page;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: page),
            Padding(padding: const EdgeInsets.fromLTRB(12, 6, 12, 0), child: _ActionBar(state: state, ready: ready, compact: true)),
          ],
        );
      },
    );
  }
}

class _Input {
  _Input(this.kind, this.title, this.desc, this.help, this.file, this.optional, this.icon, this.colors, this.glow);

  final InputKind kind;
  final String title;
  final String desc;

  /// What the file must contain, shown on the icon tile.
  final String help;
  final LoadedFile<Object?>? file;
  final bool optional;
  final Lucide icon;
  final (Color, Color) colors;
  final Color glow;
}

/// 1 Import files · 2 BOM check · 3 FAI coordinates.
class _Steps extends StatelessWidget {
  const _Steps({required this.state, required this.ready});

  final AppState state;
  final bool ready;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final checked = state.report != null;
    final built = checked && state.coords != null;
    final steps = [
      (s.t('step1_title'), ready, !ready, null),
      (s.t('step2_title'), checked, ready && !checked, () => state.setModule(Module.check)),
      (s.t('step3_title'), built, checked && !built, () => state.setModule(Module.cad)),
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 32,
      runSpacing: 10,
      children: [
        for (var i = 0; i < steps.length; i++)
          Hoverable(
            onTap: steps[i].$4,
            builder: (context, hover, _) {
              final (label, done, active, _) = steps[i];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? c.blueTint
                          : active
                          ? c.btn
                          : c.track,
                      boxShadow: active && !done ? const [BoxShadow(color: Color(0x590071E3), offset: Offset(0, 4), blurRadius: 12)] : null,
                    ),
                    child: done
                        ? LucideIcon(Lucide.check, size: 13, color: c.blueTx, stroke: 3)
                        : Text(
                            '${i + 1}',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1, color: active ? const Color(0xFFFFFFFF) : c.tx2),
                          ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    label,
                    style: TextStyle(fontSize: 15, fontWeight: active ? FontWeight.w600 : FontWeight.w500, color: done || active ? c.tx : c.tx2),
                  ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _InputCard extends StatefulWidget {
  const _InputCard({super.key, required this.state, required this.input, required this.next});

  final AppState state;
  final _Input input;

  /// The file to import next: raised with a blue glow.
  final bool next;

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

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Hoverable(
          tooltip: input.help,
          cursor: SystemMouseCursors.help,
          builder: (context, hover, _) => GradientTile(icon: input.icon, colors: input.colors, glow: input.glow),
        ),
        const Spacer(),
        if (widget.next) ...[
          Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.btn, borderRadius: BorderRadius.circular(12)),
            child: Text(
              s.t('in_next'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFFFFFFF)),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(color: input.optional ? c.grayTint : c.blueTint, borderRadius: BorderRadius.circular(999)),
          child: Text(
            input.optional ? s.t('in_optional_chip') : s.t('in_required_chip'),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, height: 1.5, color: input.optional ? c.tx2 : c.blueTx),
          ),
        ),
      ],
    );

    final Widget well;
    if (f == null) {
      well = Hoverable(
        onTap: () => importFile(context, state, input.kind),
        builder: (context, hover, _) => AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          height: 232,
          decoration: BoxDecoration(color: hover || _dragging ? c.blueTint : c.well, borderRadius: BorderRadius.circular(26)),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.circle,
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Color(0x1A1E2850), offset: Offset(0, 6), blurRadius: 18)],
                ),
                child: LucideIcon(Lucide.plus, size: 24, color: c.blue, stroke: 2),
              ),
              const SizedBox(height: 14),
              Text(
                dropSupported ? s.t('well_drop') : s.t('well_tap'),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.16, color: c.tx),
              ),
              if (dropSupported) ...[
                const SizedBox(height: 4),
                Text(
                  s.t('well_click'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.blueTx),
                ),
              ],
              const SizedBox(height: 12),
              Text(s.t('well_formats'), style: TextStyle(fontSize: 12, color: c.tx2)),
            ],
          ),
        ),
      );
    } else {
      final issues = f.result.issues.length;
      final columns = f.result.columns.entries.where((e) => e.key != 'unit').map((e) => e.value).toList();
      final ext = f.name.split('.').last.toLowerCase();
      final bom = input.kind == InputKind.bom;
      Widget fact(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: c.tx2)),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.tx),
          ),
        ],
      );
      well = AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 232,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: _dragging ? c.blueTint : c.well, borderRadius: BorderRadius.circular(26)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.17, color: c.tx),
                ),
                const SizedBox(height: 3),
                Text('${formatSize(f.size)} · ${formatTime(f.loadedAt)}', style: TextStyle(fontSize: 13, color: c.tx2)),
              ],
            ),
            Row(
              children: [
                Expanded(child: fact(s.t('row_format_short'), _formatName(ext))),
                const SizedBox(width: 16),
                Expanded(
                  child: fact(
                    s.t(bom ? 'row_bom_count' : 'row_station_count'),
                    s.t(bom ? 'card_count_bom' : 'card_count_station', {'n': f.result.items.length}),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: fact(s.t('row_sheets'), f.sheets <= 1 ? s.t('card_sheet_single') : s.t('chk_sheets_n', {'n': f.sheets}))),
                const SizedBox(width: 16),
                Expanded(child: fact(s.t('row_columns'), columns.isEmpty ? '—' : columns.take(3).join(' · '))),
              ],
            ),
            Row(
              children: [
                Container(
                  height: 28,
                  padding: const EdgeInsets.fromLTRB(9, 0, 12, 0),
                  decoration: BoxDecoration(color: issues == 0 ? c.okTint : c.warnTint, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LucideIcon(issues == 0 ? Lucide.check : Lucide.alert, size: 14, color: issues == 0 ? c.okTx : c.warnTx, stroke: 2.6),
                      const SizedBox(width: 6),
                      Text(
                        issues == 0 ? s.t('chk_passed') : s.t('in_issues', {'n': issues}),
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: issues == 0 ? c.okTx : c.warnTx),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                PillButton(
                  label: s.t('step_replace'),
                  kind: PillKind.ghost,
                  height: 32,
                  color: c.blueTx,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onTap: () => importFile(context, state, input.kind),
                ),
                PillButton(
                  label: s.t('file_remove'),
                  kind: PillKind.ghost,
                  height: 32,
                  color: c.blueTx,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  onTap: () => state.unload(input.kind),
                ),
              ],
            ),
          ],
        ),
      );
    }

    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      transform: Matrix4.translationValues(0, widget.next ? -4 : 0, 0),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(36),
        boxShadow: widget.next
            ? const [
                BoxShadow(color: Color(0x0F0A64E8), offset: Offset(0, 2), blurRadius: 4),
                BoxShadow(color: Color(0x3D0A64E8), offset: Offset(0, 32), blurRadius: 72),
              ]
            : c.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 22),
          Text(
            input.title,
            style: TextStyle(fontSize: 24, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.53, color: c.tx),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 42),
            child: Text(input.desc, style: TextStyle(fontSize: 14, height: 1.5, color: c.tx2)),
          ),
          const SizedBox(height: 24),
          well,
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

String _formatName(String ext) => switch (ext) {
  'xlsx' || 'xlsm' => 'Excel (.$ext)',
  'csv' => 'CSV (.csv)',
  'txt' => 'Text (.txt)',
  _ => '.$ext',
};

/// Floating pill with the import progress, Clear and Run Check.
class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.state, required this.ready, this.compact = false});

  final AppState state;
  final bool ready;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final loaded = [state.bom != null, state.stationA != null, state.stationB != null];
    final (headline, subline) = state.report != null
        ? (s.t('bar_checked'), s.t('bar_checked_sub'))
        : state.bom == null
        ? (s.t('bar_need_bom'), s.t('bar_need_bom_sub'))
        : !ready
        ? (s.t('bar_need_station'), s.t('bar_optional_b'))
        : (s.t('bar_ready'), state.stationB != null && state.stationA != null ? s.t('bar_all_loaded') : s.t('bar_optional_b'));
    if (compact) {
      return Container(
        padding: const EdgeInsets.fromLTRB(18, 8, 8, 8),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(26), boxShadow: c.shadow),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(headline, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.tx)),
                  Text(subline, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.tx2)),
                ],
              ),
            ),
            GlassButton(icon: Lucide.trash, size: 40, tooltip: s.t('btn_clear'), onTap: state.clearAll),
            const SizedBox(width: 6),
            PillButton(
              key: tourTargets.runButton,
              label: s.t('btn_run'),
              kind: PillKind.primary,
              height: 44,
              fontSize: 15,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              onTap: ready ? () => runCheck(context, state) : null,
            ),
          ],
        ),
      );
    }
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PillButton(
          label: s.t('btn_clear'),
          icon: Lucide.trash,
          kind: PillKind.ghost,
          height: 48,
          fontSize: 15,
          weight: FontWeight.w500,
          iconSize: 16,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          onTap: state.clearAll,
        ),
        const SizedBox(width: 8),
        PillButton(
          key: tourTargets.runButton,
          label: s.t('btn_run'),
          kind: PillKind.primary,
          height: 48,
          fontSize: 16,
          padding: const EdgeInsets.fromLTRB(26, 0, 10, 0),
          trailing: const KeyHint('F5'),
          onTap: ready ? () => runCheck(context, state) : null,
        ),
      ],
    );
    final info = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            for (var i = 0; i < loaded.length; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: 26,
                height: 6,
                decoration: BoxDecoration(color: loaded[i] ? c.blue : c.track, borderRadius: BorderRadius.circular(3)),
              ),
            ],
          ],
        ),
        const SizedBox(width: 18),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                headline,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.25, color: c.tx),
              ),
              const SizedBox(height: 2),
              Text(subline, style: TextStyle(fontSize: 13, color: c.tx2)),
            ],
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 14, 14, 14),
      decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(40), boxShadow: c.shadow),
      child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, spacing: 36, runSpacing: 16, children: [info, buttons]),
    );
  }
}
