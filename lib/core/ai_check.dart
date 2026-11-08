/// AI check: sends the finished comparison to the configured cloud model
/// and reads back an analysis with the findings, checked against the
/// schema and against the parts that exist.
library;

import 'dart:convert';

import 'bom.dart';
import 'bom_compare.dart';
import 'cloud/provider.dart';

enum AiSeverity { error, warning, info }

class AiFinding {
  AiFinding({required this.partNo, required this.field, required this.side, required this.severity, required this.message, this.singleValue = '', this.mergedValue = ''});

  final String partNo;

  /// `description`, `quantity`, `refs`, `partNo` or another column's header.
  final String field;

  /// `single`, `merged` or `both`.
  final String side;
  final AiSeverity severity;
  final String message;
  final String singleValue;
  final String mergedValue;

  factory AiFinding.fromJson(Map<String, dynamic> j) => AiFinding(
    partNo: '${j['partNo'] ?? ''}'.trim(),
    field: '${j['field'] ?? ''}'.trim(),
    side: '${j['side'] ?? 'both'}'.trim(),
    severity: AiSeverity.values.firstWhere((s) => s.name == '${j['severity']}'.trim().toLowerCase(), orElse: () => AiSeverity.warning),
    message: '${j['message'] ?? ''}'.trim(),
    singleValue: '${j['singleValue'] ?? ''}'.trim(),
    mergedValue: '${j['mergedValue'] ?? ''}'.trim(),
  );
}

class AiResult {
  AiResult({required this.summary, required this.findings, required this.model, required this.at, this.dropped = 0, Usage? usage}) : usage = usage ?? Usage();

  final String summary;
  final List<AiFinding> findings;

  /// Findings that named parts not in the check, left out.
  final int dropped;
  final String model;
  final DateTime at;
  final Usage usage;

  Iterable<AiFinding> forPart(String pn) => findings.where((f) => f.partNo == pn);
}

class AiException implements Exception {
  AiException(this.code, [this.detail = '']);

  /// `ai_not_configured`, `ai_http`, `ai_timeout`, `ai_bad_reply`, `ai_network`.
  final String code;
  final String detail;

  @override
  String toString() => 'AiException($code) $detail';
}

const _system = '''你是电子制造（SMT）BOM 核对专家。用户给出两份 BOM 按料号逐项对比的数据：
「single」是 A-BOM（基准），「merged」是 B-BOM 与 C-BOM 合并后的结果。
请逐项检查并找出所有不一致与潜在问题：
1. 料号缺失或多出（只在一侧出现）。
2. 用量不一致；用量与位号数量不符。
3. 位号缺失、多出、重复，或同一位号出现在不同料号下。
4. 物料描述：只比较参数（阻值、容值、电感量、电压、功率、精度、温度系数、封装尺寸、型号等英文与数字）。中文名称多一个字、少一个字或长短不同但参数一致视为一致；参数不同必须指出。参数写法不同但等价（如 10K 与 10KΩ、0.1uF 与 100nF）请说明是否等价。
5. 其他列（extra）的内容必须完全一致，任何不同都要指出。
只输出一个 JSON 对象，不要输出其他文字：
{"summary":"中文总结：整体是否一致、主要问题与建议","findings":[{"partNo":"料号","field":"description|quantity|refs|partNo|其他列名","side":"single|merged|both","severity":"error|warning|info","message":"中文说明","singleValue":"A-BOM 中的值","mergedValue":"B+C 中的值"}]}
没有问题时 findings 为空数组。''';

String _clip(String s, int n) => s.length <= n ? s : '${s.substring(0, n)}…';

/// The comparison as compact JSON for the prompt. Large BOMs send the
/// differing rows in full and only the part numbers of matching rows.
String comparisonJson(CompareReport report) {
  Map<String, dynamic> side(BomPart? p) => p == null
      ? {}
      : {
          'records': p.recordIds,
          'description': _clip(p.description, 160),
          'quantity': formatQuantity(p.quantity),
          'refs': p.refs.join(','),
          if (p.extra.values.any((v) => v.isNotEmpty)) 'extra': {for (final e in p.extra.entries) if (e.value.isNotEmpty) report.compared[e.key] ?? e.key: e.value},
        };
  final big = report.rows.length > 400;
  return jsonEncode({
    'columnsCompared': report.compared.values.toList(),
    'columnsOnlyInSingle': report.singleOnlyColumns,
    'columnsOnlyInMerged': report.mergedOnlyColumns,
    'rows': [
      for (final r in report.rows)
        if (!big || r.status != CheckStatus.pass)
          {
            'partNo': r.partNo,
            'localResult': r.status.name,
            if (r.reasons.isNotEmpty) 'localReasons': r.reasons,
            if (r.basis.kinds.isNotEmpty) 'matchedBy': r.basis.kinds,
            if (r.differences.isNotEmpty) 'localDifferences': [for (final f in r.differences) f.key.startsWith('col:') ? f.header : f.key],
            'single': side(r.single),
            'merged': side(r.merged),
          },
    ],
    if (big) 'matchingPartNumbers': [for (final r in report.rows) if (r.status == CheckStatus.pass) r.partNo],
  });
}

/// Reads the JSON object out of a reply (models sometimes wrap it in a
/// code block or add a sentence).
Map<String, dynamic> extractJson(String reply) {
  final start = reply.indexOf('{'), end = reply.lastIndexOf('}');
  if (start < 0 || end <= start) throw AiException('ai_bad_reply', _clip(reply, 300));
  try {
    return jsonDecode(reply.substring(start, end + 1)) as Map<String, dynamic>;
  } on FormatException {
    throw AiException('ai_bad_reply', _clip(reply, 300));
  }
}

const _schema = {
  'type': 'object',
  'properties': {
    'summary': {'type': 'string'},
    'findings': {
      'type': 'array',
      'items': {
        'type': 'object',
        'properties': {
          'partNo': {'type': 'string'},
          'field': {'type': 'string'},
          'side': {'type': 'string', 'enum': ['single', 'merged', 'both']},
          'severity': {'type': 'string', 'enum': ['error', 'warning', 'info']},
          'message': {'type': 'string'},
          'singleValue': {'type': 'string'},
          'mergedValue': {'type': 'string'},
        },
        'required': ['partNo', 'field', 'severity', 'message'],
      },
    },
  },
  'required': ['summary', 'findings'],
};

/// The analysis of a finished check, from [provider]. Findings that name a
/// part not in the check are dropped: nothing invented reaches the screen.
Future<AiResult> runAiCheck(CloudProvider provider, CompareReport report, {CloudCancel? cancel}) async {
  final reply = await provider.ask(system: _system, user: comparisonJson(report), schema: _schema, maxTokens: 8192, cancel: cancel);
  final known = {for (final r in report.rows) ...[r.partNo, ...r.singleParts.map((p) => p.partNo), ...r.mergedParts.map((p) => p.partNo)]};
  final findings = [
    for (final f in (reply.json['findings'] as List? ?? const []))
      if (f is Map) AiFinding.fromJson(f.cast<String, dynamic>()),
  ];
  return AiResult(
    summary: '${reply.json['summary'] ?? ''}'.trim(),
    findings: [for (final f in findings) if (known.contains(f.partNo)) f],
    dropped: findings.where((f) => !known.contains(f.partNo)).length,
    model: provider.model,
    at: DateTime.now(),
    usage: reply.usage,
  );
}

/// A short request to check the endpoint, key and model.
Future<CloudReply> testCloud(CloudProvider provider) => provider.ask(
  system: 'Reply with the JSON object {"ok": true}.',
  user: 'Test',
  schema: const {
    'type': 'object',
    'properties': {
      'ok': {'type': 'boolean'},
    },
    'required': ['ok'],
  },
  maxTokens: 50,
);
