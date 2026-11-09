import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/table_reader.dart';

BomDocument doc(
  List<List<String>> rows,
  String id, {
  List<String> header = const ['料号', '描述', '用量', '位号', 'Manufacturer', 'Level'],
}) => readBom(
  [
    Grid('BOM', [header, ...rows]),
  ],
  id: id,
  file: '$id.csv',
);
List<String> line(
  String pn,
  String desc,
  String qty,
  String refs, {
  String maker = 'Yageo',
  String level = '1',
}) => [pn, desc, qty, refs, maker, level];

void main() {
  test('an unrecognized fitted flag cannot silently pass', () {
    final a = doc([['P1001', '电阻 10K 0402', '1', 'R1', 'MAYBE']], 'S', header: ['料号', '描述', '用量', '位号', 'DNP']);
    final b = doc([['P1001', '电阻 10K 0402', '1', 'R1', 'MAYBE']], 'A', header: ['料号', '描述', '用量', '位号', 'DNP']);
    expect(compareBoms(a, b, null).rows.single.status, CheckStatus.review);
    expect(compareBoms(a, b, null).rows.single.reasons, contains('dnp_unsure'));
  });
  test('unfamiliar header followed by blank rows is never a component', () {
    final d = readBom([Grid('s', [['代料', 'Lead time', 'RoHS', 'SKU', 'Pcs/board', '物料说明', 'Bestückt', 'Bestückung'], [], ['15-7025-822', 'N/A', '', '75-6627-000', '1', '晶振 8MHz 3225', 'Y', 'Y1']])], id: 'S');
    expect(d.parts.map((p) => p.partNo), ['75-6627-000']);
    expect(d.headerRow, 0);
  });
  test(
    'quantity consumes the whole cell, with scientific and grouped numbers',
    () {
      expect(parseQuantity('1e3'), 1000);
      expect(parseQuantity('1,000 pcs'), 1000);
      for (final v in ['1/2', '1,5', '2+3', '2oops', '-1']) {
        expect(parseQuantity(v), isNull, reason: v);
      }
    },
  );
  test(
    'later same-part specifications are checked, within a file and across B+C',
    () {
      final s = doc([line('P1001', '电阻 10K 0402', '2', 'R1,R2')], 'S');
      final a = doc([
        line('P1001', '电阻 10K 0402', '1', 'R1'),
        line('P1001', '电阻 22K 0402', '1', 'R2'),
      ], 'A');
      final one = compareBoms(s, a, null).rows.single;
      expect(one.status, CheckStatus.ng);
      expect(one.reasons, contains('input_conflict'));
      expect(
        one.fields.where((f) => f.key.startsWith('input:')).single.merged,
        contains('22K'),
      );
      final two = compareBoms(
        s,
        doc([line('P1001', '电阻 10K 0402', '1', 'R1')], 'A'),
        doc([line('P1001', '电阻 22K 0402', '1', 'R2')], 'B'),
      ).rows.single;
      expect(two.status, CheckStatus.ng);
    },
  );
  test('later attributes cannot be masked by first row', () {
    final s = doc([line('P1001', '电阻 10K 0402', '2', 'R1,R2')], 'S');
    final a = doc([
      line('P1001', '电阻 10K 0402', '1', 'R1'),
      line('P1001', '电阻 10K 0402', '1', 'R2', maker: 'Vishay'),
    ], 'A');
    expect(
      compareBoms(s, a, null).rows.single.reasons,
      contains('input_conflict'),
    );
  });
  test('identical duplicated refs on both sides cannot pass', () {
    final rows = [line('P1001', '电阻 10K 0402', '2', 'R1,R1')];
    final r = compareBoms(doc(rows, 'S'), doc(rows, 'A'), null).rows.single;
    expect(r.status, CheckStatus.ng);
    expect(r.reasons, contains('duplicate_refs'));
  });
  test('same internal quantity/ref mismatch still needs review', () {
    final rows = [line('P1001', '电阻 10K 0402', '3', 'R1,R2')];
    final r = compareBoms(doc(rows, 'S'), doc(rows, 'A'), null).rows.single;
    expect(r.status, CheckStatus.review);
    expect(r.reasons, contains('qty_refs'));
  });
  test(
    'blank quantity in a repeated row cannot be hidden by a partial sum',
    () {
      final s = doc([line('P1001', '电阻 10K 0402', '1', 'R1,R2')], 'S');
      final a = doc([
        line('P1001', '电阻 10K 0402', '1', 'R1'),
        line('P1001', '电阻 10K 0402', '', 'R2'),
      ], 'A');
      expect(
        compareBoms(s, a, null).rows.single.reasons,
        contains('qty_invalid'),
      );
    },
  );
  test('BOM level survives merging', () {
    final s = doc([line('P1001', '电阻 10K 0402', '1', 'R1', level: '2')], 'S');
    final a = doc([line('P1001', '电阻 10K 0402', '1', 'R1')], 'A');
    expect(compareBoms(s, a, null).rows.single.reasons, contains('level'));
  });
  test('Not fitted is a negative header', () {
    final d = doc(
      [
        ['P1001', '电阻 10K 0402', '1', 'R1', 'YES'],
        ['P1002', '电阻 22K 0402', '1', 'R2', 'NO'],
      ],
      'S',
      header: ['料号', '描述', '用量', '位号', 'Not fitted'],
    );
    expect(d.parts.first.dnp, isTrue);
    expect(d.parts.last.dnp, isFalse);
  });
  test('missing requested designator column is explicit review', () {
    final s = doc([line('P1001', '电阻 10K 0402', '1', 'R1')], 'S');
    final a = doc(
      [
        ['P1001', '电阻 10K 0402', '1'],
      ],
      'A',
      header: ['料号', '描述', '用量'],
    );
    expect(
      compareBoms(s, a, null).rows.single.reasons,
      contains('field_unavailable'),
    );
  });
  test('Chinese discriminators count and bilingual equivalents agree', () {
    expect(compareDescription('红色 LED 0603', '绿色 LED 0603').equal, isFalse);
    expect(compareDescription('电解电容 10uF 16V', '陶瓷电容 10uF 16V').equal, isFalse);
    expect(compareDescription('红色 LED 0603', 'RED LED 0603').equal, isTrue);
    expect(compareDescription('无极性电容 10uF', '有极性电容 10uF').equal, isFalse);
  });
  test(
    'ambiguous maker part numbers do not consume an arbitrary left part',
    () {
      final s = doc(
        [
          ['P1001', 'Special device A', '1', 'ABC12345'],
          ['P1002', 'Special device B', '1', 'ABC12345'],
        ],
        'S',
        header: ['料号', '描述', '用量', 'MPN'],
      );
      final a = doc(
        [
          ['Q1001', 'Special device', '1', 'ABC12345'],
        ],
        'A',
        header: ['料号', '描述', '用量', 'MPN'],
      );
      expect(
        compareBoms(s, a, null).rows.any((r) => r.basis.kinds.contains('mpn')),
        isFalse,
      );
    },
  );
  test('explicitly skipped fields do not add input findings', () {
    final rows = [line('P1001', '电阻 10K 0402', '2', 'R1,R1')];
    final r = compareBoms(
      doc(rows, 'S'),
      doc(rows, 'A'),
      null,
      options: const CompareOptions(skip: {'refs'}),
    ).rows.single;
    expect(r.status, CheckStatus.pass);
  });
}
