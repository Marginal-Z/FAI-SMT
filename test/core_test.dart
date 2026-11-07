import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/ai_check.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/classify.dart';
import 'package:smt_fai/core/refdes.dart';
import 'package:smt_fai/core/report.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/core/table_reader.dart';
import 'package:smt_fai/core/updater.dart';
import 'package:smt_fai/core/xlsx_writer.dart';
import 'package:smt_fai/l10n/strings.dart';
import 'package:smt_fai/version.dart';

Grid g(List<List<String>> rows) => Grid('s', rows);

BomDocument bom(List<List<String>> rows) => readBom([g(rows)]);

BomDocument demo(String name, {String id = 'S'}) {
  final p = 'samples/demo/$name';
  return readBom(readTableBytes(File(p).readAsBytesSync(), p), file: name, id: id);
}

void main() {
  group('refdes', () {
    test('splits mixed separators and expands ranges', () {
      expect(splitRefs('3U2,3U3'), ['3U2', '3U3']);
      expect(splitRefs('c1、C2；c3 c4'), ['C1', 'C2', 'C3', 'C4']);
      expect(splitRefs('R1-R3'), ['R1', 'R2', 'R3']);
      expect(splitRefs('R8~10'), ['R8', 'R9', 'R10']);
      expect(splitRefs('J1-A'), ['J1-A']);
    });
    test('natural sort', () {
      expect(sortedRefs(['R10', 'R2', 'C1', 'R1']), ['C1', 'R1', 'R2', 'R10']);
    });
  });

  group('reading BOMs', () {
    test('header words in any language, title rows above the header', () {
      final f = bom([
        ['物料清单  机种 X1'],
        ['序号', '料号', '品名', '规格', '用量', '位号', '品牌'],
        ['1', 'K1102-1020K0-001A', '贴片电阻', '10K ±1% 0402', '3', 'R1,R2,R3', 'Yageo'],
        ['2', 'K1103-0104K0-001A', '贴片电容', '100nF 16V 0402', '2', 'C1 C2', 'Murata'],
        ['3', 'K1105-24M000-001A', '晶振', '24MHz 3225', '1', 'Y1', 'TXC'],
      ]);
      expect(f.headerRow, 1);
      expect(f.column(BomRole.partNo)!.header, '料号');
      expect(f.column(BomRole.quantity)!.header, '用量');
      expect(f.column(BomRole.refs)!.header, '位号');
      expect(f.others.map((c) => c.header), ['品牌']);
      final r = f.parts.first;
      // 品名 and 规格 both describe the part and are read as one description.
      expect(r.description, '贴片电阻 10K ±1% 0402');
      expect(r.quantity, 3);
      expect(r.refs, ['R1', 'R2', 'R3']);
    });

    test('no header row: columns recognised by their content, in any order', () {
      final f = bom([
        ['R1,R2,R3', 'K1102-1020K0-001A', '贴片电阻 10K ±1% 0402', '3'],
        ['C1,C2', 'K1103-0104K0-001A', '贴片电容 100nF 16V X7R 0402', '2'],
        ['Y1', 'K1105-24M000-001A', '贴片晶振 24MHz 3225', '1'],
        ['U1', 'K1101-1C302X-001A', '贴片IC 主芯片 BGA128', '1'],
        ['L1,L2', 'K1104-2R2M00-001A', '贴片电感 2.2uH 2520', '2'],
      ]);
      expect(f.headerRow, -1);
      expect(f.column(BomRole.refs)!.index, 0);
      expect(f.column(BomRole.partNo)!.index, 1);
      expect(f.column(BomRole.description)!.index, 2);
      expect(f.column(BomRole.quantity)!.index, 3);
      expect(f.parts, hasLength(5));
    });

    test('headers that name nothing useful still read by content', () {
      final f = bom([
        ['A', 'B', 'C', 'D'],
        ['K1102-1020K0-001A', '10K 0402 电阻', '2', 'R1,R2'],
        ['K1103-0104K0-001A', '100nF 0402 电容', '1', 'C1'],
        ['K1105-24M000-001A', '24MHz 晶振', '1', 'Y1'],
        ['K1104-2R2M00-001A', '2.2uH 电感', '2', 'L1,L2'],
      ]);
      expect(f.column(BomRole.partNo)!.index, 0);
      expect(f.column(BomRole.refs)!.index, 3);
      expect(f.column(BomRole.quantity)!.index, 2);
      expect(f.column(BomRole.description)!.index, 1);
    });

    test('continuation rows, repeated parts and warnings', () {
      final f = bom([
        ['料号', '描述', '用量', '位号'],
        ['K1', '贴片电阻 10K 0402', '7', 'R1,R2,R3,R4,R5'],
        ['', '', '', 'R6,R7'],
        ['K2', '贴片电容 1uF 0402', '3', 'C1,C2'],
        ['K3', '贴片电容 10uF 0603', '1', 'C3'],
        ['K3', '贴片电容 10uF 0603', '1', 'C4'],
        ['K4', '贴片电感 1uH', '1', 'R1'],
      ]);
      final k1 = f.parts.firstWhere((p) => p.partNo == 'K1');
      expect(k1.refs, hasLength(7));
      final k3 = f.parts.firstWhere((p) => p.partNo == 'K3');
      expect(k3.quantity, 2);
      expect(k3.refs, ['C3', 'C4']);
      expect(f.warnings.map((w) => w.code), containsAll(['w_qty_refs', 'w_dup_ref']));
    });

    test('two-row header with merged cells; part numbers merged down', () {
      // Row 0: 料号 and 用量 merged down, 物料 merged across 品名 + 规格.
      final grid = Grid('s', [
        ['料号', '物料', '', '用量', '位号'],
        ['', '品名', '规格', '', ''],
        ['K1', '贴片电阻', '10K 0402', '2', 'R1,R2'],
        ['K2', '贴片电容', '1uF 0402', '1', 'C1'],
        ['', '', '', '1', 'C2'],
        ['K3', '电感', '2.2uH', '1', 'L1'],
      ], merges: [(0, 0, 1, 0), (0, 1, 0, 2), (0, 3, 1, 3), (0, 4, 1, 4), (3, 0, 4, 0), (3, 1, 4, 1), (3, 2, 4, 2)]);
      final d = readBom([grid]);
      expect(d.column(BomRole.partNo)!.header, '料号');
      expect(d.columns.where((c) => c.role == BomRole.description).map((c) => c.header), ['物料 品名', '物料 规格']);
      expect(d.records.first.source.row, 3);
      // K2 is merged over two rows, each with its own quantity and designator.
      final k2 = d.parts.firstWhere((p) => p.partNo == 'K2');
      expect(k2.quantity, 2);
      expect(k2.refs, ['C1', 'C2']);
      expect(k2.rows, [4, 5]);
      expect(d.parts.firstWhere((p) => p.partNo == 'K3').quantity, 1);
    });
    test('quoted CSV fields may hold line breaks', () {
      final text = 'PN,Description,Qty,Designator\nK1,"Resistor 10K\n0402",3,"R1,\nR2,R3"\nK2,Cap 1uF 0402,1,C1\n';
      final grids = readTableBytes(Uint8List.fromList(utf8.encode(text)), 'x.csv');
      final d = readBom(grids);
      expect(d.parts.map((p) => p.partNo), ['K1', 'K2']);
      expect(d.parts.first.refs, ['R1', 'R2', 'R3']);
      expect(d.parts.first.description, 'Resistor 10K 0402');
      expect(d.records[1].source.row, 3);
    });
    test('sheets with the same columns are one BOM', () {
      List<List<String>> sheet(List<List<String>> rows) => [['料号', '描述', '用量', '位号'], ...rows];
      final d = readBom([
        Grid('TOP', sheet([['K1', '电阻 10K 0402', '2', 'R1,R2'], ['K2', '电容 1uF', '1', 'C1']])),
        Grid('BOT', sheet([['K1', '电阻 10K 0402', '1', 'R3'], ['K3', '电感 1uH', '1', 'L1']])),
        Grid('Notes', [['Rev', 'Date'], ['A', '2026-01-01']]),
      ]);
      expect(d.records.map((r) => r.id), ['S:TOP!2', 'S:TOP!3', 'S:BOT!2', 'S:BOT!3']);
      expect(d.parts.firstWhere((p) => p.partNo == 'K1').refs, ['R1', 'R2', 'R3']);
      expect(d.sheets, ['TOP', 'BOT', 'Notes']);
    });
    test('digit-only part numbers and a brand column', () {
      final d = bom([
        ['460100030', '贴片电阻', '10K ±1% 0402', 'Yageo', '2', 'R1,R2'],
        ['460100031', '贴片电容', '1uF 10V 0402', 'Murata', '1', 'C1'],
        ['460100032', '贴片电感', '2.2uH 2A', 'Sunlord', '2', 'L1,L2'],
        ['460100033', '晶振', '24MHz 3225', 'TXC', '1', 'Y1'],
        ['460100034', '贴片电阻', '4.7K ±1% 0402', 'Yageo', '1', 'R3'],
      ]);
      expect(d.column(BomRole.partNo)!.index, 0);
      expect(d.column(BomRole.quantity)!.index, 4);
      expect(d.columns.where((c) => c.role == BomRole.description).map((c) => c.index), [1, 2]);
      expect(d.columns.firstWhere((c) => c.index == 3).role, isNot(BomRole.description));
    });
    test('a sheet without part numbers is refused', () {
      expect(() => bom([['hello'], ['world']]), throwsA(isA<BomReadException>()));
    });
  });

  group('unified model', () {
    test('records cite file, sheet and Excel row; continuation rows included', () {
      final d = readBom(readTableBytes(File('samples/demo/demo_single_BOM.xlsx').readAsBytesSync(), 'x.xlsx'), file: 'demo_single_BOM.xlsx', id: 'S');
      // Title on row 1, header on row 2: the first part is on Excel row 3.
      expect(d.headerRow + 1, 2);
      final first = d.records.first;
      expect(first.source, const SourceRef('demo_single_BOM.xlsx', 'BOM', 3));
      expect(first.id, 'S:BOM!3');
      expect(first.cells, hasLength(greaterThanOrEqualTo(7)));
      // Eight resistors: five designators on the part row, three on the next.
      final r = d.records.firstWhere((x) => x.partNo == 'K1102-1020K0-001A');
      expect(r.sources.map((x) => x.row), [r.source.row, r.source.row + 1]);
      expect(r.refs, hasLength(8));
      expect(d.toJson()['records'], hasLength(d.records.length));
    });
    test('a part listed twice is one part made of two records', () {
      final d = bom([
        ['料号', '描述', '用量', '位号'],
        ['K3', '电容 10uF 0603', '1', 'C3'],
        ['K4', '电阻 1K', '1', 'R1'],
        ['K3', '电容 10uF 0603', '1', 'C4'],
      ]);
      expect(d.records, hasLength(3));
      final k3 = d.parts.firstWhere((p) => p.partNo == 'K3');
      expect(k3.recordIds, ['S:s!2', 'S:s!4']);
      expect(k3.rows, [2, 4]);
      expect(k3.quantity, 2);
    });
    test('columns carry confidence and what they were recognised from', () {
      final d = demo('demo_B_BOM.xlsx');
      final refs = d.column(BomRole.refs)!;
      expect(refs.header, isEmpty);
      expect(refs.evidence, 'content');
      expect(refs.confidence, greaterThan(0.5));
      expect(refs.letter, 'A');
    });
  });

  group('item attributes', () {
    test('maker part numbers, makers, alternates by header and by form', () {
      final d = bom([
        ['料号', '描述', 'Mfr P/N', 'Manufacturer', '替代料号', '用量', '位号'],
        ['K1102-102000-001A', '贴片电阻 10K 0402', 'RC0402FR-0710KL', 'Yageo', 'K1102-102000-002A', '2', 'R1,R2'],
        ['K1103-010400-001A', '贴片电容 100nF 0402', 'GRM155R71C104KA88D', 'Murata', '', '1', 'C1'],
        ['K1104-022000-001A', '贴片电感 2.2uH', 'SWPA4020S2R2MT', 'Sunlord', '', '1', 'L1'],
      ]);
      expect(d.column(BomRole.partNo)!.header, '料号');
      expect(d.column(BomRole.mpn)!.header, 'Mfr P/N');
      expect(d.column(BomRole.maker)!.header, 'Manufacturer');
      expect(d.column(BomRole.alternate)!.header, '替代料号');
      expect(d.records.first.alternates, ['K1102-102000-002A']);
      // Without headers: a second code column of the same form holds
      // alternates, of another form maker part numbers.
      final h = bom([
        ['K1102-102000-001A', '贴片电阻 10K 0402', 'RC0402FR-0710KL', 'K1102-102000-002A', '2', 'R1,R2'],
        ['K1103-010400-001A', '贴片电容 100nF 0402', 'GRM155R71C104KA88D', '', '1', 'C1'],
        ['K1104-022000-001A', '贴片电感 2.2uH', 'SWPA4020S2R2MT', '', '1', 'L1'],
        ['K1105-024000-001A', '晶振 24MHz 3225', 'X322524MSB4SI', 'K1105-024000-003A', '1', 'Y1'],
      ]);
      expect(h.column(BomRole.partNo)!.index, 0);
      expect(h.column(BomRole.mpn)!.index, 2);
      expect(h.column(BomRole.alternate)!.index, 3);
    });
    test('DNP: by words, by "fitted" polarity, by majority without a header', () {
      final words = bom([
        ['料号', '描述', '用量', '位号', 'DNP'],
        ['K1', '电阻 10K', '1', 'R1', ''],
        ['K2', '电阻 1K', '1', 'R2', 'DNP'],
        ['K3', '电容 1uF NC', '1', 'C1', ''],
      ]);
      expect(words.records.map((r) => r.dnp), [false, true, true]);
      final fitted = bom([
        ['料号', '描述', '用量', '位号', '是否贴装'],
        ['K1', '电阻 10K', '1', 'R1', '是'],
        ['K2', '电阻 1K', '1', 'R2', '否'],
      ]);
      expect(fitted.records.map((r) => r.dnp), [false, true]);
      final majority = bom([
        ['K1102-1', '电阻 10K 0402', '1', 'R1', 'Y'],
        ['K1102-2', '电阻 1K 0402', '1', 'R2', 'N'],
        ['K1102-3', '电阻 2K 0402', '1', 'R3', 'Y'],
        ['K1102-4', '电阻 3K 0402', '1', 'R4', 'Y'],
      ]);
      expect(majority.column(BomRole.dnp)!.confidence, 0.5);
      expect(majority.records.map((r) => r.dnp), [false, true, false, false]);
      // "NC7SZ04" is a part name, not a "not connected" marker.
      expect(bom([['料号', '描述', '用量', '位号'], ['K1', 'IC NC7SZ04 SOT353', '1', 'U1']]).records.single.dnp, isFalse);
    });
    test('BOM levels and the assembly each line belongs to', () {
      final d = bom([
        ['Level', 'Part Number', 'Description', 'Qty', 'Designator'],
        ['1', 'A100', 'PCBA main board', '1', ''],
        ['2', 'R100', 'Resistor 10K 0402', '2', 'R1,R2'],
        ['2', 'C100', 'Capacitor 1uF 0402', '1', 'C1'],
        ['1', 'S100', 'Shield can', '1', ''],
      ]);
      expect(d.records.map((r) => r.level), [1, 2, 2, 1]);
      expect(d.records[1].parentId, d.records[0].id);
      expect(d.records[3].parentId, isNull);
      // Dotted depths are recognised without a header.
      final h = bom([
        ['.1', 'A100', 'PCBA 主板', '1', ''],
        ['..2', 'R100', '电阻 10K 0402', '2', 'R1,R2'],
        ['..2', 'C100', '电容 1uF 0402', '1', 'C1'],
      ]);
      expect(h.column(BomRole.level)!.index, 0);
    });
    test('item kinds from words, designators and units', () {
      (ItemKind, String) k(String d, [List<String> r = const []]) => classifyItem(d, r);
      expect(k('贴片电阻 10K 0402').$1, ItemKind.resistor);
      expect(k('Keramikkondensator 100nF').$1, ItemKind.capacitor);
      expect(k('Shielded power inductor 2.2uH').$1, ItemKind.inductor);
      expect(k('发光二极管 红色 0603').$1, ItemKind.led);
      expect(k('ESD bag 100x150').$1, ItemKind.packaging);
      expect(k('XYZ-123', ['U1', 'U2']), (ItemKind.ic, 'designator'));
      expect(k('10uF 6.3V 0603'), (ItemKind.capacitor, 'unit'));
      expect(k('ABC-123').$1, ItemKind.unknown);
    });
  });

  group('description rule', () {
    test('only letters and digits count; Chinese wording may differ', () {
      expect(compareDescription('贴片电阻 10K ±1% 0402', '贴片电阻器 10K ±1% 0402').equal, isTrue);
      expect(compareDescription('电容 100nF 16V', '贴片陶瓷电容，100nF 16V').equal, isTrue);
      expect(compareDescription('贴片LED 绿色 0603', '贴片LED 绿 0603').equal, isTrue);
      expect(compareDescription('0402 10K', '10K 0402').equal, isTrue);
    });
    test('a different parameter is a difference, case included', () {
      final f = compareDescription('贴片电容 10uF 6.3V X5R 0603', '贴片电容 10uF 10V X5R 0603');
      expect(f.equal, isFalse);
      expect(f.singleSpans.map((s) => f.single.substring(s.$1, s.$2)), ['6.3V']);
      expect(f.mergedSpans.map((s) => f.merged.substring(s.$1, s.$2)), ['10V']);
      expect(compareDescription('10K 0402', '10k 0402').equal, isFalse);
      expect(compareDescription('10K 0402', '10K 0402 1%').equal, isFalse);
    });
    test('other columns must match exactly', () {
      expect(compareExact('col:x', 'x', 'Murata', 'Murata').equal, isTrue);
      final f = compareExact('col:x', 'x', 'AOS', 'A0S');
      expect(f.equal, isFalse);
      expect(f.singleSpans, [(1, 2)]);
      expect(f.mergedSpans, [(1, 2)]);
    });
  });

  group('comparing', () {
    late CompareReport r;
    setUpAll(() => r = compareBoms(demo('demo_single_BOM.xlsx'), demo('demo_A_BOM.xlsx', id: 'A'), demo('demo_B_BOM.xlsx', id: 'B')));
    CompareRow row(String pn) => r.rows.firstWhere((x) => x.partNo == pn);

    test('A and B are merged and compared with the single BOM', () {
      expect(r.count(DiffStatus.same), 21);
      expect(r.count(DiffStatus.different), 5);
      expect(r.count(DiffStatus.onlySingle), 1);
      expect(r.count(DiffStatus.onlyMerged), 1);
      // Parts from the headerless B-BOM, reworded descriptions on A.
      expect(row('K1102-1020K0-001A').sources, ['B']);
      expect(row('K1102-1020K0-001A').status, DiffStatus.same);
      expect(row('K1103-0104K0-001A').status, DiffStatus.same);
    });
    test('each kind of difference', () {
      expect(row('K1103-0220P0-001A').missingRefs, ['C21']);
      expect(row('K1102-1049K9-001A').extraRefs, ['R32']);
      expect(row('K1104-2R2M00-001A').differences.map((f) => f.key), ['quantity']);
      expect(row('K1103-0106K0-001A').differences.map((f) => f.key), ['description']);
      expect(row('K1109-MOS340-001A').differences.map((f) => f.key), ['col:maker']);
      expect(row('K1402-LABEL0-001A').status, DiffStatus.onlySingle);
      expect(row('K1102-1000R0-009A').status, DiffStatus.onlyMerged);
    });
    test('a headerless column is paired with the single BOM column by content', () {
      expect(r.compared.values, ['品牌']);
      expect(r.mergedOnlyColumns, isEmpty);
    });
    test('quantities add up and designators join across A and B', () {
      final single = bom([
        ['料号', '描述', '用量', '位号'],
        ['K1', '电阻 10K', '4', 'R1,R2,R3,R4'],
        ['K2', '电容 1uF', '1', 'C1'],
      ]);
      final a = bom([
        ['料号', '描述', '用量', '位号'],
        ['K1', '电阻 10K', '2', 'R1,R2'],
        ['K2', '电容 1uF', '1', 'C1'],
      ]);
      final b = bom([
        ['料号', '描述', '用量', '位号'],
        ['K1', '电阻器 10K', '2', 'R3,R4'],
        ['K9', '电容 1uF', '1', 'C9'],
      ]);
      final rep = compareBoms(single, a, b);
      final k1 = rep.rows.firstWhere((x) => x.partNo == 'K1');
      expect(k1.status, DiffStatus.same);
      expect(k1.sources, ['A', 'B']);
      expect(k1.merged!.quantity, 4);
      expect(rep.rows.firstWhere((x) => x.partNo == 'K9').status, DiffStatus.onlyMerged);
    });
  });

  group('report and AI', () {
    test('Excel report: both sides, differing cells filled', () {
      final r = compareBoms(demo('demo_single_BOM.xlsx'), demo('demo_A_BOM.xlsx', id: 'A'), demo('demo_B_BOM.xlsx', id: 'B'));
      final ai = AiResult(
        summary: 's',
        findings: [AiFinding(partNo: 'K1103-0106K0-001A', field: 'description', side: 'both', severity: AiSeverity.error, message: '电压不同')],
        model: 'm',
        at: DateTime(2026),
      );
      final t = Strings('zh').t;
      final book = buildCompareWorkbook(r, t, ai: ai, singleName: 's.xlsx', aName: 'a.xlsx', bName: 'b.xlsx');
      final sheet = book.sheets.first;
      expect(sheet.name, t('rep_sheet'));
      final header = [for (var i = 0; i < sheet.rowCount; i++) i].firstWhere((i) => sheet.value(i, 0) == '#');
      expect(sheet.styleAt(header, 0)!.fill, 'E5E7EB');
      expect(sheet.styleAt(header, 0)!.bold, isTrue);
      final rows = [for (var i = header + 1; i < sheet.rowCount; i++) i];
      expect(rows.map((i) => sheet.value(i, 1)), [for (final x in r.rows) x.partNo]);
      final diff = rows.firstWhere((i) => sheet.value(i, 1) == 'K1103-0106K0-001A');
      expect(sheet.styleAt(diff, 4)!.fill, 'FFE3A3');
      expect(sheet.styleAt(diff, 2)!.fill, 'FDE2E1');
      var last = 0;
      while (sheet.value(header, last + 1) != null) {
        last++;
      }
      expect(sheet.value(diff, last), '电压不同');
      expect(sheet.styleAt(diff, last)!.fill, 'E4D7FB');
      expect(book.sheets.map((x) => x.name), contains(t('rep_ai_sheet')));
      // Every row cites its source records.
      final srcCol = [for (var c = 0; c <= last; c++) c].firstWhere((c) => sheet.value(header, c) == t('rep_src_single'));
      expect(sheet.value(diff, srcCol), startsWith('S:BOM!'));
      expect(sheet.value(diff, srcCol + 1), startsWith('A:A-BOM!'));
      // The file reads back with the same values.
      final grids = readTableBytes(book.encode(), 'r.xlsx');
      expect(grids.map((g) => g.name), [t('rep_sheet'), t('rep_ai_sheet')]);
      expect(grids.first.cell(diff, 1), 'K1103-0106K0-001A');
      expect(grids.first.cell(diff, 0), '${rows.indexOf(diff) + 1}');
      expect(grids.first.cell(header, srcCol), t('rep_src_single'));
    });
    test('xlsx writer: escaping, control characters, styles in the file', () {
      final w = XlsxWriter();
      final s = w.addSheet('A/B:C*?[x]');
      s.appendRow(['<a & "b">', 'line\nbreak\u0001', 3, 2.5, null, '']);
      s.style(0, 0, const XlsxStyle(bold: true, fill: 'FFE3A3'));
      final bytes = w.encode();
      final g = readTableBytes(bytes, 'w.xlsx').single;
      expect(g.name, 'A B C   x');
      expect(g.rows.first.take(4), ['<a & "b">', 'line\nbreak', '3', '2.5']);
      final zip = ZipDecoder().decodeBytes(bytes);
      final styles = utf8.decode(zip.findFile('xl/styles.xml')!.content);
      expect(styles, contains('FFFFE3A3'));
      expect(utf8.decode(zip.findFile('xl/worksheets/sheet1.xml')!.content), contains('<c r="A1" s="1" t="inlineStr">'));
    });
    test('AI reply: the JSON is found inside other text', () {
      final j = extractJson('Here you go:\n```json\n{"summary":"ok","findings":[{"partNo":"K1","severity":"error","message":"x"}]}\n```');
      expect(j['summary'], 'ok');
      final f = AiFinding.fromJson((j['findings'] as List).first as Map<String, dynamic>);
      expect(f.severity, AiSeverity.error);
      expect(() => extractJson('no json here'), throwsA(isA<AiException>()));
    });
    test('AI request carries the comparison', () {
      final r = compareBoms(demo('demo_single_BOM.xlsx'), demo('demo_A_BOM.xlsx'), null);
      final text = comparisonJson(r);
      expect(text, contains('K1103-0106K0-001A'));
      expect(text, contains('localResult'));
    });
    test('AI settings round-trip and readiness', () {
      final s = AppSettings.fromJson(AppSettings(aiEnabled: true, ai: AiConfig(provider: AiProvider.anthropic, apiKey: 'k')).toJson());
      expect(s.aiEnabled, isTrue);
      expect(s.ai.provider, AiProvider.anthropic);
      expect(s.ai.url, AiConfig.anthropicUrl);
      expect(s.ai.modelName, AiConfig.anthropicModel);
      expect(AiConfig().ready, isFalse);
      expect(AiConfig(baseUrl: 'http://localhost:11434/v1/').url, 'http://localhost:11434/v1');
    });
  });

  group('strings', () {
    test('every string has zh, en and th text', () {
      for (final k in Texts.keys) {
        for (final lang in supportedLanguages) {
          expect(Strings(lang).t(k), isNot(isEmpty), reason: '$k/$lang');
        }
      }
    });
    test('every code shown to the user is translated', () {
      final codes = [
        for (final d in DiffStatus.values) ...['status_${d.name}'],
        'why_onlySingle', 'why_onlyMerged',
        for (final s in AiSeverity.values) 'ai_sev_${s.name}',
        for (final r in BomRole.values)
          if (r != BomRole.serial) 'role_${r.name}',
        'w_qty_refs', 'w_dup_ref', 'w_no_part_no',
        'err_bom_empty', 'err_bom_no_parts', 'err_xls_unsupported', 'err_read_failed', 'err_empty',
        for (final c in ['not_configured', 'http', 'timeout', 'bad_reply', 'network']) 'err_ai_$c',
        for (final c in ['network', 'no_release', 'no_asset', 'download', 'install', 'signature']) 'upd_err_$c',
        for (final k in ['quick', 'files', 'rules', 'ai', 'export', 'keys', 'faq']) ...['guide_${k}_title', 'guide_${k}_body'],
      ];
      for (final c in codes) {
        expect(Texts.has(c), isTrue, reason: c);
      }
    });
  });

  group('updates', () {
    test('appVersion matches pubspec.yaml', () {
      final v = RegExp(r'^version:\s*([0-9.]+)', multiLine: true).firstMatch(File('pubspec.yaml').readAsStringSync())!.group(1);
      expect(appVersion, v);
    });
    test('version comparison', () {
      expect(compareVersions('1.2.0', '1.1.9'), greaterThan(0));
      expect(compareVersions('1.10.0', '1.9.0'), greaterThan(0));
      expect(compareVersions('1.2', '1.2.0'), 0);
      expect(compareVersions('1.2.0', '1.2.1'), lessThan(0));
    });
    test('asset selection per platform', () {
      final r = ReleaseInfo.fromJson({
        'tag_name': 'v1.3.0',
        'assets': [
          for (final n in [
            'SMT-FAI-1.3.0-windows-x64.zip', 'SMT-FAI-1.3.0-windows-arm64.zip', 'SMT-FAI-1.3.0-windows-x64-setup.exe',
            'SMT-FAI-1.3.0-linux-x64.tar.gz',
            'SMT-FAI-1.3.0-linux-arm64.tar.gz', 'SMT-FAI-1.3.0-android-arm64-v8a.apk', 'SMT-FAI-1.3.0-android-universal.apk',
          ])
            {'name': n, 'browser_download_url': 'https://x/$n', 'size': 1},
        ],
      });
      expect(r.version, '1.3.0');
      expect(pickAsset(r, Abi.windowsArm64)!.name, endsWith('windows-arm64.zip'));
      // Installed with the setup program: update with the new setup, or the
      // zip when that architecture has no setup.
      expect(pickAsset(r, Abi.windowsX64, installer: true)!.name, endsWith('windows-x64-setup.exe'));
      expect(pickAsset(r, Abi.windowsX64)!.name, endsWith('windows-x64.zip'));
      expect(pickAsset(r, Abi.windowsArm64, installer: true)!.name, endsWith('windows-arm64.zip'));
      expect(pickAsset(r, Abi.linuxX64)!.name, endsWith('linux-x64.tar.gz'));
      expect(pickAsset(r, Abi.androidArm64)!.name, endsWith('arm64-v8a.apk'));
      expect(pickAsset(r, Abi.androidArm)!.name, endsWith('universal.apk'));
      expect(pickAsset(r, Abi.macosArm64), isNull);
    });
  });

}
