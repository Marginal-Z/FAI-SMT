// A local stand-in for cloud AI APIs (OpenAI-compatible and Anthropic):
// answers from a script, records what it was sent. Not used by the app.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

class FakeReply {
  const FakeReply(this.status, this.body, {this.delay = Duration.zero});

  final int status;
  final Object body;
  final Duration delay;

  /// An OpenAI-style answer carrying [content].
  factory FakeReply.openai(Object content, {String finish = 'stop', int input = 100, int output = 50}) => FakeReply(200, {
    'choices': [
      {
        'message': {'role': 'assistant', 'content': content is String ? content : jsonEncode(content)},
        'finish_reason': finish,
      },
    ],
    'usage': {'prompt_tokens': input, 'completion_tokens': output},
  });

  /// An Anthropic-style answer through the answer tool.
  factory FakeReply.anthropic(Map<String, dynamic> input, {String stop = 'tool_use', int inTok = 120, int outTok = 60}) => FakeReply(200, {
    'content': [
      {'type': 'tool_use', 'name': 'answer', 'input': input},
    ],
    'stop_reason': stop,
    'usage': {'input_tokens': inTok, 'output_tokens': outTok},
  });
}

class FakeLlmServer {
  FakeLlmServer._(this._server);

  static Future<FakeLlmServer> start() async {
    final s = FakeLlmServer._(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    s._server.listen(s._handle);
    return s;
  }

  final HttpServer _server;
  final replies = <FakeReply>[];

  /// Requests received: path, headers, decoded body.
  final requests = <(String, Map<String, String>, Map<String, dynamic>)>[];

  /// Answers for every request when the script is empty.
  FakeReply Function(Map<String, dynamic> body)? fallback;

  String get url => 'http://127.0.0.1:${_server.port}';

  Future<void> _handle(HttpRequest req) async {
    final text = await utf8.decodeStream(req);
    final body = text.isEmpty ? <String, dynamic>{} : jsonDecode(text) as Map<String, dynamic>;
    final headers = <String, String>{};
    req.headers.forEach((k, v) => headers[k] = v.join(','));
    requests.add((req.uri.path, headers, body));
    final r = replies.isNotEmpty ? replies.removeAt(0) : (fallback?.call(body) ?? const FakeReply(500, {'error': 'no reply scripted'}));
    if (r.delay > Duration.zero) await Future<void>.delayed(r.delay);
    req.response.statusCode = r.status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(r.body is String ? r.body : jsonEncode(r.body));
    await req.response.close();
  }

  Future<void> close() => _server.close(force: true);
}
