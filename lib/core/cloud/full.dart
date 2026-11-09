/// CLOUD_FULL check: the cloud model reads both BOMs' columns and pairs
/// their lines itself, without the program's matching; the program then
/// checks everything it can.
///
/// Checks: column roles must fit the column contents; every line must be
/// answered exactly once, otherwise the check is incomplete; cited lines
/// must exist; a line claimed twice is REVIEW; fields of every pairing are
/// compared by the program, and a conflict it finds outranks a cloud
/// "pass"; a pairing only the cloud supports (another part number, no
/// shared designators) is at most REVIEW. A failed, cut-off or invalid
/// answer leaves the check incomplete; it is never shown as finished.
library;

import 'dart:convert';

import '../bom.dart';
import '../bom_compare.dart';
import '../table_reader.dart';
import 'hybrid.dart' show CloudRun, PrivacyOptions;
import 'provider.dart';
import 'batching.dart';

const _roles = ['partNo', 'description', 'quantity', 'refs', 'serial', 'mpn', 'maker', 'alternate', 'level', 'dnp', 'other'];

const _columnSystem = '''You read the columns of an electronics bill of materials. For every column say what it holds:
partNo (the company's own part number of each line), description, quantity, refs (PCB designators such as R1, C3),
serial (line number), mpn (manufacturer part number), maker (manufacturer), alternate (alternative part numbers),
level (depth in a multi-level BOM), dnp (fitted / not fitted flag), other. Judge from header and values; headers may be missing or in any language.
JSON shape example: {"columns":[{"column":"A","role":"partNo"}]}. Use only the column letters supplied in the current request.''';

const _matchSystem = '''You compare two electronics bills of materials. For every line of BOM 1 in the request, find the line(s) of BOM 2 that are the same physical part
(a part may be split over several lines on one side), or none. Then judge the pair: pass (same part, same quantity, same designators),
ng (same position but something differs: value, package, quantity, designators), review (you cannot tell), unmatched (no counterpart),
substitute (another part number that one BOM lists as an alternate). Only cite ids from the request. Explain briefly in Chinese.
JSON shape example: {"lines":[{"id":"L1","counterparts":["R1"],"verdict":"review","reason":"需确认"}]}. Replace example ids with the actual ids in this request.''';

const _matchSchema = {
  'type': 'object',
  'properties': {
    'lines': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'id': {'type': 'string'},
          'counterparts': {
            'type': 'array',
            'items': {'type': 'string'},
          },
          'verdict': {'type': 'string', 'enum': ['pass', 'ng', 'review', 'unmatched', 'substitute']},
          'reason': {'type': 'string'},
        },
        'required': ['id', 'counterparts', 'verdict', 'reason'],
      },
    },
  },
  'required': ['lines'],
};

String _letter(int c) {
  var n = c + 1, out = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    out = String.fromCharCode(65 + r) + out;
    n = (n - 1) ~/ 26;
  }
  return out;
}

/// The cloud's reading of a sheet's columns, kept only where it fits the
/// contents.
Future<Map<int, BomRole>> cloudColumns(Grid g, CloudProvider provider, CloudRun run, {CloudCancel? cancel}) async {
  final width = g.rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
  final lines = <String>[];
  final letters = <String>[];
  for (var c = 0; c < width; c++) {
    final values = {for (final r in g.rows.take(60)) if (c < r.length && r[c].trim().isNotEmpty) cleanCell(r[c])}.take(10).toList();
    if (values.isEmpty) continue;
    letters.add(_letter(c));
    lines.add('Column ${_letter(c)}: ${values.map((v) => v.length > 40 ? '${v.substring(0, 40)}…' : v).join(' | ')}');
  }
  final replies = <CloudReply>[];
  await adaptiveCloudBatch<String>(letters,
    request: (batch) => provider.ask(
    system: _columnSystem,
    user: 'The first values of each column (the header row, if any, comes first):\n${[for (final c in batch) lines[letters.indexOf(c)]].join('\n')}',
    schema: {
      'type': 'object',
      'properties': {
        'columns': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'column': {'type': 'string', 'enum': batch},
              'role': {'type': 'string', 'enum': _roles},
            },
            'required': ['column', 'role'],
          },
        },
      },
      'required': ['columns'],
    },
    maxTokens: 1024 + 96 * batch.length,
    cancel: cancel,
    ),
    onReply: (_, reply) => replies.add(reply),
    onError: (_, error) => throw error,
    onSplit: (e) { if (e.usage != null) run.usage.add(e.usage!); },
    cancel: cancel,
  );
  final out = <int, BomRole>{};
  for (final reply in replies) {
  run.usage.add(reply.usage);
  for (final item in (reply.json['columns'] as List? ?? const []).whereType<Map>()) {
    final c = letters.indexOf('${item['column']}');
    final role = BomRole.values.where((r) => r.name == '${item['role']}').firstOrNull;
    if (c < 0 || role == null) continue;
    final col = _colIndex(letters[c]);
    final values = [for (final r in g.rows.skip(1)) if (col < r.length) r[col]];
    if (contentFits(role, values)) {
      out[col] = role;
    } else {
      run.dropped++;
    }
  }
  }
  if (cancel?.cancelled ?? false) throw CloudException('cancelled');
  return out;
}

int _colIndex(String letters) {
  var n = 0;
  for (final ch in letters.codeUnits) {
    n = n * 26 + (ch - 64);
  }
  return n - 1;
}

/// Reads both sides with the cloud's column roles and lets the cloud pair
/// the lines; returns the report with the program's checks applied. When
/// anything is missing the report is incomplete.
Future<(CompareReport, CloudRun)> cloudFullCheck(
  List<Grid> singleGrids,
  List<Grid> aGrids,
  List<Grid>? bGrids,
  CloudProvider provider, {
  String singleName = '',
  String aName = '',
  String bName = '',
  PrivacyOptions privacy = const PrivacyOptions(),
  int batchSize = 8,
  CloudCancel? cancel,
  void Function(CloudRun)? onProgress,
  CompareOptions options = const CompareOptions(),
}) async {
  final run = CloudRun();
  // 1. Columns, by the cloud, for the sheet each file would be read from.
  Future<BomDocument> read(List<Grid> grids, String file, String id) async {
    final plain = readBom(grids, file: file, id: id);
    final g = grids.firstWhere((x) => x.name == plain.sheet);
    run.batches++;
    final roles = await cloudColumns(g, provider, run, cancel: cancel);
    run.batchesDone++;
    onProgress?.call(run);
    return readBom(grids, file: file, id: id, overrides: {g.name: roles});
  }

  final BomDocument single, a;
  BomDocument? b;
  try {
    single = await read(singleGrids, singleName, 'S');
    a = await read(aGrids, aName, 'A');
    b = bGrids == null ? null : await read(bGrids, bName, 'B');
  } on CloudException catch (e) {
    run.batchesFailed++;
    run.errors.add(e.code);
    rethrow;
  }

  // 2. Lines, paired by the cloud in batches against every line of the
  // other side.
  final (merged, _) = mergeBoms(a, b);
  final left = single.parts;
  final rightIds = {for (var i = 0; i < merged.length; i++) 'R${i + 1}': merged[i]};
  final leftIds = {for (var i = 0; i < left.length; i++) 'L${i + 1}': left[i]};
  final aliases = <String, String>{};
  Map<String, dynamic> side(String id, BomPart p) => {
    'id': id,
    'partNo': privacy.partNumbers ? p.partNo : aliases.putIfAbsent(p.partNo, () => 'P${aliases.length + 1}'),
    'description': p.description.length > 160 ? p.description.substring(0, 160) : p.description,
    if (p.quantity != null) 'quantity': formatQuantity(p.quantity),
    if (p.refs.isNotEmpty) privacy.designators ? 'designators' : 'designatorCount': privacy.designators ? p.refs.take(60).join(',') : p.refs.length,
    if (p.alternates.isNotEmpty) 'alternates': p.alternates.join(','),
  };
  final bom2 = [for (final e in rightIds.entries) side(e.key, e.value)];
  final answers = <String, (List<String>, String, String)>{};
  final ids = leftIds.keys.toList();
  for (var i = 0; i < ids.length; i += batchSize) {
    if (cancel?.cancelled ?? false) break;
    final initial = ids.sublist(i, i + batchSize > ids.length ? ids.length : i + batchSize);
    run.batches++;
    await adaptiveCloudBatch<String>(initial,
      request: (batch) => provider.ask(
        system: '$_matchSystem\nKeep each reason concise (at most 80 Chinese characters). Do not repeat the input.',
        user: jsonEncode({
          'bom1': [for (final id in batch) side(id, leftIds[id]!)],
          'bom2': bom2,
        }),
        schema: _matchSchema,
        maxTokens: 1024 + 256 * batch.length,
        cancel: cancel,
      ),
      onReply: (batch, reply) {
      run.linesSent += batch.length;
      run.usage.add(reply.usage);
      for (final line in (reply.json['lines'] as List? ?? const []).whereType<Map>()) {
        final id = '${line['id']}';
        final cps = [for (final c in (line['counterparts'] as List? ?? const [])) '$c'];
        // Ids outside this batch, or counterparts that do not exist.
        if (!batch.contains(id) || cps.any((c) => !rightIds.containsKey(c))) {
          run.dropped++;
          continue;
        }
        answers[id] = (cps, '${line['verdict']}', '${line['reason'] ?? ''}');
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

  // 3. The program's checks. A BOM 2 line claimed by two lines of BOM 1
  // is not given to either.
  final claims = <String, int>{};
  for (final (cps, _, _) in answers.values) {
    for (final c in cps) {
      claims[c] = (claims[c] ?? 0) + 1;
    }
  }
  final pairs = <(List<String>, List<String>)>[];
  final notes = <String, (String, String)>{};
  final contested = <String>{};
  for (final e in answers.entries) {
    final (cps, verdict, why) = e.value;
    final p = leftIds[e.key]!;
    notes[p.partNo] = (verdict, why);
    final mine = [for (final c in cps) if (claims[c] == 1) c];
    if (mine.length != cps.length) contested.add(p.partNo);
    if (mine.isNotEmpty) pairs.add(([p.partNo], [for (final c in mine) rightIds[c]!.partNo]));
  }
  final base = compareBoms(single, a, b, pairs: pairs, options: options);
  final unanswered = [for (final e in leftIds.entries) if (!answers.containsKey(e.key)) e.value];
  final rows = [
    for (final r in base.rows)
      _annotate(r, r.single == null ? null : notes[r.single!.partNo], contested.contains(r.single?.partNo), unanswered.any((p) => identical(p, r.single)) || unanswered.any((p) => r.singleParts.contains(p))),
  ];
  // Lines nobody answered for make the check incomplete.
  final uncovered = [...base.uncovered, for (final p in unanswered) ...p.recordIds];
  return (
    CompareReport(rows: rows, compared: base.compared, singleOnlyColumns: base.singleOnlyColumns, mergedOnlyColumns: base.mergedOnlyColumns, at: base.at, uncovered: uncovered, skipped: base.skipped),
    run,
  );
}

/// The program's result for a line, with the cloud's verdict alongside.
CompareRow _annotate(CompareRow r, (String, String)? note, bool contested, bool unanswered) {
  final reasons = [...r.reasons];
  var status = r.status;
  if (unanswered) {
    reasons.add('cloud_missing');
    if (status == CheckStatus.pass) status = CheckStatus.review;
  }
  if (contested) {
    reasons.add('cloud_conflict');
    if (status == CheckStatus.pass) status = CheckStatus.review;
  }
  if (note != null) {
    final (verdict, _) = note;
    // The cloud saw a difference the program cannot confirm: REVIEW.
    if (verdict == 'ng' && status == CheckStatus.pass) {
      status = CheckStatus.review;
      reasons.add('cloud_says_ng');
    }
    // The cloud said pass where the program found a conflict: the
    // program's result stands, marked.
    if (verdict == 'pass' && status == CheckStatus.ng) reasons.add('cloud_contradicted');
  }
  return CompareRow(
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
    basis: r.basis,
    reasons: reasons,
    cloudNote: note?.$2 ?? '',
  );
}
