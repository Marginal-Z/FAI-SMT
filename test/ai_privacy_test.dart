import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/ai_check.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/cloud/hybrid.dart';
import 'package:smt_fai/core/cloud/provider.dart';
import 'package:smt_fai/core/table_reader.dart';
import 'support/fake_llm_server.dart';

void main() {
  test('analysis respects all privacy options and maps aliases back', () async {
    BomDocument doc(String id) => readBom([Grid('s', [['料号', '描述', '用量', '位号', 'Manufacturer'], ['SECRET-P1001', '电阻 10K 0402', '1', 'R987', 'PRIVATE_MAKER']])], id: id);
    final report = compareBoms(doc('S'), doc('A'), null);
    final server = await FakeLlmServer.start();
    addTearDown(server.close);
    server.fallback = (body) {
      final payload = ((body['messages'] as List).last as Map)['content'] as String;
      expect(payload, isNot(contains('SECRET-P1001')));
      expect(payload, isNot(contains('R987')));
      expect(payload, isNot(contains('PRIVATE_MAKER')));
      final row = (jsonDecode(payload)['rows'] as List).single as Map;
      return FakeReply.openai({'summary': 'Review', 'findings': [
        {'partNo': row['partNo'], 'field': 'description', 'side': 'both', 'severity': 'warning', 'message': 'Check'}
      ]});
    };
    final result = await runAiCheck(HttpCloudProvider(ProviderConfig(kind: ProviderKind.custom, baseUrl: server.url, minIntervalMs: 0), ''), report, privacy: const PrivacyOptions(partNumbers: false, designators: false, otherColumns: false));
    expect(result.findings.single.partNo, 'SECRET-P1001');
    expect(result.dropped, 0);
  });
}
