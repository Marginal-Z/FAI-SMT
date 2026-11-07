/// AI check: sends the part-by-part comparison to a language model (an
/// OpenAI-compatible endpoint or Anthropic) and reads back an analysis with
/// the differing fields it found.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'bom.dart';
import 'bom_compare.dart';

enum AiProvider { openai, anthropic }

class AiConfig {
  AiConfig({this.provider = AiProvider.openai, this.baseUrl = '', this.apiKey = '', this.model = ''});

  AiProvider provider;

  /// Empty: the provider's public endpoint.
  String baseUrl;
  String apiKey;

  /// Empty: the provider's default model.
  String model;

  static const openaiUrl = 'https://api.openai.com/v1';
  static const anthropicUrl = 'https://api.anthropic.com';
  static const openaiModel = 'gpt-4o-mini';
  static const anthropicModel = 'claude-sonnet-5-5';

  bool get ready => apiKey.trim().isNotEmpty || (provider == AiProvider.openai && baseUrl.trim().isNotEmpty);
  String get url => (baseUrl.trim().isEmpty ? (provider == AiProvider.openai ? openaiUrl : anthropicUrl) : baseUrl.trim()).replaceAll(RegExp(r'/+$'), '');
  String get modelName => model.trim().isNotEmpty ? model.trim() : (provider == AiProvider.openai ? openaiModel : anthropicModel);

  Map<String, dynamic> toJson() => {'provider': provider.name, 'baseUrl': baseUrl, 'apiKey': apiKey, 'model': model};

  factory AiConfig.fromJson(Map<String, dynamic> j) => AiConfig(
    provider: AiProvider.values.firstWhere((p) => p.name == j['provider'], orElse: () => AiProvider.openai),
    baseUrl: j['baseUrl'] as String? ?? '',
    apiKey: j['apiKey'] as String? ?? '',
    model: j['model'] as String? ?? '',
  );
}

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
  AiResult({required this.summary, required this.findings, required this.model, required this.at});

  final String summary;
  final List<AiFinding> findings;
  final String model;
  final DateTime at;

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
「single」是单 BOM（基准），「merged」是 A-BOM 与 B-BOM 合并后的结果。
请逐项检查并找出所有不一致与潜在问题：
1. 料号缺失或多出（只在一侧出现）。
2. 用量不一致；用量与位号数量不符。
3. 位号缺失、多出、重复，或同一位号出现在不同料号下。
4. 物料描述：只比较参数（阻值、容值、电感量、电压、功率、精度、温度系数、封装尺寸、型号等英文与数字）。中文名称多一个字、少一个字或长短不同但参数一致视为一致；参数不同必须指出。参数写法不同但等价（如 10K 与 10KΩ、0.1uF 与 100nF）请说明是否等价。
5. 其他列（extra）的内容必须完全一致，任何不同都要指出。
只输出一个 JSON 对象，不要输出其他文字：
{"summary":"中文总结：整体是否一致、主要问题与建议","findings":[{"partNo":"料号","field":"description|quantity|refs|partNo|其他列名","side":"single|merged|both","severity":"error|warning|info","message":"中文说明","singleValue":"单BOM中的值","mergedValue":"A+B中的值"}]}
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
        if (!big || r.status != DiffStatus.same)
          {
            'partNo': r.partNo,
            'localResult': r.status.name,
            if (r.differences.isNotEmpty) 'localDifferences': [for (final f in r.differences) f.key.startsWith('col:') ? f.header : f.key],
            'single': side(r.single),
            'merged': side(r.merged),
          },
    ],
    if (big) 'matchingPartNumbers': [for (final r in report.rows) if (r.status == DiffStatus.same) r.partNo],
  });
}

Future<String> _post(AiConfig cfg, String system, String user, {Duration timeout = const Duration(seconds: 180)}) async {
  if (!cfg.ready) throw AiException('ai_not_configured');
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
  try {
    final anthropic = cfg.provider == AiProvider.anthropic;
    final uri = Uri.parse(anthropic ? '${cfg.url}/v1/messages' : '${cfg.url}/chat/completions');
    final req = await client.postUrl(uri).timeout(timeout);
    req.headers.contentType = ContentType.json;
    if (anthropic) {
      req.headers.set('x-api-key', cfg.apiKey.trim());
      req.headers.set('anthropic-version', '2023-06-01');
    } else if (cfg.apiKey.trim().isNotEmpty) {
      req.headers.set('authorization', 'Bearer ${cfg.apiKey.trim()}');
    }
    final body = anthropic
        ? {
            'model': cfg.modelName,
            'max_tokens': 8192,
            'system': system,
            'messages': [
              {'role': 'user', 'content': user},
            ],
          }
        : {
            'model': cfg.modelName,
            'temperature': 0,
            'messages': [
              {'role': 'system', 'content': system},
              {'role': 'user', 'content': user},
            ],
          };
    req.add(utf8.encode(jsonEncode(body)));
    final res = await req.close().timeout(timeout);
    final text = await res.transform(utf8.decoder).join().timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw AiException('ai_http', '${res.statusCode} ${_clip(text, 300)}');
    }
    final j = jsonDecode(text) as Map<String, dynamic>;
    if (anthropic) {
      final content = j['content'] as List? ?? const [];
      return content.whereType<Map>().where((b) => b['type'] == 'text').map((b) => '${b['text']}').join();
    }
    final choices = j['choices'] as List? ?? const [];
    if (choices.isEmpty) throw AiException('ai_bad_reply', _clip(text, 300));
    return '${(choices.first as Map)['message']?['content'] ?? ''}';
  } on TimeoutException {
    throw AiException('ai_timeout');
  } on SocketException catch (e) {
    throw AiException('ai_network', e.message);
  } on HttpException catch (e) {
    throw AiException('ai_network', e.message);
  } on FormatException catch (e) {
    throw AiException('ai_bad_reply', e.message);
  } finally {
    client.close(force: true);
  }
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

Future<AiResult> runAiCheck(AiConfig cfg, CompareReport report) async {
  final reply = await _post(cfg, _system, comparisonJson(report));
  final j = extractJson(reply);
  return AiResult(
    summary: '${j['summary'] ?? ''}'.trim(),
    findings: [for (final f in (j['findings'] as List? ?? const [])) if (f is Map) AiFinding.fromJson(f.cast<String, dynamic>())],
    model: cfg.modelName,
    at: DateTime.now(),
  );
}

/// A short request to check the endpoint, key and model.
Future<String> testAi(AiConfig cfg) => _post(cfg, 'Reply with the single word OK.', 'OK?', timeout: const Duration(seconds: 40));
