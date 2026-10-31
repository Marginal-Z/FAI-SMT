/// AI check: sends the user's tables to a language model and streams back
/// its written analysis. It is independent of the local check — nothing it
/// returns changes a check result.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'settings.dart';
import 'table_reader.dart';

class AiException implements Exception {
  AiException(this.code, [this.detail = '']);

  /// `not_configured`, `http`, `network`, `api`, `refusal`.
  final String code;
  final String detail;

  @override
  String toString() => 'AiException($code) $detail';
}

/// A piece of streamed output; [stopReason] is set on the last one.
class AiChunk {
  const AiChunk(this.text, {this.stopReason});

  final String text;
  final String? stopReason;
}

/// Tables as plain text rows (`R<n>: a | b | c`), file by file and sheet by
/// sheet. Returns the text and whether it had to stop at [maxChars].
(String, bool) tablesAsText(Map<String, List<Grid>> files, {int maxChars = 600000}) {
  final out = StringBuffer();
  for (final f in files.entries) {
    out.writeln('### ${f.key}');
    for (final g in f.value) {
      out.writeln('#### ${g.name}');
      for (var r = 0; r < g.rows.length; r++) {
        final cells = [...g.rows[r].map((c) => c.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim())];
        while (cells.isNotEmpty && cells.last.isEmpty) {
          cells.removeLast();
        }
        if (cells.isEmpty) continue;
        final line = 'R${r + 1}: ${cells.join(' | ')}';
        if (out.length + line.length > maxChars) return (out.toString(), true);
        out.writeln(line);
      }
    }
    out.writeln();
  }
  return (out.toString(), false);
}

String _join(String base, String path) {
  final b = base.trim().replaceAll(RegExp(r'/+$'), '');
  return b.endsWith(path) ? b : '$b$path';
}

bool _official(String url) => Uri.tryParse(url)?.host == 'api.anthropic.com';

/// Streams the model's answer to [user] (the tables and the request) with
/// [system] instructions. Cancelling the subscription closes the connection.
Stream<AiChunk> streamAiCheck(AiSettings s, {required String system, required String user}) async* {
  if (!s.configured) throw AiException('not_configured');
  final anthropic = s.provider == AiProvider.anthropic;
  final base = s.effectiveUrl;
  final uri = Uri.parse(anthropic
      ? (base.replaceAll(RegExp(r'/+$'), '').endsWith('/v1') ? _join(base, '/messages') : _join(base, '/v1/messages'))
      : _join(base, '/chat/completions'));
  final body = anthropic
      ? {
          'model': s.effectiveModel,
          'max_tokens': 64000,
          'stream': true,
          'system': system,
          'thinking': {'type': 'adaptive'},
          'output_config': {'effort': 'high'},
          // Lets the API retry a declined request on another model.
          if (_official(base)) 'fallbacks': 'default',
          'messages': [
            {'role': 'user', 'content': user},
          ],
        }
      : {
          'model': s.effectiveModel,
          'stream': true,
          'messages': [
            {'role': 'system', 'content': system},
            {'role': 'user', 'content': user},
          ],
        };

  final client = HttpClient()..connectionTimeout = const Duration(seconds: 30);
  try {
    final HttpClientResponse res;
    try {
      final req = await client.postUrl(uri);
      req.headers.contentType = ContentType.json;
      if (anthropic) {
        req.headers.set('x-api-key', s.apiKey.trim());
        req.headers.set('anthropic-version', '2026-10-21');
        if (_official(base)) req.headers.set('anthropic-beta', 'server-side-fallback-2026-07-01');
      } else {
        req.headers.set('authorization', 'Bearer ${s.apiKey.trim()}');
      }
      req.add(utf8.encode(jsonEncode(body)));
      res = await req.close();
    } on SocketException catch (e) {
      throw AiException('network', e.message);
    } on HandshakeException catch (e) {
      throw AiException('network', e.message);
    } on HttpException catch (e) {
      throw AiException('network', e.message);
    }
    if (res.statusCode != 200) {
      final text = await res.transform(utf8.decoder).join();
      throw AiException('http', '${res.statusCode} ${_errorMessage(text)}');
    }
    String? stop;
    await for (final line in res.transform(utf8.decoder).transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final data = line.substring(5).trim();
      if (data.isEmpty) continue;
      if (data == '[DONE]') break;
      final Object? j;
      try {
        j = jsonDecode(data);
      } on FormatException {
        continue;
      }
      if (j is! Map) continue;
      if (anthropic) {
        switch (j['type']) {
          case 'content_block_delta':
            final d = j['delta'];
            if (d is Map && d['type'] == 'text_delta') yield AiChunk('${d['text'] ?? ''}');
          case 'message_delta':
            final d = j['delta'];
            if (d is Map && d['stop_reason'] != null) stop = '${d['stop_reason']}';
          case 'error':
            throw AiException('api', _errorMessage(jsonEncode(j)));
        }
      } else {
        final choices = j['choices'];
        if (choices is List && choices.isNotEmpty && choices.first is Map) {
          final c = choices.first as Map;
          final d = c['delta'];
          if (d is Map && d['content'] is String) yield AiChunk(d['content'] as String);
          if (c['finish_reason'] != null) stop = '${c['finish_reason']}';
        } else if (j['error'] != null) {
          throw AiException('api', _errorMessage(jsonEncode(j)));
        }
      }
    }
    if (stop == 'refusal') throw AiException('refusal');
    yield AiChunk('', stopReason: stop ?? 'end_turn');
  } finally {
    client.close(force: true);
  }
}

String _errorMessage(String text) {
  try {
    final j = jsonDecode(text);
    if (j is Map) {
      final e = j['error'];
      if (e is Map && e['message'] != null) return '${e['message']}';
      if (e is String) return e;
      if (j['message'] != null) return '${j['message']}';
    }
  } on FormatException {
    // Not JSON: show it as it is.
  }
  return text.length > 300 ? '${text.substring(0, 300)}…' : text;
}
