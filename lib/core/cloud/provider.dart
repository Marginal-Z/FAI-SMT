/// Cloud AI providers behind one interface: OpenAI, DeepSeek, Anthropic and
/// any OpenAI-compatible endpoint. The checking code asks for a JSON answer
/// matching a schema; this layer handles the request format of each vendor,
/// timeouts, retries, rate limits, cancellation, token and cost counts, a
/// request log, and checks the answer against the schema before returning.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

enum ProviderKind { openai, deepseek, anthropic, custom }

/// Prices in US dollars per million tokens, input and output.
class Price {
  const Price(this.input, this.output);

  final double input;
  final double output;

  Map<String, dynamic> toJson() => {'input': input, 'output': output};
  factory Price.fromJson(Map<String, dynamic> j) => Price((j['input'] as num?)?.toDouble() ?? 0, (j['output'] as num?)?.toDouble() ?? 0);
}

/// Defaults per vendor; base URL, model and prices can all be changed.
class ProviderPreset {
  const ProviderPreset(this.kind, this.baseUrl, this.model, this.price, {this.jsonSchema = true});

  final ProviderKind kind;
  final String baseUrl;
  final String model;

  /// List prices at the time of writing; shown as editable defaults.
  final Price price;

  /// The endpoint accepts `response_format: json_schema`.
  final bool jsonSchema;
}

const providerPresets = {
  ProviderKind.openai: ProviderPreset(ProviderKind.openai, 'https://api.openai.com/v1', 'gpt-4o-mini', Price(0.15, 0.6)),
  ProviderKind.deepseek: ProviderPreset(ProviderKind.deepseek, 'https://api.deepseek.com/v1', 'deepseek-chat', Price(0.27, 1.1), jsonSchema: false),
  ProviderKind.anthropic: ProviderPreset(ProviderKind.anthropic, 'https://api.anthropic.com', 'claude-sonnet-5-5', Price(3, 15)),
  ProviderKind.custom: ProviderPreset(ProviderKind.custom, '', '', Price(0, 0), jsonSchema: false),
};

class ProviderConfig {
  ProviderConfig({this.kind = ProviderKind.openai, this.baseUrl = '', this.model = '', Price? price, this.timeoutSeconds = 180, this.maxRetries = 2, this.minIntervalMs = 300})
    : price = price ?? providerPresets[kind]!.price;

  ProviderKind kind;

  /// Empty: the vendor's default.
  String baseUrl;
  String model;
  Price price;
  int timeoutSeconds;
  int maxRetries;

  /// Smallest gap between two requests (rate limit).
  int minIntervalMs;

  ProviderPreset get preset => providerPresets[kind]!;
  String get url => (baseUrl.trim().isEmpty ? preset.baseUrl : baseUrl.trim()).replaceAll(RegExp(r'/+$'), '');
  String get modelName => model.trim().isEmpty ? preset.model : model.trim();
  bool get anthropic => kind == ProviderKind.anthropic;

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'baseUrl': baseUrl,
    'model': model,
    'price': price.toJson(),
    'timeoutSeconds': timeoutSeconds,
    'maxRetries': maxRetries,
    'minIntervalMs': minIntervalMs,
  };

  factory ProviderConfig.fromJson(Map<String, dynamic> j) {
    final kind = ProviderKind.values.firstWhere((k) => k.name == j['kind'], orElse: () => ProviderKind.openai);
    return ProviderConfig(
      kind: kind,
      baseUrl: j['baseUrl'] as String? ?? '',
      model: j['model'] as String? ?? '',
      price: j['price'] is Map ? Price.fromJson((j['price'] as Map).cast()) : null,
      timeoutSeconds: (j['timeoutSeconds'] as num?)?.toInt() ?? 180,
      maxRetries: (j['maxRetries'] as num?)?.toInt() ?? 2,
      minIntervalMs: (j['minIntervalMs'] as num?)?.toInt() ?? 300,
    );
  }
}

class CloudException implements Exception {
  CloudException(this.code, [this.detail = '']);

  /// `no_key`, `http`, `auth`, `rate_limited`, `server`, `timeout`,
  /// `network`, `bad_reply`, `truncated`, `schema`, `cancelled`.
  final String code;
  final String detail;

  @override
  String toString() => 'CloudException($code) $detail';
}

/// Token counts and cost.
class Usage {
  Usage({this.inputTokens = 0, this.outputTokens = 0, this.cost = 0, this.requests = 0});

  int inputTokens;
  int outputTokens;
  double cost;
  int requests;

  void add(Usage o) {
    inputTokens += o.inputTokens;
    outputTokens += o.outputTokens;
    cost += o.cost;
    requests += o.requests;
  }
}

/// One request, as kept in the log (no prompt text or key).
class RequestRecord {
  RequestRecord({required this.at, required this.provider, required this.model, required this.status, required this.millis, required this.usage, this.error = '', this.attempt = 1});

  final DateTime at;
  final String provider;
  final String model;

  /// HTTP status, 0 when no answer arrived.
  final int status;
  final int millis;
  final Usage usage;
  final String error;
  final int attempt;
}

/// Stops a running request.
class CloudCancel {
  bool _cancelled = false;
  final _onCancel = <void Function()>[];

  bool get cancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final f in [..._onCancel]) {
      f();
    }
  }
}

/// A checked JSON answer.
class CloudReply {
  CloudReply(this.json, this.usage, this.model);

  final Map<String, dynamic> json;
  final Usage usage;
  final String model;
}

/// Checks [value] against the subset of JSON Schema the prompts use: type,
/// properties, required, items, enum, additionalProperties. Returns the
/// path of the first problem, or null.
String? schemaProblem(Object? value, Map<String, dynamic> schema, [String path = r'$']) {
  final type = schema['type'];
  bool isType(String t) => switch (t) {
    'object' => value is Map,
    'array' => value is List,
    'string' => value is String,
    'integer' => value is int || (value is num && value == value.roundToDouble()),
    'number' => value is num,
    'boolean' => value is bool,
    'null' => value == null,
    _ => true,
  };
  if (type is String && !isType(type)) return '$path: expected $type';
  if (type is List && !type.any((t) => isType('$t'))) return '$path: expected ${type.join('|')}';
  final en = schema['enum'];
  if (en is List && !en.contains(value)) return '$path: not one of ${en.join(', ')}';
  if (value is Map) {
    final props = (schema['properties'] as Map?)?.cast<String, dynamic>() ?? const {};
    for (final r in (schema['required'] as List? ?? const [])) {
      if (!value.containsKey(r)) return '$path.$r: missing';
    }
    if (schema['additionalProperties'] == false) {
      for (final k in value.keys) {
        if (!props.containsKey(k)) return '$path.$k: not allowed';
      }
    }
    for (final e in props.entries) {
      if (!value.containsKey(e.key)) continue;
      final p = schemaProblem(value[e.key], (e.value as Map).cast(), '$path.${e.key}');
      if (p != null) return p;
    }
  }
  if (value is List && schema['items'] is Map) {
    for (var i = 0; i < value.length; i++) {
      final p = schemaProblem(value[i], (schema['items'] as Map).cast(), '$path[$i]');
      if (p != null) return p;
    }
  }
  return null;
}

/// The JSON object in a reply (models sometimes wrap it in a code block).
Map<String, dynamic>? jsonIn(String text) {
  final start = text.indexOf('{'), end = text.lastIndexOf('}');
  if (start < 0 || end <= start) return null;
  try {
    final v = jsonDecode(text.substring(start, end + 1));
    return v is Map<String, dynamic> ? v : null;
  } on FormatException {
    return null;
  }
}

abstract class CloudProvider {
  String get name;
  String get model;

  /// A JSON object matching [schema]; throws [CloudException].
  Future<CloudReply> ask({required String system, required String user, required Map<String, dynamic> schema, int maxTokens = 4096, CloudCancel? cancel});
}

/// Talks HTTP to the vendor in [config]; [apiKey] is passed in, never
/// stored here. [onRecord] receives every attempt for the request log.
class HttpCloudProvider implements CloudProvider {
  HttpCloudProvider(this.config, this.apiKey, {this.onRecord, this.client});

  final ProviderConfig config;
  final String apiKey;
  final void Function(RequestRecord)? onRecord;
  /// For tests; a new client per request otherwise.
  final HttpClient? client;
  DateTime? _last;

  @override
  String get name => config.kind.name;

  @override
  String get model => config.modelName;

  @override
  Future<CloudReply> ask({required String system, required String user, required Map<String, dynamic> schema, int maxTokens = 4096, CloudCancel? cancel}) async {
    if (apiKey.trim().isEmpty && config.kind != ProviderKind.custom) throw CloudException('no_key');
    CloudException? last;
    for (var attempt = 1; attempt <= config.maxRetries + 1; attempt++) {
      if (cancel?.cancelled ?? false) throw CloudException('cancelled');
      // Rate limit: keep a gap between requests.
      final now = DateTime.now();
      if (_last != null) {
        final wait = Duration(milliseconds: config.minIntervalMs) - now.difference(_last!);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      _last = DateTime.now();
      try {
        return await _once(system, user, schema, maxTokens, cancel, attempt);
      } on CloudException catch (e) {
        last = e;
        // Worth another try: rate limits, server errors, network trouble,
        // and an answer that broke the schema.
        final retry = const ['rate_limited', 'network', 'timeout', 'server', 'schema', 'bad_reply'].contains(e.code);
        if (!retry || attempt > config.maxRetries) rethrow;
        await Future<void>.delayed(Duration(milliseconds: (400 * math.pow(2, attempt - 1)).round()));
      }
    }
    throw last!;
  }

  Future<CloudReply> _once(String system, String user, Map<String, dynamic> schema, int maxTokens, CloudCancel? cancel, int attempt) async {
    final http = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 20));
    final sw = Stopwatch()..start();
    var status = 0;
    void cancelNow() => http.close(force: true);
    cancel?._onCancel.add(cancelNow);
    try {
      final a = config.anthropic;
      final uri = Uri.parse(a ? '${config.url}/v1/messages' : '${config.url}/chat/completions');
      final req = await http.postUrl(uri).timeout(Duration(seconds: config.timeoutSeconds));
      req.headers.contentType = ContentType.json;
      if (a) {
        req.headers.set('x-api-key', apiKey.trim());
        req.headers.set('anthropic-version', '2023-06-01');
      } else if (apiKey.trim().isNotEmpty) {
        req.headers.set('authorization', 'Bearer ${apiKey.trim()}');
      }
      final schemaNote = '\nReply with one JSON object matching this JSON Schema, and nothing else:\n${jsonEncode(schema)}';
      final body = a
          ? {
              'model': config.modelName,
              'max_tokens': maxTokens,
              'temperature': 0,
              'system': system,
              // A tool whose input is the answer: Anthropic then returns
              // JSON that follows the schema.
              'tools': [
                {'name': 'answer', 'description': 'Give the answer.', 'input_schema': schema},
              ],
              'tool_choice': {'type': 'tool', 'name': 'answer'},
              'messages': [
                {'role': 'user', 'content': user},
              ],
            }
          : {
              'model': config.modelName,
              'temperature': 0,
              'max_tokens': maxTokens,
              'messages': [
                {'role': 'system', 'content': config.preset.jsonSchema ? system : '$system$schemaNote'},
                {'role': 'user', 'content': user},
              ],
              'response_format': config.preset.jsonSchema
                  ? {
                      'type': 'json_schema',
                      'json_schema': {'name': 'answer', 'schema': schema, 'strict': false},
                    }
                  : {'type': 'json_object'},
            };
      req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(Duration(seconds: config.timeoutSeconds));
      status = res.statusCode;
      final text = await res.transform(utf8.decoder).join().timeout(Duration(seconds: config.timeoutSeconds));
      if (status == 401 || status == 403) throw CloudException('auth', _clip(text));
      if (status == 429) throw CloudException('rate_limited', _clip(text));
      if (status >= 500) throw CloudException('server', '$status ${_clip(text)}');
      if (status < 200 || status >= 300) throw CloudException('http', '$status ${_clip(text)}');
      final j = jsonDecode(text) as Map<String, dynamic>;
      final usage = _usage(j);
      Map<String, dynamic>? answer;
      if (a) {
        if (j['stop_reason'] == 'max_tokens') throw CloudException('truncated');
        final blocks = (j['content'] as List? ?? const []).whereType<Map>();
        final tool = blocks.where((b) => b['type'] == 'tool_use').firstOrNull;
        answer = tool != null ? (tool['input'] as Map?)?.cast<String, dynamic>() : jsonIn(blocks.where((b) => b['type'] == 'text').map((b) => '${b['text']}').join());
      } else {
        final choice = ((j['choices'] as List?) ?? const []).cast<Map>().firstOrNull;
        if (choice == null) throw CloudException('bad_reply', _clip(text));
        if (choice['finish_reason'] == 'length') throw CloudException('truncated');
        answer = jsonIn('${(choice['message'] as Map?)?['content'] ?? ''}');
      }
      if (answer == null) throw CloudException('bad_reply', _clip(text));
      final problem = schemaProblem(answer, schema);
      if (problem != null) throw CloudException('schema', problem);
      onRecord?.call(RequestRecord(at: DateTime.now(), provider: name, model: model, status: status, millis: sw.elapsedMilliseconds, usage: usage, attempt: attempt));
      return CloudReply(answer, usage, model);
    } on CloudException catch (e) {
      onRecord?.call(RequestRecord(at: DateTime.now(), provider: name, model: model, status: status, millis: sw.elapsedMilliseconds, usage: Usage(requests: 1), error: '${e.code} ${e.detail}', attempt: attempt));
      if (cancel?.cancelled ?? false) throw CloudException('cancelled');
      rethrow;
    } on TimeoutException {
      onRecord?.call(RequestRecord(at: DateTime.now(), provider: name, model: model, status: status, millis: sw.elapsedMilliseconds, usage: Usage(requests: 1), error: 'timeout', attempt: attempt));
      throw CloudException('timeout');
    } on SocketException catch (e) {
      if (cancel?.cancelled ?? false) throw CloudException('cancelled');
      onRecord?.call(RequestRecord(at: DateTime.now(), provider: name, model: model, status: status, millis: sw.elapsedMilliseconds, usage: Usage(requests: 1), error: 'network ${e.message}', attempt: attempt));
      throw CloudException('network', e.message);
    } on HttpException catch (e) {
      if (cancel?.cancelled ?? false) throw CloudException('cancelled');
      throw CloudException('network', e.message);
    } on FormatException catch (e) {
      throw CloudException('bad_reply', e.message);
    } finally {
      cancel?._onCancel.remove(cancelNow);
      if (client == null) http.close(force: true);
    }
  }

  Usage _usage(Map<String, dynamic> j) {
    final u = (j['usage'] as Map?)?.cast<String, dynamic>() ?? const {};
    final input = ((u['prompt_tokens'] ?? u['input_tokens']) as num?)?.toInt() ?? 0;
    final output = ((u['completion_tokens'] ?? u['output_tokens']) as num?)?.toInt() ?? 0;
    final p = config.price;
    return Usage(inputTokens: input, outputTokens: output, cost: (input * p.input + output * p.output) / 1e6, requests: 1);
  }
}

String _clip(String s) => s.length <= 300 ? s : '${s.substring(0, 300)}…';
