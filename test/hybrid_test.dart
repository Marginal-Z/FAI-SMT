// HYBRID: the cloud is asked only about lines the local engine could not
// settle, and its answers pass the program's checks before they change
// anything. The cloud here is a local fake: an honest one that knows the
// true answers, and a dishonest one that agrees with everything and cites
// lines that do not exist.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/cloud/hybrid.dart';
import 'package:smt_fai/core/cloud/provider.dart';

import 'support/fake_llm_server.dart';
import 'support/mutate.dart';

List<Map<String, dynamic>> _items(Map<String, dynamic> body) {
  final msgs = body['messages'] as List;
  return (jsonDecode((msgs.last as Map)['content'] as String) as List).cast<Map<String, dynamic>>();
}

/// Same part when the second number is the first, or the first renumbered.
bool _truthSame(String a, String b) => a == b || b == 'X$a';

FakeReply _honest(Map<String, dynamic> body) => FakeReply.openai({
  'answers': [
    for (final it in _items(body))
      if (it['type'] == 'pair')
        {'id': it['id'], 'same': _truthSame('${it['bom1']['partNo']}', '${it['bom2']['partNo']}') ? 'yes' : 'no', 'reason': '同一物料'}
      else
        () {
          final c = (it['candidates'] as List? ?? const []).cast<Map>().where((c) => _truthSame('${it['bom1']['partNo']}', '${c['partNo']}')).firstOrNull;
          return {'id': it['id'], 'same': c == null ? 'no' : 'yes', if (c != null) 'counterpart': c['id'], 'reason': '对应'};
        }(),
  ],
});

FakeReply _liar(Map<String, dynamic> body) => FakeReply.openai({
  'answers': [
    for (final it in _items(body)) {'id': it['id'], 'same': 'yes', if (it['candidates'] != null) 'counterpart': (it['candidates'] as List).first['id'], 'reason': '一样'},
    {'id': 'i999', 'same': 'yes', 'reason': '不存在的行'},
  ],
});

void main() {
  late FakeLlmServer server;
  setUp(() async => server = await FakeLlmServer.start());
  tearDown(() => server.close());

  CloudProvider provider() => HttpCloudProvider(ProviderConfig(kind: ProviderKind.openai, baseUrl: server.url, minIntervalMs: 0, maxRetries: 0), 'k');

  Future<(int, int, int, int, int)> runAll(FakeReply Function(Map<String, dynamic>) oracle, {int failEvery = 0}) async {
    var calls = 0;
    server.fallback = (b) {
      calls++;
      return failEvery > 0 && calls % failEvery == 0 ? const FakeReply(500, {'error': 'down'}) : oracle(b);
    };
    var localPass = 0, hybridPass = 0, falsePass = 0, dropped = 0, missing = 0;
    for (var seed = 0; seed < 120; seed++) {
      final m = mutateBom(seed);
      final local = compareBoms(readBom([m.left.grid], id: 'S'), readBom([m.right], id: 'A'), null);
      final (hybrid, run) = await hybridCheck(local, provider());
      expect(hybrid.complete, isTrue);
      expect(hybrid.rows.length, lessThanOrEqualTo(local.rows.length));
      dropped += run.dropped;
      final byLeft = {for (final r in hybrid.rows) for (final p in r.singleParts) p.partNo: r};
      final localByLeft = {for (final r in local.rows) for (final p in r.singleParts) p.partNo: r};
      for (final e in m.changes.entries) {
        final want = expectedFor[e.value]!;
        final got = byLeft[e.key]?.status;
        if (localByLeft[e.key]?.status == CheckStatus.pass) localPass++;
        if (got == CheckStatus.pass) hybridPass++;
        if (want != CheckStatus.pass && got == CheckStatus.pass) falsePass++;
        if (byLeft[e.key]?.reasons.contains('cloud_missing') ?? false) missing++;
      }
    }
    return (localPass, hybridPass, falsePass, dropped, missing);
  }

  test('an honest cloud settles lines the local engine could not', () async {
    final (localPass, hybridPass, falsePass, dropped, missing) = await runAll(_honest);
    // ignore: avoid_print
    print('honest cloud: PASS $localPass -> $hybridPass, false PASS $falsePass, dropped $dropped');
    expect(hybridPass, greaterThan(localPass));
    expect(falsePass, 0);
    expect(dropped, 0);
    expect(missing, 0);
  });

  test('a cloud that agrees with everything cannot pass a real change', () async {
    final (_, _, falsePass, dropped, _) = await runAll(_liar);
    // ignore: avoid_print
    print('dishonest cloud: false PASS $falsePass, dropped answers $dropped');
    expect(falsePass, 0);
    expect(dropped, greaterThan(0));
  });

  test('a failed batch keeps the local result and is marked', () async {
    final (_, _, falsePass, _, missing) = await runAll(_honest, failEvery: 3);
    expect(falsePass, 0);
    expect(missing, greaterThan(0));
  });

  test('privacy: part numbers masked, designators as counts', () async {
    server.fallback = _honest;
    final m = mutateBom(3);
    final local = compareBoms(readBom([m.left.grid], id: 'S'), readBom([m.right], id: 'A'), null);
    await hybridCheck(local, provider(), privacy: const PrivacyOptions(partNumbers: false, designators: false));
    final sent = jsonEncode(server.requests.map((r) => r.$3).toList());
    for (final pn in m.changes.keys) {
      expect(sent, isNot(contains(pn)));
    }
    expect(sent, isNot(contains('designators')));
  });
}
