/// Every local result row needs a complete language-model decision before the
/// report can be published. Deterministic findings remain hard constraints.
library;

import 'dart:convert';

import '../bom.dart';
import '../bom_compare.dart';
import 'local_ai.dart';

class LocalReviewResult {
  const LocalReviewResult(this.report, this.rows, this.calls);
  final CompareReport report;
  final int rows;
  final int calls;
}

const _system =
    '''你是 SMT 首件 BOM 核对工程师。逐项分析本批 rows 中每一项：基准 BOM 的 single 与待核 BOM 的 merged。
结合物料描述（包括中文颜色、极性、材质）、型号、参数、数量、位号、厂商及贴装状态判断 pass/ng/review/unmatched/substitute。
只有两侧资料充分且一致才能 pass，信息不足或无法确定必须 review；仅一侧有物料时 unmatched。
遵守 skipped 中关闭的检查字段。不要把 BOM 一致当成已经确认实物方向。每一行必须回答且只回答一次，只引用当前行 id。
reason 用简短中文写出本行判断依据，不要抄写整段输入。仅输出 JSON：
{"rows":[{"id":"i1","verdict":"review","reason":"资料不足，需复核"}]}。示例 id 必须替换为本批实际 id。''';

Map<String, dynamic> _side(BomPart? p) => p == null
    ? {}
    : {
        'partNo': p.partNo,
        'description': p.description,
        if (p.sourceDescriptions.length > 1)
          'sourceDescriptions': p.sourceDescriptions,
        'quantity': p.quantity == null ? null : formatQuantity(p.quantity),
        'refs': p.refs,
        'dnp': p.dnp,
        'other': {
          for (final e in p.extra.entries)
            if (!isReferenceColumn(e.key)) e.key: e.value,
        },
      };

/// Model analysis covers PASS, NG, REVIEW and both sides' unmatched rows. A
/// truncated, missing, duplicate or out-of-batch answer cannot finish a check.
Future<LocalReviewResult> reviewLocally(
  CompareReport draft,
  LocalModels model, {
  bool Function()? cancelled,
  void Function(int done, int total, int calls)? onProgress,
}) async {
  if (draft.rows.isEmpty || !draft.complete) {
    throw LocalAiException('incomplete');
  }
  final ids = {
    for (var i = 0; i < draft.rows.length; i++) 'i${i + 1}': draft.rows[i],
  };
  final decisions = <String, (String, String)>{};
  var calls = 0;
  void checkCancelled() {
    if (cancelled?.call() ?? false) throw LocalAiException('cancelled');
  }

  String payload(List<String> batch) => jsonEncode({
    'skipped': draft.skipped,
    'columns': {
      for (final e in draft.compared.entries)
        if (!isReferenceColumn(e.key, e.value)) e.key: e.value,
    },
    'rows': [
      for (final id in batch)
        {
          'id': id,
          'single': _side(ids[id]!.single),
          'merged': _side(ids[id]!.merged),
        },
    ],
  });

  Future<void> analyze(List<String> batch) async {
    checkCancelled();
    final schema = <String, dynamic>{
      'type': 'object',
      'properties': {
        'rows': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'id': {'type': 'string', 'enum': batch},
              'verdict': {
                'type': 'string',
                'enum': ['pass', 'ng', 'review', 'unmatched', 'substitute'],
              },
              'reason': {'type': 'string'},
            },
            'required': ['id', 'verdict', 'reason'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['rows'],
      'additionalProperties': false,
    };
    try {
      calls++;
      onProgress?.call(decisions.length, ids.length, calls);
      final answer = await model.structured(
        system: _system,
        user: payload(batch),
        schema: schema,
        maxTokens: 512 + 256 * batch.length,
      );
      checkCancelled();
      final rows = answer['rows'];
      if (rows is! List || rows.length != batch.length) {
        throw LocalAiException('incomplete');
      }
      final checked = <String, (String, String)>{};
      for (final row in rows) {
        if (row is! Map ||
            row['id'] is! String ||
            row['reason'] is! String ||
            !batch.contains(row['id']) ||
            checked.containsKey(row['id']) ||
            !const [
              'pass',
              'ng',
              'review',
              'unmatched',
              'substitute',
            ].contains(row['verdict']) ||
            (row['reason'] as String).trim().isEmpty) {
          throw LocalAiException('incomplete');
        }
        checked[row['id'] as String] = (
          '${row['verdict']}',
          (row['reason'] as String).trim(),
        );
      }
      decisions.addAll(checked);
      onProgress?.call(decisions.length, ids.length, calls);
    } on LocalAiException catch (e) {
      if (batch.length <= 1 ||
          !const [
            'incomplete',
            'bad_output',
            'truncated',
            'context_limit',
          ].contains(e.code)) {
        rethrow;
      }
      final middle = batch.length ~/ 2;
      await analyze(batch.sublist(0, middle));
      await analyze(batch.sublist(middle));
    }
  }

  var batch = <String>[];
  for (final id in ids.keys) {
    if (batch.isNotEmpty &&
        (batch.length >= 4 ||
            utf8.encode(payload([...batch, id])).length > 6000)) {
      await analyze(batch);
      batch = [];
    }
    batch.add(id);
  }
  if (batch.isNotEmpty) await analyze(batch);
  checkCancelled();
  if (decisions.length != ids.length) throw LocalAiException('incomplete');
  return LocalReviewResult(
    CompareReport(
      rows: [
        for (final e in ids.entries)
          _decision(e.value, decisions[e.key]!.$1, decisions[e.key]!.$2),
      ],
      compared: draft.compared,
      singleOnlyColumns: draft.singleOnlyColumns,
      mergedOnlyColumns: draft.mergedOnlyColumns,
      at: draft.at,
      skipped: draft.skipped,
      uncovered: draft.uncovered,
    ),
    decisions.length,
    calls,
  );
}

CompareRow _decision(CompareRow r, String verdict, String note) {
  var status = r.status;
  final reasons = [...r.reasons];
  // A model cannot approve a measured conflict, missing data or an unlisted
  // substitute. It can independently flag a problem in an otherwise PASS row.
  if (r.single == null || r.merged == null) {
    status = CheckStatus.unmatched;
    if (verdict == 'pass') reasons.add('local_ai_contradicted');
  } else if (r.status == CheckStatus.ng) {
    if (verdict == 'pass') reasons.add('local_ai_contradicted');
  } else if (verdict == 'review') {
    status = CheckStatus.review;
    reasons.add('local_ai_review');
  } else if (verdict == 'ng') {
    status = CheckStatus.review;
    reasons.add('local_ai_different');
  } else if (verdict == 'pass' &&
      r.status == CheckStatus.review &&
      r.basis.firm &&
      reasons.isNotEmpty &&
      reasons.every((r) => r == 'wording_unsure' || r == 'desc_text') &&
      r.fields.every((f) => !f.incomplete)) {
    status = CheckStatus.pass;
    reasons.clear();
  } else if ((verdict == 'unmatched' && r.single != null && r.merged != null) ||
      (verdict == 'pass' && (r.single == null || r.merged == null)) ||
      (verdict == 'substitute' && r.status != CheckStatus.substitute)) {
    status = CheckStatus.review;
    reasons.add('local_ai_review');
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
    basis: MatchBasis([...r.basis.kinds, 'local_ai'], r.basis.confidence),
    reasons: reasons,
    localNote: note,
    cloudNote: r.cloudNote,
  );
}
