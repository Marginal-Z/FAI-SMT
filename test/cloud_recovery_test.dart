import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/ai_check.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/cloud/full.dart';
import 'package:smt_fai/core/cloud/hybrid.dart';
import 'package:smt_fai/core/cloud/provider.dart';
import 'package:smt_fai/core/table_reader.dart';

import 'support/fake_llm_server.dart';
import 'support/mutate.dart';

Grid grid(int count) => Grid('s', [
  ['料号', '描述', '用量', '位号'],
  for (var i = 1; i <= count; i++)
    ['P${1000 + i}', 'Chip resistor 10k 0603', '1', 'R$i'],
]);

Map<String, dynamic> columns() => {
  'columns': [
    for (final (column, role) in [
      ('A', 'partNo'),
      ('B', 'description'),
      ('C', 'quantity'),
      ('D', 'refs'),
    ])
      {'column': column, 'role': role},
  ],
};

String user(Map<String, dynamic> body) =>
    ((body['messages'] as List).last as Map)['content'] as String;

void main() {
  late FakeLlmServer server;
  setUp(() async => server = await FakeLlmServer.start());
  tearDown(() => server.close());
  HttpCloudProvider provider({
    int retries = 0,
    void Function(RequestRecord)? onRecord,
  }) => HttpCloudProvider(
    ProviderConfig(
      kind: ProviderKind.deepseek,
      baseUrl: server.url,
      model: 'test',
      maxRetries: retries,
      minIntervalMs: 0,
    ),
    'test-key',
    onRecord: onRecord,
  );

  test(
    'column detection can recover independently from line matching',
    () async {
      const roles = {
        'A': 'partNo',
        'B': 'description',
        'C': 'quantity',
        'D': 'refs',
      };
      server.fallback = (body) {
        final prompt = user(body);
        if (prompt.startsWith('The first values')) {
          final letters = RegExp(r'Column ([A-Z]+):')
              .allMatches(prompt)
              .map((m) => m[1]!)
              .toList();
          if (letters.length > 1) {
            return FakeReply.openai({'columns': []}, finish: 'length');
          }
          return FakeReply.openai({
            'columns': [
              for (final c in letters) {'column': c, 'role': roles[c]},
            ],
          });
        }
        final payload = jsonDecode(prompt) as Map;
        return FakeReply.openai({
          'lines': [
            for (final row in payload['bom1'] as List)
              {
                'id': row['id'],
                'counterparts': [
                  for (final r in payload['bom2'] as List)
                    if (r['partNo'] == row['partNo']) r['id'],
                ],
                'verdict': 'pass',
                'reason': 'same',
              },
          ],
        });
      };
      final (report, run) = await cloudFullCheck(
        [grid(2)],
        [grid(2)],
        null,
        provider(),
      );
      expect(report.complete, isTrue);
      expect(report.count(CheckStatus.pass), 2);
      expect(run.complete, isTrue);
      expect(run.usage.requests, server.requests.length);
      expect(server.requests.length, greaterThan(3));
    },
  );

  test('cancelling recovered analysis stops remaining batches and returns no partial result', () async {
    final input = grid(5);
    final report = compareBoms(
      readBom([input], id: 'S'),
      readBom([input], id: 'A'),
      null,
    );
    final cancel = CloudCancel();
    server.fallback = (body) {
      final rows = jsonDecode(user(body))['rows'] as List;
      return rows.length > 2
          ? FakeReply.openai({
              'summary': 'partial',
              'findings': [],
            }, finish: 'length')
          : FakeReply.openai({'summary': 'complete leaf', 'findings': []});
    };
    final p = provider(
      onRecord: (record) {
        if (record.error.isEmpty) cancel.cancel();
      },
    );
    await expectLater(
      runAiCheck(p, report, cancel: cancel),
      throwsA(isA<CloudException>().having((e) => e.code, 'code', 'cancelled')),
    );
    expect(server.requests, hasLength(2));
  });

  test(
    'DeepSeek connectivity disables thinking and has enough JSON budget',
    () async {
      server.fallback = (body) =>
          (body['thinking'] as Map?)?['type'] == 'disabled' &&
              (body['max_tokens'] as int) >= 4096
          ? FakeReply.openai({'ok': true})
          : FakeReply.openai('', finish: 'length');
      final reply = await testCloud(provider());
      expect(reply.json['ok'], isTrue);
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'official retired aliases migrate; custom gateway names are retained',
    () {
      for (final model in ['', 'deepseek-chat', 'deepseek-reasoner']) {
        expect(
          ProviderConfig(kind: ProviderKind.deepseek, model: model).modelName,
          'deepseek-flash',
        );
      }
      expect(
        ProviderConfig(
          kind: ProviderKind.deepseek,
          model: 'deepseek-v4-pro',
        ).modelName,
        'deepseek-v4-pro',
      );
      expect(
        ProviderConfig(
          kind: ProviderKind.deepseek,
          baseUrl: server.url,
          model: 'deepseek-chat',
        ).modelName,
        'deepseek-chat',
      );
    },
  );

  test(
    'truncation grows token allowance and accounts for failed attempt usage',
    () async {
      final records = <RequestRecord>[];
      server.replies
        ..add(
          FakeReply.openai('{"ok":', finish: 'length', input: 10, output: 4096),
        )
        ..add(FakeReply.openai({'ok': true}, input: 10, output: 4));
      final result = await testCloud(
        provider(retries: 1, onRecord: records.add),
      );
      expect(server.requests.map((r) => r.$3['max_tokens']), [4096, 8192]);
      expect(result.usage.requests, 2);
      expect(result.usage.outputTokens, 4100);
      expect(records.first.usage.outputTokens, 4096);
      expect(records.first.error, startsWith('truncated'));
    },
  );

  test(
    'blank JSON output is retried; ceiling truncation is never accepted',
    () async {
      server.replies
        ..add(FakeReply.openai('   '))
        ..add(FakeReply.openai({'ok': true}));
      expect((await testCloud(provider(retries: 1))).json['ok'], isTrue);
      server.requests.clear();
      server.fallback = (_) => FakeReply.openai({'ok': true}, finish: 'length');
      await expectLater(
        provider(retries: 2).ask(
          system: 'JSON',
          user: 'test',
          schema: const {'type': 'object'},
          maxTokens: 16384,
        ),
        throwsA(
          isA<CloudException>().having((e) => e.code, 'code', 'truncated'),
        ),
      );
      expect(server.requests, hasLength(1));
    },
  );

  test(
    'full check recovers smaller batches with exact line coverage and counts',
    () async {
      final successful = <String>[];
      server.fallback = (body) {
        final prompt = user(body);
        if (prompt.startsWith('The first values')) {
          return FakeReply.openai(columns());
        }
        final payload = jsonDecode(prompt) as Map;
        final left = (payload['bom1'] as List).cast<Map>();
        if (left.length > 2) {
          return FakeReply.openai({'lines': []}, finish: 'length');
        }
        final right = (payload['bom2'] as List).cast<Map>();
        successful.addAll(left.map((r) => '${r['id']}'));
        return FakeReply.openai({
          'lines': [
            for (final row in left)
              {
                'id': row['id'],
                'counterparts': [
                  for (final r in right)
                    if (r['partNo'] == row['partNo']) r['id'],
                ],
                'verdict': 'pass',
                'reason': 'same',
              },
          ],
        });
      };
      final (report, run) = await cloudFullCheck(
        [grid(13)],
        [grid(13)],
        null,
        provider(),
      );
      expect(run.complete, isTrue);
      expect(report.complete, isTrue);
      expect(run.batchesDone, run.batches);
      expect(run.linesSent, 13);
      expect(successful.toSet(), {for (var i = 1; i <= 13; i++) 'L$i'});
      expect(successful, hasLength(13));
      expect(report.count(CheckStatus.pass), 13);
      expect(run.usage.requests, server.requests.length);
    },
  );

  test(
    'a single line still cut off stays incomplete while siblings succeed',
    () async {
      server.fallback = (body) {
        final prompt = user(body);
        if (prompt.startsWith('The first values')) {
          return FakeReply.openai(columns());
        }
        final payload = jsonDecode(prompt) as Map;
        final left = (payload['bom1'] as List).cast<Map>();
        if (left.any((r) => r['id'] == 'L1')) {
          return FakeReply.openai({'lines': []}, finish: 'length');
        }
        final right = (payload['bom2'] as List).cast<Map>();
        return FakeReply.openai({
          'lines': [
            for (final row in left)
              {
                'id': row['id'],
                'counterparts': [
                  for (final r in right)
                    if (r['partNo'] == row['partNo']) r['id'],
                ],
                'verdict': 'pass',
                'reason': 'same',
              },
          ],
        });
      };
      final (report, run) = await cloudFullCheck(
        [grid(3)],
        [grid(3)],
        null,
        provider(),
      );
      expect(run.complete, isFalse);
      expect(run.batchesFailed, 1);
      expect(report.complete, isFalse);
      expect(
        report.rows.firstWhere((r) => r.partNo == 'P1001').status,
        isNot(CheckStatus.pass),
      );
      expect(report.count(CheckStatus.pass), 2);
    },
  );

  test(
    'hybrid recovers truncated batches without changing conservative verdicts',
    () async {
      final fixture = mutateBom(3);
      final local = compareBoms(
        readBom([fixture.left.grid], id: 'S'),
        readBom([fixture.right], id: 'A'),
        null,
      );
      server.fallback = (body) {
        final items = (jsonDecode(user(body)) as List).cast<Map>();
        if (items.length > 1) {
          return FakeReply.openai({'answers': []}, finish: 'length');
        }
        return FakeReply.openai({
          'answers': [
            for (final it in items)
              {'id': it['id'], 'same': 'unsure', 'reason': 'review'},
          ],
        });
      };
      final (report, run) = await hybridCheck(local, provider());
      expect(run.complete, isTrue);
      expect(run.linesSent, local.rows.where(needsCloud).length);
      expect(run.linesSent, greaterThan(0));
      expect(
        report.rows.any((r) => r.reasons.contains('cloud_missing')),
        isFalse,
      );
      expect(report.count(CheckStatus.pass), local.count(CheckStatus.pass));
    },
  );

  test(
    'analysis batches and splits preserve privacy, aliases and findings',
    () async {
      final input = grid(25);
      final report = compareBoms(
        readBom([input], id: 'S'),
        readBom([input], id: 'A'),
        null,
      );
      server.fallback = (body) {
        final text = user(body);
        expect(text, isNot(contains('P1001')));
        expect(text, isNot(contains('"refs"')));
        final rows = (jsonDecode(text)['rows'] as List).cast<Map>();
        if (rows.length > 3) {
          return FakeReply.openai({
            'summary': 'partial',
            'findings': [],
          }, finish: 'length');
        }
        return FakeReply.openai({
          'summary': '${rows.length} rows',
          'findings': [
            for (final row in rows)
              {
                'partNo': row['partNo'],
                'field': 'description',
                'severity': 'info',
                'message': 'review',
              },
            {
              'partNo': 'invented',
              'field': 'description',
              'severity': 'info',
              'message': 'drop',
            },
          ],
        });
      };
      final result = await runAiCheck(
        provider(),
        report,
        privacy: const PrivacyOptions(partNumbers: false, designators: false),
      );
      expect(result.findings, hasLength(25));
      expect(result.findings.map((f) => f.partNo).toSet(), {
        for (var i = 1; i <= 25; i++) 'P${1000 + i}',
      });
      expect(result.summary, isNot(contains('partial')));
      expect(result.dropped, greaterThan(0));
      expect(result.usage.requests, server.requests.length);
      expect(server.requests.length, greaterThan(3));
    },
  );
}
