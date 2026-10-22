/// Files module: the four inputs as cards with what was detected in each.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'glyphs.dart';
import 'theme.dart';
import 'widgets.dart';

class FilesPage extends StatelessWidget {
  const FilesPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final ready = state.bom != null && (state.stationA != null || state.stationB != null);
    final cards = [
      _FileCard(
        state: state,
        kind: InputKind.bom,
        glyph: Glyph.bom,
        title: s.t('btn_bom'),
        hint: s.t('step_bom'),
        file: state.bom,
        stats: state.bom == null
            ? null
            : [
                s.t('file_rows', {'n': state.bom!.result.items.length}),
                s.t('file_refs', {'n': state.bom!.result.items.fold<int>(0, (n, b) => n + b.refs.length)}),
              ],
      ),
      _FileCard(
        state: state,
        kind: InputKind.stationA,
        glyph: Glyph.stationA,
        title: s.t('btn_station_a'),
        hint: s.t('step_station_a'),
        file: state.stationA,
        stats: _stationStats(s, state.stationA),
      ),
      _FileCard(
        state: state,
        kind: InputKind.stationB,
        glyph: Glyph.stationB,
        title: s.t('btn_station_b'),
        hint: s.t('step_station_b'),
        file: state.stationB,
        optional: true,
        stats: _stationStats(s, state.stationB),
      ),
      _FileCard(
        state: state,
        kind: InputKind.coords,
        glyph: Glyph.coords,
        title: s.t('btn_coord'),
        hint: s.t('step_coord'),
        file: state.coords,
        optional: true,
        stats: state.coords == null
            ? null
            : [
                s.t('file_refs', {'n': state.coords!.result.items.length}),
                (state.coords!.result.columns['unit'] ?? 'mm'),
              ],
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PageHeader(title: s.t('mod_files'), subtitle: s.t('page_files_sub')),
        Expanded(
          child: Container(
            color: c.window,
            child: LayoutBuilder(builder: (context, box) {
              final twoCols = box.maxWidth >= 860;
              final gap = 14.0;
              final w = twoCols ? (box.maxWidth.clamp(0, 1180) - 40 - gap) / 2 : box.maxWidth - 32;
              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1140),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Wrap(spacing: gap, runSpacing: gap, children: [for (final card in cards) SizedBox(width: w, child: card)]),
                      const SizedBox(height: 20),
                      SurfaceCard(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: Row(children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(shape: BoxShape.circle, color: ready ? c.pass : c.textFaint),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(s.t(ready ? 'files_ready' : 'files_not_ready'), style: TextStyle(fontSize: 13, color: c.textDim)),
                          ),
                          FlatButton(icon: null, label: s.t('btn_run'), primary: true, onTap: ready ? () => runCheck(context, state) : null),
                        ]),
                      ),
                    ]),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  List<String>? _stationStats(Strings s, LoadedFile<StationItem>? f) {
    if (f == null) return null;
    final items = f.result.items;
    final alts = items.fold<int>(0, (n, e) => n + e.alternates.length);
    return [
      s.t('file_rows', {'n': items.length}),
      s.t('file_refs', {'n': items.fold<int>(0, (n, e) => n + e.refs.length)}),
      if (alts > 0) '${s.t('cat_substitute')} $alts',
    ];
  }
}

class _FileCard extends StatelessWidget {
  const _FileCard({
    required this.state,
    required this.kind,
    required this.glyph,
    required this.title,
    required this.hint,
    required this.file,
    this.stats,
    this.optional = false,
  });

  final AppState state;
  final InputKind kind;
  final Glyph glyph;
  final String title;
  final String hint;
  final LoadedFile<Object?>? file;
  final List<String>? stats;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final loaded = file != null;
    final columns = file?.result.columns.entries.where((e) => e.key != 'unit').map((e) => e.value).toList() ?? const <String>[];
    final issues = file?.result.issues ?? const [];
    return SurfaceCard(
      padding: const EdgeInsets.all(18),
      borderColor: loaded ? c.pass.withValues(alpha: 0.45) : null,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: c.panelAlt, borderRadius: BorderRadius.circular(10), border: Border.all(color: c.border)),
            child: GlyphIcon(glyph, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.text)),
                const SizedBox(width: 8),
                _Tag(
                  text: loaded ? s.t('file_loaded') : (optional ? s.t('step_optional') : s.t('file_none')),
                  color: loaded ? c.pass : c.textFaint,
                ),
              ]),
              const SizedBox(height: 3),
              Text(loaded ? file!.name : hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: loaded ? c.textDim : c.textFaint)),
            ]),
          ),
        ]),
        if (stats != null) ...[
          const SizedBox(height: 14),
          Row(children: [
            for (final st in stats!) ...[
              Text(st, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(width: 14),
            ],
          ]),
        ],
        if (columns.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final col in columns) _Tag(text: col, color: c.textDim, outlined: true)]),
        ],
        for (final i in issues.take(3))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(s.t(i.code, {'row': i.row, 'detail': i.detail}),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.substitute)),
          ),
        const SizedBox(height: 16),
        Row(children: [
          FlatButton(
            label: loaded ? s.t('step_replace') : s.t('step_import'),
            primary: !loaded,
            compact: true,
            onTap: () => importFile(context, state, kind),
          ),
          if (loaded) ...[
            const SizedBox(width: 8),
            FlatButton(label: s.t('file_remove'), compact: true, onTap: () => state.unload(kind)),
          ],
        ]),
      ]),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color, this.outlined = false});

  final String text;
  final Color color;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: outlined ? c.panelAlt : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: outlined ? c.border : color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(fontSize: 11.5, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
