/// Check history: past checks, newest first, searchable by file name, part
/// number or description; each can be read back, checked again or its
/// report saved as it was.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/bom_compare.dart';
import '../core/history.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'check_view.dart' show statusLabel, statusText, statusTint;
import 'design.dart';
import 'lucide.dart';
import 'theme.dart';
import 'widgets.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key, required this.state});

  final AppState state;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  final _query = TextEditingController();
  List<(HistoryEntry, List<HistoryLine>)>? _results;
  String? _open;
  int _bytes = 0;
  int _searchRun = 0;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    await widget.state.refreshHistory();
    final b = await widget.state.history?.bytes() ?? 0;
    if (!mounted) return;
    setState(() => _bytes = b);
    await _search();
  }

  Future<void> _search() async {
    final run = ++_searchRun;
    final store = widget.state.history;
    if (store == null) return;
    final r = await store.search(_query.text, entries: widget.state.historyEntries);
    if (!mounted || run != _searchRun) return;
    setState(() => _results = r);
  }

  String _stamp(DateTime t) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }

  String _size(int b) => b >= 1 << 20 ? '${(b / (1 << 20)).toStringAsFixed(1)} MB' : '${(b / 1024).ceil()} KB';

  Future<void> _delete(HistoryEntry e) async {
    final s = Strings.of(context);
    final ok = await showMessage(context, title: s.t('hist_delete'), message: s.t('hist_delete_ask', {'t': _stamp(e.at)}), ok: s.t('hist_delete'), cancel: s.t('dlg_cancel'), error: true);
    if (!ok) return;
    await widget.state.deleteHistory(e.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final state = widget.state;
    final results = _results;
    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PillSearch(controller: _query, hint: s.t('hist_search'), onChanged: (_) => _search()),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            s.t('hist_summary', {'n': state.historyEntries.length, 'size': _size(_bytes)}) + (state.historyError.isEmpty ? '' : '  ·  ${s.t('hist_err_save', {'e': state.historyError})}'),
            style: TextStyle(fontSize: 12.5, color: state.historyError.isEmpty ? c.tx3 : c.ngTx),
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
    if (state.history == null || results == null) return head;
    if (results.isEmpty) {
      return ListView(
        children: [
          head,
          DCard(child: EmptyStateText(text: s.t(state.historyEntries.isEmpty ? 'hist_empty' : 'hist_no_match'))),
        ],
      );
    }
    return ListView.builder(
      padding: EdgeInsets.only(bottom: bottomInset(context) + 24),
      itemCount: results.length + 1,
      itemBuilder: (context, i) {
        if (i == 0) return head;
        final (e, hits) = results[i - 1];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _EntryCard(
            state: state,
            entry: e,
            hits: hits,
            query: _query.text.trim(),
            open: _open == e.id,
            stamp: _stamp(e.at),
            onToggle: () => setState(() => _open = _open == e.id ? null : e.id),
            onDelete: () => _delete(e),
          ),
        );
      },
    );
  }
}

/// A short centred note in a card.
class EmptyStateText extends StatelessWidget {
  const EmptyStateText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
    child: Text(text, textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppTheme.of(context).tx2)),
  );
}

class _EntryCard extends StatefulWidget {
  const _EntryCard({
    required this.state,
    required this.entry,
    required this.hits,
    required this.query,
    required this.open,
    required this.stamp,
    required this.onToggle,
    required this.onDelete,
  });

  final AppState state;
  final HistoryEntry entry;
  final List<HistoryLine> hits;
  final String query;
  final bool open;
  final String stamp;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  State<_EntryCard> createState() => _EntryCardState();
}

class _EntryCardState extends State<_EntryCard> {
  List<HistoryLine>? _lines;
  CheckStatus? _filter = CheckStatus.ng;

  @override
  void didUpdateWidget(covariant _EntryCard old) {
    super.didUpdateWidget(old);
    if (widget.open && _lines == null) _load();
  }

  @override
  void initState() {
    super.initState();
    if (widget.open) _load();
  }

  Future<void> _load() async {
    final l = await widget.state.history?.lines(widget.entry.id) ?? const <HistoryLine>[];
    if (!mounted) return;
    setState(() {
      _lines = l;
      // Open on the problems when there are any.
      if (!l.any((x) => x.status == CheckStatus.ng)) _filter = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final e = widget.entry;
    final phone = isPhoneLayout(context);
    Widget count(CheckStatus st) {
      final n = e.counts[st.name] ?? 0;
      return DBadge(text: '${statusLabel(s, st)} $n', background: n == 0 ? c.well : statusTint(c, st), color: n == 0 ? c.tx3 : statusText(c, st), height: 24);
    }

    final header = Hoverable(
      onTap: widget.onToggle,
      builder: (context, hover, _) => Container(
        color: hover ? c.hover : null,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 2), child: LucideIcon(Lucide.history, size: 18, color: c.tx2, stroke: 2)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(widget.stamp, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: c.tx)),
                      const SizedBox(width: 10),
                      Text(s.t('mode_${e.mode}'), style: TextStyle(fontSize: 12.5, color: c.tx3)),
                      if (!e.complete) ...[const SizedBox(width: 8), DBadge(text: s.t('hist_incomplete'), background: c.ngTint, color: c.ngTx, height: 22)],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [for (final f in e.files) '${f.role}: ${f.name}'].join('    '),
                    maxLines: phone ? 3 : 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: c.tx2),
                  ),
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: [for (final st in CheckStatus.values) count(st)]),
                  if (widget.query.isNotEmpty && widget.hits.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      s.t('hist_hits', {'n': widget.hits.length, 'list': widget.hits.take(4).map((l) => '${l.partNo} (${statusLabel(s, l.status)})').join('、')}),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: c.blueTx),
                    ),
                  ],
                ],
              ),
            ),
            LucideIcon(widget.open ? Lucide.chevronUp : Lucide.chevronDown, size: 16, color: c.tx3, stroke: 2.2),
          ],
        ),
      ),
    );
    return DCard(
      radius: 18,
      clip: true,
      shadow: c.shadowSm,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [header, if (widget.open) _details(context)],
      ),
    );
  }

  Widget _details(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final e = widget.entry;
    final lines = _lines;
    final q = widget.query.toLowerCase();
    final shown = lines == null
        ? const <HistoryLine>[]
        : [
            for (final l in lines)
              if ((_filter == null || l.status == _filter) && (q.isEmpty || l.matches(q))) l,
          ];
    const cap = 300;
    final info = TextStyle(fontSize: 12.5, height: 1.5, color: c.tx2);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(height: 1, color: c.line, margin: const EdgeInsets.only(bottom: 12)),
          for (final f in e.files) Text('${f.role}-BOM  ${f.name}  ·  ${(f.size / 1024).ceil()} KB  ·  SHA-256 ${f.sha256.substring(0, 16)}…', style: info),
          if (e.models.isNotEmpty) Text('${s.t('rep_models')}: ${e.models.join(', ')}', style: info),
          if (e.skipped.isNotEmpty) Text('${s.t('rep_skipped')}: ${[for (final k in e.skipped) s.t('cmpf_$k')].join('、')}', style: info),
          Text('${s.t('hist_version')} ${e.appVersion}  ·  ${s.t('hist_id')} ${e.id}', style: info),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillButton(label: s.t('hist_reopen'), icon: Lucide.refresh, kind: PillKind.soft, height: 34, fontSize: 13, onTap: () => reopenHistory(context, widget.state, e)),
              PillButton(label: s.t('hist_export'), icon: Lucide.download, kind: PillKind.ghost, height: 34, fontSize: 13, onTap: () => exportHistoryReport(context, widget.state, e)),
              PillButton(label: s.t('hist_delete'), icon: Lucide.trash, kind: PillKind.ghost, height: 34, fontSize: 13, color: c.ngTx, onTap: widget.onDelete),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final st in <CheckStatus?>[null, ...CheckStatus.values])
                Hoverable(
                  onTap: () => setState(() => _filter = st),
                  builder: (context, hover, _) => DBadge(
                    text: st == null ? s.t('opt_all') : statusLabel(s, st),
                    background: _filter == st ? (st == null ? c.blueTint : statusTint(c, st)) : (hover ? c.hover : c.well),
                    color: _filter == st ? (st == null ? c.blueTx : statusText(c, st)) : c.tx2,
                    height: 26,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (lines == null)
            const Padding(padding: EdgeInsets.all(12), child: Center(child: Spinner()))
          else if (shown.isEmpty)
            Padding(padding: const EdgeInsets.all(12), child: Text(s.t('no_rows'), style: TextStyle(fontSize: 13, color: c.tx3)))
          else ...[
            for (final l in shown.take(cap))
              Container(
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 180,
                      child: Text(l.otherPartNo.isEmpty ? l.partNo : '${l.partNo} → ${l.otherPartNo}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.tx)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [l.description, if (l.reasons.isNotEmpty) [for (final r in l.reasons) s.t('reason_$r')].join('；')].join('\n'),
                        style: TextStyle(fontSize: 12.5, height: 1.4, color: c.tx2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DBadge(text: statusLabel(s, l.status), background: statusTint(c, l.status), color: statusText(c, l.status), height: 24),
                  ],
                ),
              ),
            if (shown.length > cap) Padding(padding: const EdgeInsets.only(top: 8), child: Text(s.t('hist_more', {'n': shown.length - cap}), style: TextStyle(fontSize: 12.5, color: c.tx3))),
          ],
        ],
      ),
    );
  }
}
