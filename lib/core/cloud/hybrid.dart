/// HYBRID check: the local engine decides everything it can; the lines it
/// could not settle go to the cloud model in batches, and every answer is
/// checked by the program before it changes anything.
///
/// The cloud may confirm that two descriptions mean the same item where
/// the program could only say "worded differently" or "paired by
/// parameters / meaning" (then PASS, provided the program finds no
/// parameter conflict and compatible kinds), and may propose a counterpart
/// for an unmatched line (then REVIEW). It never overrides a conflict the
/// program found, never approves an unlisted substitute, and answers that
/// cite lines outside their batch are dropped.
library;

import 'dart:convert';

import '../bom.dart';
import '../bom_compare.dart';
import '../params.dart';
import 'provider.dart';
import 'batching.dart';

/// What may leave the machine.
class PrivacyOptions {
  const PrivacyOptions({this.partNumbers = true, this.designators = true, this.otherColumns = false});

  /// Part numbers as written; otherwise aliases (L1, R1 …).
  final bool partNumbers;

  /// Designator lists; otherwise only their count.
  final bool designators;

  /// Values of the other compared columns.
  final bool otherColumns;

  Map<String, dynamic> toJson() => {'partNumbers': partNumbers, 'designators': designators, 'otherColumns': otherColumns};
  factory PrivacyOptions.fromJson(Map<String, dynamic> j) =>
      PrivacyOptions(partNumbers: j['partNumbers'] != false, designators: j['designators'] != false, otherColumns: j['otherColumns'] == true);
}

/// Progress and outcome of the cloud part of a check.
class CloudRun {
  int batches = 0;
  int batchesDone = 0;
  int batchesFailed = 0;

  /// Lines sent, lines the cloud changed, answers dropped as invalid.
  int linesSent = 0;
  int linesResolved = 0;
  int dropped = 0;
  final usage = Usage();
  final errors = <String>[];

  bool get complete => batchesFailed == 0 && batchesDone == batches;
}

const _system = '''You are an electronics manufacturing engineer checking two bills of materials (BOM 1 and BOM 2) against each other.
A local program already compared them and could not settle the items below. For each item:
- "pair" items: decide whether the line of BOM 1 and the line of BOM 2 describe the same physical part (same component, same values and package), regardless of language or wording. Answer same = yes / no / unsure.
- "unmatched" items: the line of BOM 1 has no counterpart yet; choose the candidate from BOM 2 that is the same physical part, or none.
Only cite ids given to you. Say unsure when the text does not let you decide. Explain briefly in Chinese.
JSON shape example: {"answers":[{"id":"i1","same":"unsure","reason":"需确认"}]}. Replace the example id with actual ids in this request.''';

const _schema = {
  'type': 'object',
  'properties': {
    'answers': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'same': {'type': 'string', 'enum': ['yes', 'no', 'unsure']},
          'counterpart': {'type': 'string'},
          'reason': {'type': 'string'},
        },
        'required': ['id', 'same', 'reason'],
      },
    },
  },
  'required': ['answers'],
};

class _Item {
  _Item(this.id, this.row, this.candidates);

  final String id;
  final CompareRow row;

  /// For unmatched lines: possible counterparts (rows that only BOM 2 has).
  final List<CompareRow> candidates;
}

String _alias(Map<String, String> aliases, String pn, String prefix) => aliases.putIfAbsent(pn, () => '$prefix${aliases.length + 1}');

Map<String, dynamic> _side(BomPart p, PrivacyOptions o, Map<String, String> aliases, String prefix, Map<String, String> compared) => {
  'partNo': o.partNumbers ? p.partNo : _alias(aliases, p.partNo, prefix),
  'description': p.description.length > 200 ? p.description.substring(0, 200) : p.description,
  if (p.quantity != null) 'quantity': formatQuantity(p.quantity),
  if (p.refs.isNotEmpty) o.designators ? 'designators' : 'designatorCount': o.designators ? p.refs.take(40).join(',') : p.refs.length,
  if (o.otherColumns)
    for (final e in compared.entries)
      if ((p.extra[e.key] ?? '').isNotEmpty) e.value: p.extra[e.key],
};

/// Rows of [r] worth asking about.
bool needsCloud(CompareRow r) => r.status == CheckStatus.review || (r.status == CheckStatus.unmatched && r.single != null);

/// Up to [n] lines only BOM 2 has, most alike to [p] first (shared
/// parameters, then shared words).
List<CompareRow> _candidates(BomPart p, List<CompareRow> pool, int n) {
  final pp = extractParams(p.description);
  final words = p.description.toLowerCase().split(RegExp(r'[\s,;/]+')).where((w) => w.length > 1).toSet();
  double score(CompareRow r) {
    final q = r.merged!;
    final qp = extractParams(q.description);
    final shared = pp.where((x) => qp.any(x.sameAs)).length;
    final conflict = compareParams(p.description, q.description).verdict == ParamVerdict.conflict;
    final qw = q.description.toLowerCase().split(RegExp(r'[\s,;/]+')).toSet();
    return (conflict ? -10 : 0) + shared * 2 + words.intersection(qw).length + (p.kind == q.kind ? 1 : 0);
  }

  final sorted = [...pool]..sort((a, b) => score(b).compareTo(score(a)));
  return sorted.take(n).toList();
}

/// Asks the cloud about the unsettled lines of [local] and returns the
/// report with the answers that passed the program's checks applied.
Future<(CompareReport, CloudRun)> hybridCheck(
  CompareReport local,
  CloudProvider provider, {
  PrivacyOptions privacy = const PrivacyOptions(),
  int batchSize = 8,
  CloudCancel? cancel,
  void Function(CloudRun)? onProgress,
}) async {
  final run = CloudRun();
  final onlyRight = [for (final r in local.rows) if (r.status == CheckStatus.unmatched && r.single == null) r];
  final items = <_Item>[];
  for (final r in local.rows) {
    if (!needsCloud(r)) continue;
    final id = 'i${items.length + 1}';
    items.add(_Item(id, r, r.status == CheckStatus.unmatched ? _candidates(r.single!, onlyRight, 5) : const []));
  }
  if (items.isEmpty) return (local, run);
  final aliases = <String, String>{};
  final batches = [for (var i = 0; i < items.length; i += batchSize) items.sublist(i, i + batchSize > items.length ? items.length : i + batchSize)];
  run.batches = batches.length;
  onProgress?.call(run);

  // Answers that passed the checks: item id → (same, counterpart row, reason).
  final accepted = <String, (String, CompareRow?, String)>{};
  for (final initial in batches) {
    if (cancel?.cancelled ?? false) break;
    await adaptiveCloudBatch<_Item>(initial, request: (batch) {
    final payload = [
      for (final it in batch)
        {
          'id': it.id,
          'type': it.row.status == CheckStatus.unmatched ? 'unmatched' : 'pair',
          'bom1': _side(it.row.single!, privacy, aliases, 'L', local.compared),
          if (it.row.merged != null) 'bom2': _side(it.row.merged!, privacy, aliases, 'R', local.compared),
          if (it.row.reasons.isNotEmpty) 'programNotes': it.row.reasons,
          if (it.candidates.isNotEmpty)
            'candidates': [
              for (var k = 0; k < it.candidates.length; k++) {'id': '${it.id}c${k + 1}', ..._side(it.candidates[k].merged!, privacy, aliases, 'R', local.compared)},
            ],
        },
    ];
      return provider.ask(system: '$_system\nKeep each reason concise (at most 80 Chinese characters).', user: payloadText(payload), schema: _schema, maxTokens: 1024 + 256 * batch.length, cancel: cancel);
    }, onReply: (batch, reply) {
      run.linesSent += batch.length;
      run.usage.add(reply.usage);
      final byId = {for (final it in batch) it.id: it};
      for (final a in (reply.json['answers'] as List? ?? const [])) {
        if (a is! Map) continue;
        final it = byId['${a['id']}'];
        // An id outside this batch, or a counterpart not offered: dropped.
        if (it == null) {
          run.dropped++;
          continue;
        }
        final same = '${a['same']}';
        CompareRow? counterpart;
        final c = '${a['counterpart'] ?? ''}'.trim();
        if (c.isNotEmpty && c != 'none') {
          final k = int.tryParse(c.replaceFirst('${it.id}c', '')) ?? 0;
          if (!c.startsWith('${it.id}c') || k < 1 || k > it.candidates.length) {
            run.dropped++;
            continue;
          }
          counterpart = it.candidates[k - 1];
        }
        accepted[it.id] = (same, counterpart, '${a['reason'] ?? ''}');
      }
      run.batchesDone++;
      onProgress?.call(run);
    }, onError: (batch, e) {
      run.linesSent += batch.length;
      run.batchesFailed++;
      run.errors.add(e.code);
      if (e.usage != null) run.usage.add(e.usage!);
      onProgress?.call(run);
    }, onSplit: (e) {
      run.batches++;
      if (e.usage != null) run.usage.add(e.usage!);
      onProgress?.call(run);
    }, cancel: cancel);
  }

  // Apply what the program can verify.
  final byRow = {for (final it in items) it.row: it};
  final usedCounterparts = <CompareRow>{};
  final rows = <CompareRow>[];
  final removed = <CompareRow>{};
  for (final r in local.rows) {
    final it = byRow[r];
    final ans = it == null ? null : accepted[it.id];
    if (it == null) {
      if (!removed.contains(r)) rows.add(r);
      continue;
    }
    if (ans == null) {
      // Not answered (failed batch or skipped): local result, marked.
      rows.add(_withReasons(r, [...r.reasons, 'cloud_missing']));
      continue;
    }
    final (same, counterpart, why) = ans;
    if (r.status == CheckStatus.review) {
      final settledByWords = r.reasons.every((x) => x == 'wording_unsure' || x == 'weak_match');
      final p = r.single!, q = r.merged!;
      final kindsOk = p.kind == q.kind || p.kind == ItemKind.unknown || q.kind == ItemKind.unknown;
      final noConflict = compareParams(p.description, q.description).verdict != ParamVerdict.conflict;
      if (same == 'yes' && settledByWords && kindsOk && noConflict) {
        run.linesResolved++;
        rows.add(_resolved(r, CheckStatus.pass, [], why));
      } else {
        rows.add(_withReasons(r, [...r.reasons, if (same == 'yes') 'cloud_same' else if (same == 'no') 'cloud_different' else 'cloud_unsure'], note: why));
      }
      continue;
    }
    // Unmatched line of BOM 1 with a proposed counterpart.
    if (counterpart != null && same == 'yes' && !usedCounterparts.contains(counterpart)) {
      final p = r.single!, q = counterpart.merged!;
      final kindsOk = p.kind == q.kind || p.kind == ItemKind.unknown || q.kind == ItemKind.unknown;
      if (kindsOk && compareParams(p.description, q.description).verdict != ParamVerdict.conflict) {
        usedCounterparts.add(counterpart);
        removed.add(counterpart);
        rows.removeWhere((x) => identical(x, counterpart));
        run.linesResolved++;
        rows.add(_paired(r, counterpart, why));
        continue;
      }
    }
    rows.add(_withReasons(r, [...r.reasons, if (counterpart == null && same != 'yes') 'cloud_no_counterpart'], note: why));
  }
  return (
    CompareReport(rows: rows, compared: local.compared, singleOnlyColumns: local.singleOnlyColumns, mergedOnlyColumns: local.mergedOnlyColumns, at: local.at, uncovered: local.uncovered, skipped: local.skipped),
    run,
  );
}

/// The batch as sent (compact JSON).
String payloadText(List<Map<String, dynamic>> payload) => jsonEncode(payload);

CompareRow _withReasons(CompareRow r, List<String> reasons, {String note = ''}) => CompareRow(
  partNo: r.partNo,
  status: r.status,
  single: r.single,
  merged: r.merged,
  singleParts: r.singleParts,
  mergedParts: r.mergedParts,
  sources: r.sources,
  fields: r.fields,
  missingRefs: r.missingRefs,
  extraRefs: r.extraRefs,
  movedRefs: r.movedRefs,
  basis: r.basis,
  reasons: reasons,
  cloudNote: note,
);

CompareRow _resolved(CompareRow r, CheckStatus status, List<String> reasons, String note) => CompareRow(
  partNo: r.partNo,
  status: status,
  single: r.single,
  merged: r.merged,
  singleParts: r.singleParts,
  mergedParts: r.mergedParts,
  sources: r.sources,
  fields: r.fields,
  missingRefs: r.missingRefs,
  extraRefs: r.extraRefs,
  movedRefs: r.movedRefs,
  basis: MatchBasis([...r.basis.kinds, 'cloud'], r.basis.confidence),
  reasons: reasons,
  cloudNote: note,
);

/// An unmatched line paired with the counterpart the cloud proposed: always
/// REVIEW, with the fields compared by the program.
CompareRow _paired(CompareRow left, CompareRow right, String note) {
  final s = left.single!, m = right.merged!;
  final desc = compareDescription(s.description, m.description);
  final qty = compareExact('quantity', '', formatQuantity(s.quantity), formatQuantity(m.quantity));
  return CompareRow(
    partNo: s.partNo,
    status: CheckStatus.review,
    single: s,
    merged: m,
    singleParts: left.singleParts,
    mergedParts: right.mergedParts,
    sources: right.sources,
    fields: [desc, if (s.quantity != null && m.quantity != null) qty],
    missingRefs: const [],
    extraRefs: const [],
    movedRefs: const {},
    basis: const MatchBasis(['cloud'], 0.5),
    reasons: ['weak_match', if (s.partNo != m.partNo) 'pn_differs', if (!desc.equal) 'desc_text', if (s.quantity != null && m.quantity != null && !qty.equal) 'qty'],
    cloudNote: note,
  );
}
