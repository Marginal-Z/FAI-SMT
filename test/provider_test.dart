// Cloud providers against a local fake server.
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/cloud/provider.dart';

import 'support/fake_llm_server.dart';

const schema = {
  'type': 'object',
  'properties': {
    'kind': {'type': 'string', 'enum': ['resistor', 'capacitor']},
    'confidence': {'type': 'number'},
  },
  'required': ['kind'],
  'additionalProperties': false,
};

void main() {
  late FakeLlmServer server;
  final records = <RequestRecord>[];
  setUp(() async {
    server = await FakeLlmServer.start();
    records.clear();
  });
  tearDown(() => server.close());

  HttpCloudProvider provider(ProviderKind kind, {int retries = 2, int timeout = 30}) =>
      HttpCloudProvider(ProviderConfig(kind: kind, baseUrl: server.url, model: 'm1', maxRetries: retries, timeoutSeconds: timeout, minIntervalMs: 0), 'sk-test', onRecord: records.add);

  test('OpenAI: json_schema, bearer key, usage and cost', () async {
    server.replies.add(FakeReply.openai({'kind': 'capacitor', 'confidence': 0.9}, input: 1000000, output: 1000000));
    final r = await provider(ProviderKind.openai).ask(system: 'sys', user: 'MLCC 100nF', schema: schema);
    expect(r.json['kind'], 'capacitor');
    final (path, headers, body) = server.requests.single;
    expect(path, '/chat/completions');
    expect(headers['authorization'], 'Bearer sk-test');
    expect((body['response_format'] as Map)['type'], 'json_schema');
    expect(r.usage.inputTokens, 1000000);
    // Default OpenAI price: 0.15 + 0.6 per million.
    expect(r.usage.cost, closeTo(0.75, 1e-9));
    expect(records.single.status, 200);
  });

  test('DeepSeek: json_object with the schema in the prompt', () async {
    server.replies.add(FakeReply.openai('```json\n{"kind":"resistor"}\n```'));
    final r = await provider(ProviderKind.deepseek).ask(system: 'sys', user: 'u', schema: schema);
    expect(r.json['kind'], 'resistor');
    final body = server.requests.single.$3;
    expect((body['response_format'] as Map)['type'], 'json_object');
    expect(((body['messages'] as List).first as Map)['content'], contains('JSON Schema'));
  });

  test('Anthropic: answer tool, x-api-key, version header', () async {
    server.replies.add(FakeReply.anthropic({'kind': 'resistor'}));
    final r = await provider(ProviderKind.anthropic).ask(system: 'sys', user: 'u', schema: schema);
    expect(r.json['kind'], 'resistor');
    final (path, headers, body) = server.requests.single;
    expect(path, '/v1/messages');
    expect(headers['x-api-key'], 'sk-test');
    expect(headers['anthropic-version'], '2023-06-01');
    expect((body['tool_choice'] as Map)['name'], 'answer');
    expect(r.usage.outputTokens, 60);
  });

  test('rate limited: retried, every attempt logged', () async {
    server.replies
      ..add(const FakeReply(429, {'error': 'slow down'}))
      ..add(FakeReply.openai({'kind': 'resistor'}));
    final r = await provider(ProviderKind.openai).ask(system: 's', user: 'u', schema: schema);
    expect(r.json['kind'], 'resistor');
    expect(records.map((x) => x.status), [429, 200]);
    expect(records.first.error, startsWith('rate_limited'));
  });

  test('a reply that breaks the schema is retried, then refused', () async {
    for (var i = 0; i < 3; i++) {
      server.replies.add(FakeReply.openai({'kind': 'inductor'}));
    }
    await expectLater(provider(ProviderKind.openai).ask(system: 's', user: 'u', schema: schema), throwsA(isA<CloudException>().having((e) => e.code, 'code', 'schema')));
    expect(server.requests, hasLength(3));
  });

  test('a cut-off reply is an error, never a partial answer', () async {
    server.replies.add(FakeReply.openai('{"kind": "resis', finish: 'length'));
    await expectLater(provider(ProviderKind.openai).ask(system: 's', user: 'u', schema: schema), throwsA(isA<CloudException>().having((e) => e.code, 'code', 'truncated')));
    server.replies.add(FakeReply.anthropic({'kind': 'resistor'}, stop: 'max_tokens'));
    await expectLater(provider(ProviderKind.anthropic).ask(system: 's', user: 'u', schema: schema), throwsA(isA<CloudException>().having((e) => e.code, 'code', 'truncated')));
  });

  test('a wrong key is not retried', () async {
    server.replies.add(const FakeReply(401, {'error': 'invalid key'}));
    await expectLater(provider(ProviderKind.openai).ask(system: 's', user: 'u', schema: schema), throwsA(isA<CloudException>().having((e) => e.code, 'code', 'auth')));
    expect(server.requests, hasLength(1));
  });

  test('cancel and timeout', () async {
    server.replies.add(FakeReply(200, FakeReply.openai({'kind': 'resistor'}).body, delay: const Duration(seconds: 5)));
    final cancel = CloudCancel();
    final f = provider(ProviderKind.openai, retries: 0).ask(system: 's', user: 'u', schema: schema, cancel: cancel);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    cancel.cancel();
    await expectLater(f, throwsA(isA<CloudException>().having((e) => e.code, 'code', 'cancelled')));
    server.replies.add(FakeReply(200, FakeReply.openai({'kind': 'resistor'}).body, delay: const Duration(seconds: 3)));
    await expectLater(provider(ProviderKind.openai, retries: 0, timeout: 1).ask(system: 's', user: 'u', schema: schema), throwsA(isA<CloudException>().having((e) => e.code, 'code', 'timeout')));
  });

  test('no key: refused before sending anything', () async {
    final p = HttpCloudProvider(ProviderConfig(kind: ProviderKind.openai, baseUrl: server.url), '');
    await expectLater(p.ask(system: 's', user: 'u', schema: schema), throwsA(isA<CloudException>().having((e) => e.code, 'code', 'no_key')));
    expect(server.requests, isEmpty);
  });

  test('schema check', () {
    expect(schemaProblem({'kind': 'resistor'}, schema), isNull);
    expect(schemaProblem({'kind': 'x'}, schema), contains('not one of'));
    expect(schemaProblem({'confidence': 1}, schema), contains('missing'));
    expect(schemaProblem({'kind': 'resistor', 'extra': 1}, schema), contains('not allowed'));
  });
}
