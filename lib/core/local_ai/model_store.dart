/// The local models: what they are, where they come from, and keeping them
/// on disk. Downloads resume, fall back across mirrors and are only used
/// after their SHA-256 matches; a full offline installer can ship the files
/// in a `models` folder next to the program.
library;

import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

enum LocalModelRole {
  /// Text vectors for finding candidate matches.
  embedding,

  /// Small instruction model for reading columns and descriptions.
  language,
}

class LocalModelSpec {
  const LocalModelSpec({required this.id, required this.role, required this.file, required this.bytes, required this.sha256, required this.urls, required this.name, required this.license});

  final String id;
  final LocalModelRole role;
  final String file;
  final int bytes;
  final String sha256;

  /// Download sources in no particular order; see [orderedUrls].
  final Map<String, String> urls;
  final String name;
  final String license;

  /// Sources to try: mainland-China mirrors first for Chinese.
  List<String> orderedUrls(String language) {
    final order = language == 'zh' ? ['modelscope', 'hf-mirror', 'huggingface'] : ['huggingface', 'hf-mirror', 'modelscope'];
    return [for (final k in order) ?urls[k]];
  }
}

/// Qwen3 models, Apache-2.0. Hashes measured on the published files; every
/// mirror serves identical bytes.
const localModels = [
  LocalModelSpec(
    id: 'qwen3-embedding-0.6b-q8',
    role: LocalModelRole.embedding,
    name: 'Qwen3-Embedding-0.6B (Q8_0)',
    license: 'Apache-2.0',
    file: 'Qwen3-Embedding-0.6B-Q8_0.gguf',
    bytes: 639150592,
    sha256: '06507c7b42688469c4e7298b0a1e16deff06caf291cf0a5b278c308249c3e439',
    urls: {
      'modelscope': 'https://modelscope.cn/models/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/master/Qwen3-Embedding-0.6B-Q8_0.gguf',
      'huggingface': 'https://huggingface.co/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/main/Qwen3-Embedding-0.6B-Q8_0.gguf',
      'hf-mirror': 'https://hf-mirror.com/Qwen/Qwen3-Embedding-0.6B-GGUF/resolve/main/Qwen3-Embedding-0.6B-Q8_0.gguf',
    },
  ),
  LocalModelSpec(
    id: 'qwen3-1.7b-q4km',
    role: LocalModelRole.language,
    name: 'Qwen3-1.7B (Q4_K_M)',
    license: 'Apache-2.0',
    file: 'Qwen3-1.7B-Q4_K_M.gguf',
    bytes: 1282439264,
    sha256: 'd2387ca2dbfee2ffabce7120d3770dadca0b293052bc2f0e138fdc940d9bc7b5',
    urls: {
      'modelscope': 'https://modelscope.cn/models/ggml-org/Qwen3-1.7B-GGUF/resolve/master/Qwen3-1.7B-Q4_K_M.gguf',
      'huggingface': 'https://huggingface.co/ggml-org/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
      'hf-mirror': 'https://hf-mirror.com/ggml-org/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf',
    },
  ),
];

LocalModelSpec modelFor(LocalModelRole role) => localModels.firstWhere((m) => m.role == role);

enum ModelState { missing, downloading, verifying, ready, failed }

class ModelStatus {
  const ModelStatus(this.state, {this.progress = 0, this.path, this.bundled = false, this.error = '', this.detail = ''});

  final ModelState state;

  /// 0–1 while downloading or verifying.
  final double progress;
  final String? path;

  /// Shipped with the program (read-only).
  final bool bundled;

  /// Localisation key (`model_err_*`) and detail.
  final String error;
  final String detail;
}

class ModelDownloadException implements Exception {
  ModelDownloadException(this.code, [this.detail = '']);

  /// `network`, `http`, `hash`, `cancelled`, `disk`.
  final String code;
  final String detail;

  @override
  String toString() => 'ModelDownloadException($code) $detail';
}

/// Cancels a running download.
class DownloadCancel {
  bool _cancelled = false;
  final _listeners = <void Function()>[];

  bool get cancelled => _cancelled;

  void cancel() {
    _cancelled = true;
    for (final l in _listeners) {
      l();
    }
  }
}

class ModelStore {
  /// [dir]: where downloads go. [bundledDir]: the read-only folder of an
  /// offline installer, checked first.
  ModelStore(this.dir, {this.bundledDir});

  final String dir;
  final String? bundledDir;

  /// Default folders: `<settings>/models`, and `models` next to the program.
  factory ModelStore.forApp(String settingsDir) {
    final exeDir = p.dirname(Platform.resolvedExecutable);
    return ModelStore(p.join(settingsDir, 'models'), bundledDir: p.join(exeDir, 'models'));
  }

  String pathOf(LocalModelSpec m) => p.join(dir, m.file);

  /// Where the model can be loaded from, without hashing (see [verify]).
  Future<ModelStatus> status(LocalModelSpec m) async {
    if (bundledDir != null) {
      final b = File(p.join(bundledDir!, m.file));
      if (await b.exists() && await b.length() == m.bytes) return ModelStatus(ModelState.ready, path: b.path, bundled: true, progress: 1);
    }
    final f = File(pathOf(m));
    if (await f.exists() && await f.length() == m.bytes && await File('${f.path}.ok').exists()) {
      return ModelStatus(ModelState.ready, path: f.path, progress: 1);
    }
    final part = File('${pathOf(m)}.part');
    if (await part.exists()) return ModelStatus(ModelState.missing, progress: (await part.length()) / m.bytes);
    return const ModelStatus(ModelState.missing);
  }

  /// SHA-256 of a file, reported as a 0–1 progress.
  static Future<String> hashFile(String path, {void Function(double)? onProgress, int? size}) async {
    final f = File(path);
    final total = size ?? await f.length();
    var done = 0;
    final out = await sha256.bind(f.openRead().map((chunk) {
      done += chunk.length;
      if (onProgress != null && total > 0) onProgress(done / total);
      return chunk;
    })).first;
    return out.toString();
  }

  /// Downloads [m], resuming a partial file and trying each source in turn;
  /// the file is kept only when its hash matches.
  Future<String> download(LocalModelSpec m, {String language = 'en', void Function(ModelStatus)? onStatus, DownloadCancel? cancel, HttpClient? client}) async {
    await Directory(dir).create(recursive: true);
    final target = File(pathOf(m));
    final part = File('${target.path}.part');
    final http = client ?? (HttpClient()..connectionTimeout = const Duration(seconds: 20));
    final errors = <String>[];
    try {
      for (final url in m.orderedUrls(language)) {
        if (cancel?.cancelled ?? false) throw ModelDownloadException('cancelled');
        try {
          await _fetch(url, part, m.bytes, http, cancel, (p) => onStatus?.call(ModelStatus(ModelState.downloading, progress: p)));
          break;
        } on ModelDownloadException catch (e) {
          if (e.code == 'cancelled' || e.code == 'disk') rethrow;
          errors.add('${Uri.parse(url).host}: ${e.code} ${e.detail}');
        }
      }
      if (!await part.exists() || await part.length() != m.bytes) {
        throw ModelDownloadException('network', errors.join('; '));
      }
      onStatus?.call(const ModelStatus(ModelState.verifying));
      final hash = await hashFile(part.path, size: m.bytes, onProgress: (p) => onStatus?.call(ModelStatus(ModelState.verifying, progress: p)));
      if (hash != m.sha256) {
        // A corrupt or substituted file is never kept.
        await part.delete();
        throw ModelDownloadException('hash', hash);
      }
      if (await target.exists()) await target.delete();
      await part.rename(target.path);
      await File('${target.path}.ok').writeAsString(m.sha256);
      onStatus?.call(ModelStatus(ModelState.ready, path: target.path, progress: 1));
      return target.path;
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  Future<void> _fetch(String url, File part, int total, HttpClient http, DownloadCancel? cancel, void Function(double) progress) async {
    var have = await part.exists() ? await part.length() : 0;
    if (have > total) {
      await part.delete();
      have = 0;
    }
    if (have == total) return;
    final HttpClientResponse res;
    try {
      final req = await http.getUrl(Uri.parse(url));
      if (have > 0) req.headers.set(HttpHeaders.rangeHeader, 'bytes=$have-');
      res = await req.close();
    } on SocketException catch (e) {
      throw ModelDownloadException('network', e.message);
    } on HttpException catch (e) {
      throw ModelDownloadException('network', e.message);
    } on TimeoutException {
      throw ModelDownloadException('network', 'timeout');
    }
    if (res.statusCode == 200 && have > 0) {
      // The server ignored the range: start over.
      have = 0;
    } else if (res.statusCode != 200 && res.statusCode != 206) {
      await res.drain<void>();
      throw ModelDownloadException('http', '${res.statusCode}');
    }
    final sink = part.openWrite(mode: have > 0 ? FileMode.append : FileMode.write);
    var done = have;
    final finished = Completer<void>();
    late StreamSubscription<List<int>> sub;
    void stop() {
      if (!finished.isCompleted) finished.completeError(ModelDownloadException('cancelled'));
      sub.cancel();
    }

    cancel?._listeners.add(stop);
    sub = res.listen(
      (chunk) {
        sink.add(chunk);
        done += chunk.length;
        progress(done / total);
      },
      onError: (Object e) {
        if (!finished.isCompleted) finished.completeError(ModelDownloadException('network', '$e'));
      },
      onDone: () {
        if (!finished.isCompleted) finished.complete();
      },
      cancelOnError: true,
    );
    try {
      await finished.future;
    } finally {
      cancel?._listeners.remove(stop);
      try {
        await sink.flush();
        await sink.close();
      } on FileSystemException catch (e) {
        // A full disk shows up here.
        throw ModelDownloadException('disk', e.message);
      }
    }
  }

  /// Removes a downloaded model (bundled models are left alone).
  Future<void> delete(LocalModelSpec m) async {
    for (final f in [File(pathOf(m)), File('${pathOf(m)}.part'), File('${pathOf(m)}.ok')]) {
      if (await f.exists()) await f.delete();
    }
  }
}
