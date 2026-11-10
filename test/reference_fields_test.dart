import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/table_reader.dart';
import 'package:smt_fai/core/local_ai/local_review.dart';
import 'package:smt_fai/core/ai_check.dart';
import 'package:smt_fai/core/report.dart';
import 'package:smt_fai/l10n/strings.dart';

import 'support/local_models.dart';

BomDocument document(
  String id, {
  String old = '',
  String maker = 'Yageo',
  String qty = '1',
  String desc = '贴片电阻 47K 0201 1/20W ±5%',
}) => readBom([
  Grid('BOM', [
    ['料号', '物料描述', '用量', '位号', '旧料号', '厂商'],
    ['K1201-AA4730-J10A', desc, qty, 'R1', old, maker],
  ]),
], id: id);

void main() {
  test(
    'old part number difference is visible reference metadata, not NG',
    () async {
      final report = compareBoms(
        document('S'),
        document('A', old: 'OLD-47K'),
        null,
      );
      final r = report.rows.single;
      expect(r.status, CheckStatus.pass);
      expect(r.referenceDifferences.single.header, '旧料号');
      expect(r.referenceDifferences.single.merged, 'OLD-47K');
      expect(r.materialDifferences, isEmpty);
      expect(riskOf(r), Risk.none);
      final model = FakeLocalModels();
      final reviewed = await reviewLocally(report, model);
      expect(reviewed.report.rows.single.status, CheckStatus.pass);
      expect(reviewed.report.rows.single.referenceDifferences, hasLength(1));
      expect(jsonEncode(model.prompts), isNot(contains('OLD-47K')));
      expect(comparisonJson(report), isNot(contains('OLD-47K')));
      final sheet = buildCompareWorkbook(report, Strings('zh').t).sheets.first;
      final header = List.generate(
        sheet.rowCount,
        (i) => i,
      ).firstWhere((i) => sheet.value(i, 0) == '#');
      expect(
        List.generate(
          40,
          (i) => '${sheet.value(header, i) ?? ''}',
        ).any((x) => x.contains('旧料号 · 仅供参考')),
        isTrue,
      );
    },
  );
  test('one-sided reference column and forced MPN recognition retain reference semantics', () {
    final reference = readBom(
      [
        Grid('BOM', [
          ['料号', '物料描述', '用量', '位号', '旧料号'],
          [
            'K1201-AA4730-J10A',
            '贴片电阻 47K 0201 1/20W ±5%',
            '1',
            'R1',
            'OLD-47K',
          ],
        ]),
      ],
      id: 'A',
      overrides: {
        'BOM': {4: BomRole.mpn},
      },
    );
    expect(reference.columns.last.role, BomRole.other);
    final base = readBom([
      Grid('BOM', [
        ['料号', '物料描述', '用量', '位号'],
        ['K1201-AA4730-J10A', '贴片电阻 47K 0201 1/20W ±5%', '1', 'R1'],
      ]),
    ], id: 'S');
    final row = compareBoms(base, reference, null).rows.single;
    expect(row.status, CheckStatus.pass);
    expect(row.referenceDifferences.single.merged, 'OLD-47K');
    expect(reference.parts.single.alternates, isEmpty);
  });
  test('reference metadata cannot mask quantity, manufacturer or parameter conflict', () {
    for (final other in [
      document('A', old: 'OLD', qty: '2'),
      document('A', old: 'OLD', maker: 'Vishay'),
      document('A', old: 'OLD', desc: '贴片电阻 10K 0201 1/20W ±5%'),
    ]) {
      final r = compareBoms(document('S'), other, null).rows.single;
      expect(r.status, CheckStatus.ng);
      expect(r.materialDifferences, isNotEmpty);
      expect(r.referenceDifferences, hasLength(1));
    }
  });
  test('reference allowlist never treats manufacturer or approved alternates as reference', () {
    for (final name in ['旧料号', '舊料號', 'Old Part Number', 'legacy_pn']) {
      expect(isReferenceColumn(name), isTrue);
    }
    for (final name in [
      'mpn',
      'maker',
      'alternate',
      '规格',
      '颜色',
      '客户料号',
      'unknown',
    ]) {
      expect(isReferenceColumn(name), isFalse);
    }
    expect(document('S', old: 'OLD').parts.single.alternates, isEmpty);
  });
}
