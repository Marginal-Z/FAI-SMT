import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/compare.dart';
import 'package:smt_fai/core/discrepancies.dart';
import 'package:smt_fai/core/models.dart';
import 'package:smt_fai/core/parsers.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/core/smart_table.dart';
import 'package:smt_fai/core/table_reader.dart';
import 'package:smt_fai/l10n/texts.dart';

Grid g(List<List<String>> rows) => Grid('s', rows);

void main() {
  group('BOM ↔ BOM', () {
    final a = [
      BomItem(partNo: 'P-R10K', name: '电阻', spec: '10K 0402', qty: 3, refs: ['R1', 'R2', 'R3'], extras: {'厂商': 'Yageo'}),
      BomItem(partNo: 'P-C100N', name: '电容', spec: '100nF 0402', qty: 2, refs: ['C1', 'C2']),
      BomItem(partNo: 'P-U1', name: 'IC', spec: 'MCU', qty: 1, refs: ['U1']),
      BomItem(partNo: 'P-OLD', name: 'LDO', spec: 'SOT23', qty: 1, refs: ['U2']),
      BomItem(partNo: 'P-GONE', name: 'LED', spec: '0603', qty: 1, refs: ['LED1']),
      BomItem(partNo: 'P-ALT1', name: '电感', spec: '2.2uH', qty: 1, refs: ['L1']),
    ];
    final b = [
      BomItem(partNo: 'P-R10K', name: '电阻', spec: '10K 0402', qty: 2, refs: ['R1', 'R2'], extras: {'厂商': 'Murata'}),
      BomItem(partNo: 'P-C100N', name: '电容', spec: '100nF 50V 0402', qty: 2, refs: ['C1', 'C2']),
      BomItem(partNo: 'P-U1', name: 'IC', spec: 'MCU', qty: 1, refs: ['U1']),
      BomItem(partNo: 'P-NEW', name: 'LDO', spec: 'SOT23', qty: 1, refs: ['U2']),
      BomItem(partNo: 'P-R3', name: '电阻', spec: '0R', qty: 1, refs: ['R3']),
      BomItem(partNo: 'P-ADD', name: '电容', spec: '1uF', qty: 1, refs: ['C9']),
      BomItem(partNo: 'P-ALT2', name: '电感', spec: '2.2uH', qty: 1, refs: ['L1']),
    ];
    final rules = CheckRules(substitutes: {'P-ALT1': ['P-ALT2']});
    final res = compareBoms(a, b, rules);
    ResultRow row(String pnA, [String? pnB]) => res.rows.firstWhere((r) => r.cells['pnA'] == pnA && (pnB == null || r.cells['pnB'] == pnB));
    List<String> codes(ResultRow r) => r.reasons.map((e) => e.code).toList();

    test('identical lines pass', () {
      expect(row('P-U1').category, CheckCategory.pass);
      expect(row('P-U1').reasons, isEmpty);
    });
    test('quantity, designators moved to another part and other columns', () {
      final r = row('P-R10K');
      expect(r.category, CheckCategory.ng);
      expect(codes(r), containsAll(['cmp_qty', 'cmp_refs_moved', 'cmp_field']));
      expect(r.reasons.firstWhere((e) => e.code == 'cmp_refs_moved').args, {'refs': 'R3', 'pn': 'P-R3'});
      final from = res.rows.firstWhere((x) => x.cells['pnB'] == 'P-R3');
      expect(codes(from), containsAll(['cmp_only_b', 'cmp_refs_from']));
    });
    test('description differences', () {
      expect(codes(row('P-C100N')), ['cmp_desc']);
    });
    test('part number changed on the same designators', () {
      final r = row('P-OLD', 'P-NEW');
      expect(r.category, CheckCategory.ng);
      expect(codes(r), ['cmp_pn_changed']);
    });
    test('registered alternate is a substitute', () {
      final r = row('P-ALT1', 'P-ALT2');
      expect(r.category, CheckCategory.substitute);
      expect(codes(r), ['cmp_alt_swap']);
    });
    test('lines only in one BOM', () {
      expect(codes(row('P-GONE')), ['cmp_only_a']);
      expect(codes(res.rows.firstWhere((x) => x.cells['pnB'] == 'P-ADD')), ['cmp_only_b']);
    });
    test('designator map', () {
      final r3 = res.refPairs.firstWhere((p) => p.ref == 'R3');
      expect(r3.state, RefPairState.changed);
      expect(res.refPairs.firstWhere((p) => p.ref == 'LED1').state, RefPairState.onlyA);
      expect(res.refPairs.firstWhere((p) => p.ref == 'C9').state, RefPairState.onlyB);
    });
    test('user exclusion keywords apply, none by default', () {
      expect(compareBoms(a, b, CheckRules()).rows.where((r) => r.category == CheckCategory.excluded), isEmpty);
      final ex = compareBoms(a, b, CheckRules(excludeKeywords: ['LED']));
      expect(ex.rows.firstWhere((r) => r.cells['pnA'] == 'P-GONE').category, CheckCategory.excluded);
    });
    test('quantity against designators inside one BOM', () {
      final r = compareBoms([BomItem(partNo: 'X', qty: 3, refs: ['R1'])], [BomItem(partNo: 'X', qty: 3, refs: ['R1'])], CheckRules());
      expect(r.rows.single.reasons.map((e) => e.code), ['cmp_qty_refs', 'cmp_qty_refs']);
      expect(r.findings.map((d) => d.source), containsAll([Source.bomA, Source.bomB]));
    });
    test('edits stay on the row and can be undone', () {
      final r = row('P-U1');
      r.cells['qtyA'] = '9';
      r.category = CheckCategory.ng;
      r.note = 'checked';
      expect(r.edited, isTrue);
      expect(r.cellEdited('qtyA'), isTrue);
      r.reset();
      expect(r.edited, isFalse);
      expect(r.cells['qtyA'], '1');
    });
    test('every compare reason is translated and explained', () {
      for (final code in [
        'cmp_only_a', 'cmp_only_b', 'cmp_pn_changed', 'cmp_alt_swap', 'cmp_qty', 'cmp_desc', 'cmp_alt_diff', 'cmp_field', //
        'cmp_refs_removed', 'cmp_refs_added', 'cmp_refs_moved', 'cmp_refs_from', 'cmp_qty_refs', 'cmp_dup_refs', 'cmp_ref_shared',
      ]) {
        expect(Texts.has(code), isTrue, reason: code);
        expect(Texts.has('why_$code'), isTrue, reason: code);
      }
    });
  });

  group('BOM ↔ station lists', () {
    final bom = parseBom([
      g([
        ['x1', 'x2', 'x3', 'x4'],
        ['K1-0001', '电阻 10K 0402', '2', 'R1,R2'],
        ['K1-0002', '电容 1uF 0402', '2', 'C1,C2'],
        ['K1-0003', 'IC LDO SOT23-5', '1', 'U1'],
      ])
    ]).items;

    test('one list whose side column splits A and B', () {
      final st = parseStation([
        g([
          ['F', 'PN', 'D', 'N', 'Pos', 'Face'],
          ['1-01', 'K1-0001', '10K 0402', '2', 'R1 R2', 'TOP'],
          ['1-02', 'K1-0002', '1uF 0402', '1', 'C1', 'TOP'],
          ['2-01', 'K1-0002', '1uF 0402', '1', 'C2', 'BOT'],
          ['2-02', 'K1-0003', 'LDO SOT23-5', '1', 'U1', 'BOT'],
        ])
      ], StationSide.a).items;
      final res = compareBomStations(bom, st, CheckRules(), mode: CompareMode.bomStation);
      expect(res.rows.every((r) => r.category == CheckCategory.pass), isTrue, reason: res.rows.map((r) => r.reasons.map((e) => e.code)).toString());
      expect(res.rows.firstWhere((r) => r.cells['pn'] == 'K1-0002').cells['side'], 'A/B');
    });

    test('lists A and B with a missing designator', () {
      final a = [StationItem(partNo: 'K1-0001', side: StationSide.a, slot: '1', refs: ['R1', 'R2']), StationItem(partNo: 'K1-0002', side: StationSide.a, slot: '2', refs: ['C1'])];
      final b = [StationItem(partNo: 'K1-0003', side: StationSide.b, slot: '1', refs: ['U1'])];
      final res = compareBomStations(bom, [...a, ...b], CheckRules(), mode: CompareMode.bomStationAB);
      final c = res.rows.firstWhere((r) => r.cells['pn'] == 'K1-0002');
      expect(c.category, CheckCategory.ng);
      expect(c.reasons.map((e) => e.code), contains('e_missing'));
      expect(res.findings.any((d) => d.code == 'e_missing'), isTrue);
    });
  });

  group('cross-file part numbers', () {
    test('the shared code column becomes the part number', () {
      // File A carries an MPN column that looks more like a part number on
      // its own; only the internal numbers are shared with file B.
      final la = detectTable([
        g([
          ['a', 'b', 'c', 'd'],
          ['RC0402FR-0710KL', '1001-000001', 'R1,R2', '2'],
          ['GRM155R71C104KA88D', '1001-000002', 'C1', '1'],
          ['TPS62130RGTR', '1001-000003', 'U1', '1'],
        ])
      ], TableKind.bom)!;
      final lb = detectTable([
        g([
          ['p', 'q', 'r'],
          ['1001-000001', 'R1,R2', '2'],
          ['1001-000002', 'C1', '1'],
          ['1001-000003', 'U1', '1'],
        ])
      ], TableKind.bom)!;
      final (x, y) = alignPartColumns(la, lb);
      expect(x.col(ColumnRole.partNo), 1);
      expect(y.col(ColumnRole.partNo), 0);
    });
  });

  group('rules', () {
    test('exclusion keywords are empty by default', () {
      expect(CheckRules().excludeKeywords, isEmpty);
      expect(CheckRules.fromJson(CheckRules().toJson()).excludeKeywords, isEmpty);
    });
    test('an untouched old default list is dropped, user keywords are kept', () {
      expect(CheckRules.fromJson({'excludeKeywords': CheckRules.legacyExcludeKeywords}).excludeKeywords, isEmpty);
      expect(CheckRules.fromJson({'excludeKeywords': ['PCB', '锡膏']}).excludeKeywords, ['PCB', '锡膏']);
      final saved = CheckRules(excludeKeywords: [...CheckRules.legacyExcludeKeywords]).toJson();
      expect(CheckRules.fromJson(saved).excludeKeywords, CheckRules.legacyExcludeKeywords);
    });
    test('old built-in ignore list is dropped, nothing is built in any more', () {
      final r = CheckRules();
      expect([r.excludeKeywords, r.excludePrefixes, r.ignoreRefPatterns, r.substitutes.keys], everyElement(isEmpty));
      expect(CheckRules.fromJson({'schema': 2, 'ignoreRefPatterns': CheckRules.legacyIgnoreRefs}).ignoreRefPatterns, isEmpty);
      expect(CheckRules.fromJson({'schema': 2, 'ignoreRefPatterns': ['MARK*']}).ignoreRefPatterns, ['MARK*']);
      expect(CheckRules.fromJson(CheckRules(ignoreRefPatterns: [...CheckRules.legacyIgnoreRefs]).toJson()).ignoreRefPatterns, CheckRules.legacyIgnoreRefs);
    });
    test('AI settings survive a save', () {
      final s = AppSettings(ai: AiSettings(provider: AiProvider.openai, baseUrl: 'https://x/v1', apiKey: 'k', model: 'm'));
      final back = AppSettings.fromJson(s.toJson()).ai;
      expect(back.provider, AiProvider.openai);
      expect(back.configured, isTrue);
      expect(AiSettings().effectiveModel, 'claude-opus-5-5');
      expect(AiSettings().configured, isFalse);
    });
  });
}
