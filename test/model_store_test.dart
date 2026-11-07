// Model downloads against a local server: mirror fallback, resume, hash
// check, a server that ignores ranges, cancellation, bundled models.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:smt_fai/core/local_ai/model_store.dart';

void main() {
  final payload = Uint8List.fromList([for (var i = 0; i < 300000; i++) (i * 7 + 3) % 251]);
  final hash = sha256.convert(payload).toString();
  late HttpServer server;
  late Directory tmp;
  var ignoreRange = false;
  var requests = <String>[];
  // Bytes after which /slow stops answering (for cancellation).
  Completer<void>? hold;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('model_store_test');
    requests = [];
    ignoreRange = false;
    hold = null;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      requests.add('${req.uri.path} ${req.headers.value(HttpHeaders.rangeHeader) ?? ''}');
      if (req.uri.path == '/missing') {
        req.response.statusCode = 404;
        await req.response.close();
        return;
      }
      final data = req.uri.path == '/corrupt' ? (Uint8List.fromList(payload)..[1000] ^= 1) : payload;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      var start = 0;
      if (range != null && !ignoreRange) {
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        req.response.statusCode = 206;
      }
      req.response.contentLength = data.length - start;
      if (req.uri.path == '/slow') {
        req.response.bufferOutput = false;
        req.response.add(data.sublist(start, start + 1000));
        await req.response.flush();
        await hold!.future;
      }
      req.response.add(data.sublist(req.uri.path == '/slow' ? start + 1000 : start));
      await req.response.close();
    });
  });

  tearDown(() async {
    if (hold != null && !hold!.isCompleted) hold!.complete();
    await server.close(force: true);
    await tmp.delete(recursive: true);
  });

  LocalModelSpec spec(List<String> paths, {String? sha}) => LocalModelSpec(
    id: 't',
    role: LocalModelRole.embedding,
    name: 't',
    license: '',
    file: 't.gguf',
    bytes: payload.length,
    sha256: sha ?? hash,
    urls: {
      for (var i = 0; i < paths.length; i++) ['huggingface', 'hf-mirror', 'modelscope'][i]: 'http://127.0.0.1:${server.port}${paths[i]}',
    },
  );

  test('falls back to the next source and verifies the hash', () async {
    final store = ModelStore(p.join(tmp.path, 'm'));
    final states = <ModelState>[];
    final path = await store.download(spec(['/missing', '/ok']), onStatus: (s) => states.add(s.state));
    expect(await File(path).readAsBytes(), payload);
    expect(states, containsAllInOrder([ModelState.downloading, ModelState.verifying, ModelState.ready]));
    expect((await store.status(spec(['/ok']))).state, ModelState.ready);
    expect(requests.first, startsWith('/missing'));
  });

  test('resumes a partial download with a range request', () async {
    final store = ModelStore(p.join(tmp.path, 'm'));
    final m = spec(['/ok']);
    await Directory(store.dir).create(recursive: true);
    await File('${store.pathOf(m)}.part').writeAsBytes(payload.sublist(0, 120000));
    expect((await store.status(m)).progress, closeTo(0.4, 0.01));
    await store.download(m);
    expect(requests.single, '/ok bytes=120000-');
    expect(await File(store.pathOf(m)).readAsBytes(), payload);
  });

  test('a server that ignores the range sends the whole file again', () async {
    ignoreRange = true;
    final store = ModelStore(p.join(tmp.path, 'm'));
    final m = spec(['/ok']);
    await Directory(store.dir).create(recursive: true);
    await File('${store.pathOf(m)}.part').writeAsBytes(payload.sublist(0, 5000));
    await store.download(m);
    expect(await File(store.pathOf(m)).readAsBytes(), payload);
  });

  test('a file with the wrong hash is deleted and never used', () async {
    final store = ModelStore(p.join(tmp.path, 'm'));
    final m = spec(['/corrupt']);
    await expectLater(store.download(m), throwsA(isA<ModelDownloadException>().having((e) => e.code, 'code', 'hash')));
    expect(await File(store.pathOf(m)).exists(), isFalse);
    expect(await File('${store.pathOf(m)}.part').exists(), isFalse);
    expect((await store.status(m)).state, ModelState.missing);
  });

  test('cancelling keeps the partial file for later', () async {
    hold = Completer<void>();
    final store = ModelStore(p.join(tmp.path, 'm'));
    final m = spec(['/slow']);
    final cancel = DownloadCancel();
    final f = store.download(m, cancel: cancel, onStatus: (s) {
      if (s.state == ModelState.downloading && !cancel.cancelled) cancel.cancel();
    });
    await expectLater(f, throwsA(isA<ModelDownloadException>().having((e) => e.code, 'code', 'cancelled')));
    expect(await File('${store.pathOf(m)}.part').length(), greaterThan(0));
    expect((await store.status(m)).state, ModelState.missing);
  });

  test('a model shipped next to the program is used as is', () async {
    final bundled = Directory(p.join(tmp.path, 'bundled'))..createSync();
    final m = spec(['/ok']);
    File(p.join(bundled.path, m.file)).writeAsBytesSync(payload);
    final store = ModelStore(p.join(tmp.path, 'm'), bundledDir: bundled.path);
    final s = await store.status(m);
    expect(s.state, ModelState.ready);
    expect(s.bundled, isTrue);
    expect(requests, isEmpty);
  });

  test('Chinese users try the mainland mirror first', () {
    final m = modelFor(LocalModelRole.language);
    expect(m.orderedUrls('zh').first, contains('modelscope.cn'));
    expect(m.orderedUrls('en').first, contains('huggingface.co'));
    expect(localModels.every((x) => x.urls.length == 3 && x.sha256.length == 64), isTrue);
  });
}
