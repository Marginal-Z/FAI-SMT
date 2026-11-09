/// The local models at work: text vectors and structured answers from the
/// bundled llama.cpp runtime. Failures are errors; nothing here falls back
/// to rules and calls that an AI result.
library;

import 'dart:async';

import 'package:llamadart/llamadart.dart';

import 'model_store.dart';

class LocalAiException implements Exception {
  LocalAiException(this.code, [this.detail = '']);

  /// `model_missing`, `load_failed`, `inference_failed`, `timeout`, `bad_output`.
  final String code;
  final String detail;

  @override
  String toString() => 'LocalAiException($code) $detail';
}

/// What the checking code needs from a local model; a stand-in implements it
/// in tests.
abstract class LocalModels {
  /// Name and version of the language model, for results.
  String get languageModel;

  /// Unit-length vectors, one per text.
  Future<List<List<double>>> embed(List<String> texts);

  /// A JSON object matching [schema], decoded.
  Future<Map<String, dynamic>> structured({required String system, required String user, required Map<String, dynamic> schema, int maxTokens = 600});

  Future<void> dispose();
}

/// Optional preparation hook so the app can distinguish loading from analysis.
abstract interface class LocalAnalysisPreparation {
  Future<void> prepareAnalysis();
}

/// llama.cpp through llamadart, one engine per model, on a worker isolate.
class LlamaLocalModels implements LocalModels, LocalAnalysisPreparation {
  LlamaLocalModels({required this.embeddingPath, required this.languagePath, this.timeout = const Duration(minutes: 3), this.thinking = false, this.languageName, this.embeddingPrefix = ''});

  /// Opens the [embedding] model (the default when null) and the language
  /// model [store] holds; throws when the embedding model is missing.
  static Future<LlamaLocalModels> open(ModelStore store, {LocalModelSpec? embedding}) async {
    final spec = embedding ?? embeddingModels.first;
    final e = await store.status(spec);
    final l = await store.status(modelFor(LocalModelRole.language));
    if (e.state != ModelState.ready) throw LocalAiException('model_missing');
    // A bundled file was previously accepted by size alone. Check the
    // exact bytes once on opening, before any native model load.
    if (await ModelStore.hashFile(e.path!) != spec.sha256) throw LocalAiException('model_hash');
    // The language model is optional; asking it without the file fails.
    return LlamaLocalModels(embeddingPath: e.path!, languagePath: l.state == ModelState.ready ? l.path! : '', embeddingPrefix: spec.prefix);
  }

  /// Analysis needs the language model, independently of optional embeddings.
  static Future<LlamaLocalModels> openAnalysis(ModelStore store) async {
    final spec = modelFor(LocalModelRole.language);
    final status = await store.status(spec);
    if (status.state != ModelState.ready || status.path == null) throw LocalAiException('model_missing');
    if (await ModelStore.hashFile(status.path!) != spec.sha256) throw LocalAiException('model_hash');
    return LlamaLocalModels(embeddingPath: '', languagePath: status.path!, languageName: spec.name);
  }

  final String embeddingPath;
  final String languagePath;

  /// Put before every text embedded, for models trained with one
  /// ("query: " for E5).
  final String embeddingPrefix;
  final Duration timeout;

  /// Let the language model reason before answering (slower, often better).
  final bool thinking;
  final String? languageName;

  LlamaEngine? _embed;
  LlamaEngine? _lang;
  Future<LlamaEngine>? _embedLoading;
  Future<LlamaEngine>? _langLoading;

  @override
  String get languageModel => languageName ?? modelFor(LocalModelRole.language).name;

  Future<LlamaEngine> _load(String path, ModelParams params) async {
    if (path.isEmpty) throw LocalAiException('model_missing');
    try {
      return await LlamaEngine.load(LlamaModel(ModelSource.parse(path)), params: params);
    } catch (e) {
      throw LocalAiException('load_failed', '$e');
    }
  }

  Future<LlamaEngine> _embedding() async {
    try {
      return _embed ??= await (_embedLoading ??= _load(embeddingPath, const ModelParams(contextSize: 512)));
    } catch (_) {
      _embedLoading = null;
      rethrow;
    }
  }

  Future<LlamaEngine> _language() async => _lang ??= await (_langLoading ??= _load(languagePath, const ModelParams(contextSize: 8192)));
  @override
  Future<void> prepareAnalysis() async { await _language(); }

  @override
  Future<List<List<double>>> embed(List<String> texts) async {
    if (texts.isEmpty) return const [];
    final engine = await _embedding();
    try {
      // Long descriptions are cut to what one pass takes.
      return await engine.embedBatch([for (final t in texts) '$embeddingPrefix${t.length > 300 ? t.substring(0, 300) : t}']).timeout(timeout);
    } on TimeoutException {
      engine.cancelGeneration();
      throw LocalAiException('timeout');
    } on LocalAiException {
      rethrow;
    } catch (e) {
      throw LocalAiException('inference_failed', '$e');
    }
  }

  @override
  Future<Map<String, dynamic>> structured({required String system, required String user, required Map<String, dynamic> schema, int maxTokens = 600}) async {
    final engine = await _language();
    final output = LlamaStructuredOutput<Map<String, dynamic>>.jsonSchema(schema: schema, decoder: (j) => j);
    try {
      final messages = [
              LlamaChatMessage.fromText(role: LlamaChatRole.system, text: system),
              LlamaChatMessage.fromText(role: LlamaChatRole.user, text: user),
      ];
      final limit = thinking ? maxTokens + 1500 : maxTokens;
      return await (() async {
        final template = await engine.chatTemplate(messages, responseFormat: output.responseFormat, enableThinking: thinking);
        final tokens = template.tokenCount ?? (await engine.tokenize(template.prompt, addSpecial: false)).length;
        if (tokens + limit + 32 > 8192) throw LocalAiException('context_limit');
        final text = StringBuffer();
        String? finish;
        await for (final chunk in engine.create(messages, responseFormat: output.responseFormat,
          params: GenerationParams(maxTokens: limit, temp: 0), enableThinking: thinking)) {
          for (final choice in chunk.choices) {
            if (choice.delta.content != null) text.write(choice.delta.content);
            finish = choice.finishReason ?? finish;
          }
        }
        if (finish == 'length') throw LocalAiException('truncated');
        if (finish != 'stop') throw LocalAiException('bad_output');
        return output.parse(text.toString());
      })().timeout(timeout);
    } on TimeoutException {
      engine.cancelGeneration();
      throw LocalAiException('timeout');
    } on LocalAiException {
      rethrow;
    } catch (e) {
      throw LocalAiException('bad_output', '$e');
    }
  }

  void cancel() { _embed?.cancelGeneration(); _lang?.cancelGeneration(); }

  @override
  Future<void> dispose() async {
    final e = _embed, l = _lang;
    _embed = _lang = null;
    _embedLoading = _langLoading = null;
    await e?.dispose();
    await l?.dispose();
  }
}
