import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/ai_check.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/core/table_reader.dart';

/// Local server answering with [events] as server-sent events, recording the
/// request it got.
Future<(HttpServer, List<Map<String, Object?>>)> _server(List<String> events, {int status = 200}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final seen = <Map<String, Object?>>[];
  server.listen((req) async {
    final body = await utf8.decoder.bind(req).join();
    seen.add({'path': req.uri.path, 'key': req.headers.value('x-api-key'), 'auth': req.headers.value('authorization'), 'body': jsonDecode(body)});
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType('text', 'event-stream');
    for (final e in events) {
      req.response.add(utf8.encode('data: $e\n\n'));
    }
    await req.response.close();
  });
  return (server, seen);
}

void main() {
  test('tables become numbered text rows', () {
    final (text, cut) = tablesAsText({
      'bom.xlsx': [
        Grid('S1', [
          ['PN', 'Refs', ''],
          [],
          ['K1', 'R1\nR2'],
        ]),
      ],
    });
    expect(text, contains('### bom.xlsx'));
    expect(text, contains('R1: PN | Refs'));
    expect(text, contains('R3: K1 | R1 R2'));
    expect(cut, isFalse);
    expect(tablesAsText({'x': [Grid('s', [for (var i = 0; i < 100; i++) ['abcdefghij']])]}, maxChars: 200).$2, isTrue);
  });

  test('Anthropic streaming', () async {
    final (server, seen) = await _server([
      '{"type":"message_start","message":{}}',
      '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"发现 "}}',
      '{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"2 处"}}',
      '{"type":"message_delta","delta":{"stop_reason":"end_turn"}}',
      '{"type":"message_stop"}',
    ]);
    final s = AiSettings(apiKey: 'k1', baseUrl: 'http://127.0.0.1:${server.port}');
    final chunks = await streamAiCheck(s, system: 'sys', user: 'u').toList();
    await server.close();
    expect(chunks.map((c) => c.text).join(), '发现 2 处');
    expect(chunks.last.stopReason, 'end_turn');
    expect(seen.single['path'], '/v1/messages');
    expect(seen.single['key'], 'k1');
    final body = seen.single['body'] as Map;
    expect(body['model'], 'claude-opus-5-5');
    expect(body['system'], 'sys');
    // Only the official endpoint gets the fallback option.
    expect(body.containsKey('fallbacks'), isFalse);
  });

  test('OpenAI-compatible streaming', () async {
    final (server, seen) = await _server([
      '{"choices":[{"delta":{"content":"OK"}}]}',
      '{"choices":[{"delta":{},"finish_reason":"length"}]}',
      '[DONE]',
    ]);
    final s = AiSettings(provider: AiProvider.openai, apiKey: 'k2', baseUrl: 'http://127.0.0.1:${server.port}/v1', model: 'm');
    final chunks = await streamAiCheck(s, system: 'sys', user: 'u').toList();
    await server.close();
    expect(chunks.map((c) => c.text).join(), 'OK');
    expect(chunks.last.stopReason, 'length');
    expect(seen.single['path'], '/v1/chat/completions');
    expect(seen.single['auth'], 'Bearer k2');
  });

  test('errors and refusals', () async {
    final (bad, _) = await _server(['{"type":"error","error":{"type":"x","message":"nope"}}'], status: 401);
    final s = AiSettings(apiKey: 'k', baseUrl: 'http://127.0.0.1:${bad.port}');
    await expectLater(streamAiCheck(s, system: '', user: '').toList(), throwsA(isA<AiException>().having((e) => e.code, 'code', 'http')));
    await bad.close();
    final (refuse, _) = await _server(['{"type":"message_delta","delta":{"stop_reason":"refusal"}}']);
    final r = AiSettings(apiKey: 'k', baseUrl: 'http://127.0.0.1:${refuse.port}');
    await expectLater(streamAiCheck(r, system: '', user: '').toList(), throwsA(isA<AiException>().having((e) => e.code, 'code', 'refusal')));
    await refuse.close();
    await expectLater(streamAiCheck(AiSettings(), system: '', user: '').toList(), throwsA(isA<AiException>()));
  });
}
