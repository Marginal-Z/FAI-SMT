import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/orientation.dart';
import 'package:smt_fai/core/report.dart';
import 'package:smt_fai/core/table_reader.dart';
import 'package:smt_fai/l10n/texts.dart';

BomPart part(String desc, List<String> refs, {bool dnp = false}) => BomPart(
  'P1001',
  description: desc,
  quantity: 1,
  refs: refs,
  extra: {},
  sources: [],
  dnp: dnp,
);
void main() {
  test('a later source description still triggers a polarity reminder', () {
    BomDocument doc(String id) => readBom([Grid('s', [['料号', '描述', '用量', '位号'], ['P1001', '陶瓷电容 10uF', '1', 'C1'], ['P1001', '钽电容 10uF', '1', 'C2']])], id: id);
    final r = compareBoms(doc('S'), doc('A'), null).rows.single;
    expect(r.orientation.any((h) => h.code == 'polar_cap'), isTrue);
    expect(r.orientation.firstWhere((h) => h.code == 'polar_cap').refs, ['C1', 'C2']);
  });
  test('required reminders include exact refs and evidence', () {
    for (final (desc, refs, code) in [
      ('LED 红色 0603', ['D1'], 'diode'),
      ('钽电容 10uF', ['C1'], 'polar_cap'),
      ('IC STM32 QFN48', ['U1'], 'pin1'),
      ('MOSFET SOT23', ['Q1'], 'pin1'),
      ('Connector 2x5', ['J1'], 'mechanical'),
      ('电容 100uF', ['C1'], 'cap_unknown'),
      ('TVS bidirectional', ['D1'], 'bidirectional'),
      ('Resistor network', ['RN1'], 'pin1'),
    ]) {
      final h = orientationHints([part(desc, refs)])
          .firstWhere((h) => h.code == code);
      expect(h.refs, refs);
      expect(h.evidence, contains(desc));
    }
  });
  test(
    'passives, explicit nonpolar and DNP are not generic polarity alerts',
    () {
      for (final p in [
        part('电阻 10K 0402', ['R1']),
        part('MLCC 100nF X7R', ['C1']),
        part('无极性电解电容', ['C1']),
        part('LED red', ['D1'], dnp: true),
      ]) {
        expect(orientationHints([p]), isEmpty, reason: p.description);
      }
    },
  );
  test(
    'reminders are independent from PASS and persist through Excel roundtrip',
    () {
      BomDocument doc(String id) => readBom([
        Grid('s', [
          ['料号', '描述', '用量', '位号'],
          ['P1001', 'LED red 0603', '1', 'D1'],
        ]),
      ], id: id);
      final r = compareBoms(doc('S'), doc('A'), null);
      expect(r.rows.single.status, CheckStatus.pass);
      expect(r.rows.single.orientation.single.refs, ['D1']);
      final t = Texts('zh').t;
      final grids = readTableBytes(exportCompareWorkbook(r, t), 'out.xlsx');
      expect(
        grids.first.rows.expand((x) => x),
        contains(t('orientation_title')),
      );
      expect(
        grids.first.rows
            .expand((x) => x)
            .any((x) => x.contains(t('orientation_diode')) && x.contains('D1')),
        isTrue,
      );
    },
  );
}
