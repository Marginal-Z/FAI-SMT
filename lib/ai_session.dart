/// State of the AI check page. Its files, request and answer are its own:
/// the local check results are never read from or written to here.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app_state.dart' show UserMessage;
import 'core/ai_check.dart';
import 'core/settings.dart';
import 'core/table_reader.dart';

class AiFile {
  AiFile(this.name, this.size, this.grids);

  final String name;
  final int size;
  final List<Grid> grids;
}

class AiSession extends ChangeNotifier {
  AiSession(this._settings, this._persist);

  final AiSettings Function() _settings;
  final Future<void> Function() _persist;

  final List<AiFile> files = [];
  String output = '';
  bool running = false;

  /// Localisation key and detail of the last failure.
  String? errorKey;
  String errorDetail = '';

  /// The tables were longer than what is sent, so the model saw only a part.
  bool inputTruncated = false;

  /// The answer was cut at the output limit.
  bool outputTruncated = false;
  DateTime? finishedAt;
  StreamSubscription<AiChunk>? _sub;

  AiSettings get settings => _settings();

  static const maxFiles = 6;

  void addFile(String name, Uint8List bytes) {
    if (files.length >= maxFiles) throw UserMessage('ai_too_many', {'n': maxFiles});
    try {
      files.add(AiFile(name, bytes.length, readTableBytes(bytes, name)));
    } on TableReadException catch (e) {
      throw UserMessage('err_${e.code}', {'detail': e.detail});
    }
    notifyListeners();
  }

  void removeFile(AiFile f) {
    files.remove(f);
    notifyListeners();
  }

  void saveSettings(AiSettings s) {
    final current = _settings();
    current
      ..provider = s.provider
      ..baseUrl = s.baseUrl
      ..apiKey = s.apiKey
      ..model = s.model
      ..prompt = s.prompt;
    _persist();
    notifyListeners();
  }

  /// Sends the files with [system] instructions and the [request] text.
  void run({required String system, required String request}) {
    if (running) return;
    if (files.isEmpty) throw UserMessage('ai_need_files');
    if (!settings.configured) throw UserMessage('ai_err_not_configured');
    final (tables, truncated) = tablesAsText({for (final f in files) f.name: f.grids});
    inputTruncated = truncated;
    outputTruncated = false;
    output = '';
    errorKey = null;
    errorDetail = '';
    running = true;
    finishedAt = null;
    notifyListeners();
    _sub = streamAiCheck(settings, system: system, user: '$request\n\n$tables').listen(
      (chunk) {
        output += chunk.text;
        if (chunk.stopReason == 'max_tokens' || chunk.stopReason == 'length') outputTruncated = true;
        notifyListeners();
      },
      onError: (Object e) {
        errorKey = e is AiException ? 'ai_err_${e.code}' : 'ai_err_network';
        errorDetail = e is AiException ? e.detail : '$e';
        _done();
      },
      onDone: _done,
      cancelOnError: true,
    );
  }

  void _done() {
    running = false;
    finishedAt = DateTime.now();
    _sub = null;
    notifyListeners();
  }

  void stop() {
    _sub?.cancel();
    if (running) _done();
  }

  void clearOutput() {
    output = '';
    errorKey = null;
    inputTruncated = outputTruncated = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
