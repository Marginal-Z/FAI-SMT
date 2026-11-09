// CLOUD_FULL: the cloud reads the columns and pairs the lines; the program
// checks coverage, citations and fields. The cloud is a local fake that
// pairs lines by the true answers and calls every pair "pass", plus faults.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/cloud/full.dart';
import 'package:smt_fai/core/cloud/provider.dart';
import 'package:smt_fai/core/table_reader.dart';

import 'support/fake_llm_server.dart';
import 'support/mutate.dart';

/// Columns as the program reads them (a perfect reader), for the fake.
Map<String, dynamic> _columns(String user, List<Grid> grids) {
  final letters = RegExp(r'Column ([A-Z]+):').allMatches(user).map((m) => m.group(1)!).toList();
  // Which grid is being asked about: the one whose first values appear.
  final g = grids.firstWhere((g) => g.rows.isNotEmpty && g.rows.first.where((c) => c.isNotEmpty).every((c) => user.contains(cleanCell(c).length > 40 ? cleanCell(c).substring(0, 40) : cleanCell(c))));
  final d = readBom([g]);
  return {
    'columns': [
      for (final l in letters)
        {'column': l, 'role': (d.columns.where((c) => c.letter == l).firstOrNull?.role ?? BomRole.other).name},
    ],
  };
}

/// Pairs by the truth: same part number, or renumbered with an X.
Map<String, dynamic> _lines(Map<String, dynamic> req, {bool invent = false}) {
  final bom2 = (req['bom2'] as List).cast<Map>();
  return {
    'lines': [
      for (final l in (req['bom1'] as List).cast<Map>())
        {
          'id': l['id'],
          'counterparts': [for (final r in bom2) if (r['partNo'] == l['partNo'] || r['partNo'] == 'X${l['partNo']}') r['id'], if (invent) 'R9999'],
          'verdict': 'pass',
          'reason': '对应',
        },
    ],
  };
}

void main() {
  late FakeLlmServer server;
  setUp(() async => server = await FakeLlmServer.start());
  tearDown(() => server.close());

  CloudProvider provider() => HttpCloudProvider(ProviderConfig(kind: ProviderKind.openai, baseUrl: server.url, minIntervalMs: 0, maxRetries: 0), 'k');

  void oracle(List<Grid> grids, {int failMatchCall = 0, bool invent = false, bool truncate = false}) {
    var matchCalls = 0;
    server.fallback = (body) {
      final msgs = body['messages'] as List;
      final user = (msgs.last as Map)['content'] as String;
      if (user.startsWith('The first values')) return FakeReply.openai(_columns(user, grids));
      matchCalls++;
      if (failMatchCall > 0 && matchCalls == failMatchCall) return const FakeReply(500, {'error': 'down'});
      if (truncate && matchCalls == 1) return FakeReply.openai('{"lines": [', finish: 'length');
      return FakeReply.openai(_lines(jsonDecode(user) as Map<String, dynamic>, invent: invent));
    };
  }

  test('pairs from the cloud, fields from the program: no false PASS', () async {
    var falsePass = 0, total = 0, agree = 0;
    for (var seed = 0; seed < 60; seed++) {
      final m = mutateBom(seed);
      oracle([m.left.grid, m.right]);
      final (r, run) = await cloudFullCheck([m.left.grid], [m.right], null, provider());
      expect(run.complete, isTrue, reason: 'seed $seed ${run.errors}');
      expect(r.complete, isTrue, reason: 'seed $seed');
      final local = compareBoms(readBom([m.left.grid], id: 'S'), readBom([m.right], id: 'A'), null);
      final byLeft = {for (final row in r.rows) for (final p in row.singleParts) p.partNo: row};
      final localBy = {for (final row in local.rows) for (final p in row.singleParts) p.partNo: row};
      for (final e in m.changes.entries) {
        total++;
        final got = byLeft[e.key]?.status;
        if (expectedFor[e.value] != CheckStatus.pass && got == CheckStatus.pass) falsePass++;
        if (got == localBy[e.key]?.status) agree++;
      }
    }
    // ignore: avoid_print
    print('cloud-full: false PASS $falsePass of $total lines; same result as the local engine on $agree');
    expect(falsePass, 0);
  });

  test('a failed batch leaves the check incomplete, never finished', () async {
    final m = mutateBom(7);
    oracle([m.left.grid, m.right], failMatchCall: 1);
    final (r, run) = await cloudFullCheck([m.left.grid], [m.right], null, provider(), batchSize: 5);
    expect(run.complete, isFalse);
    expect(r.complete, isFalse);
    expect(r.rows.where((x) => x.reasons.contains('cloud_missing')), isNotEmpty);
    expect(r.rows.where((x) => x.reasons.contains('cloud_missing')).every((x) => x.status != CheckStatus.pass), isTrue);
  });

  test('a cut-off batch is replaced by complete smaller answers', () async {
    final m = mutateBom(8);
    oracle([m.left.grid, m.right], truncate: true);
    final (r, run) = await cloudFullCheck([m.left.grid], [m.right], null, provider(), batchSize: 100);
    expect(run.errors, isEmpty);
    expect(run.complete, isTrue);
    expect(r.complete, isTrue);
  });

  test('invented counterparts are dropped', () async {
    final m = mutateBom(9);
    oracle([m.left.grid, m.right], invent: true);
    final (r, run) = await cloudFullCheck([m.left.grid], [m.right], null, provider());
    expect(run.dropped, greaterThan(0));
    // Those lines went unanswered: incomplete, not finished.
    expect(r.complete, isFalse);
  });
}
