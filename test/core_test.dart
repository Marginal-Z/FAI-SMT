import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/checker.dart';
import 'package:smt_fai/core/discrepancies.dart';
import 'package:smt_fai/core/footprints.dart';
import 'package:smt_fai/core/updater.dart';
import 'package:smt_fai/version.dart';
import 'package:smt_fai/core/exporters.dart';
import 'package:smt_fai/core/models.dart';
import 'package:smt_fai/core/parsers.dart';
import 'package:smt_fai/core/refdes.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/core/table_reader.dart';
import 'package:smt_fai/l10n/strings.dart';

Grid g(List<List<String>> rows) => Grid('s', rows);

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

  group('parsers', () {
    test('BOM header detection, continuation rows, merging', () {
      final items = parseBom([
        g([
          ['T100 BOM export'],
          ['主件料件编号', '料件编号', '品名', '规格', '组成用量', '插件位置'],
          ['MAIN', 'K1101-1', '贴片IC', 'C302XS', '1', 'U5'],
          ['MAIN', 'K1101-2', '贴片电阻', '10K', '4', 'R1,R2'],
          ['', '', '', '', '', 'R3,R4'],
          ['MAIN', 'K1101-1', '', '', '1', 'U6'],
        ])
      ]).items;
      expect(items.length, 2);
      expect(items[0].partNo, 'K1101-1');
      expect(items[0].refs, ['U5', 'U6']);
      expect(items[0].qty, 2);
      expect(items[1].refs, ['R1', 'R2', 'R3', 'R4']);
    });

    test('Altium style coordinates with units in header', () {
      final p = parseCoordinates([
        g([
          ['Designator', 'Comment', 'Layer', 'Footprint', 'Center-X(mil)', 'Center-Y(mil)', 'Rotation'],
          ['R1', '10K', 'TopLayer', '0402', '1000', '2000', '90'],
          ['U5', 'C302', 'BottomLayer', 'BGA', '500', '500', '270'],
        ])
      ]).items;
      expect(p.length, 2);
      expect(p[0].x, closeTo(25.4, 1e-9));
      expect(p[0].side, BoardSide.top);
      expect(p[1].side, BoardSide.bottom);
      expect(p[1].rotation, 270);
    });

    test('headerless coordinates', () {
      final grid = parseDelimited('R1 10.0 20.0 90 T\nC1 1 2 0 B\n');
      final p = parseCoordinates([g(grid)]).items;
      expect(p.map((e) => e.ref), ['R1', 'C1']);
      expect(p[1].side, BoardSide.bottom);
    });
  });

  group('checker', () {
    final bom = [
      BomItem(partNo: 'P-IC', name: '贴片IC', qty: 1, refs: ['U5']),
      BomItem(partNo: 'P-DDR', name: 'DDR3L', qty: 2, refs: ['3U2', '3U3']),
      BomItem(partNo: 'P-R', name: '电阻', qty: 3, refs: ['R1', 'R2', 'R3'], alternates: ['P-R-ALT']),
      BomItem(partNo: 'P-C', name: '电容', qty: 2, refs: ['C1', 'C2']),
      BomItem(partNo: 'P-PCB', name: 'PCB 光板', qty: 1),
      BomItem(partNo: 'P-DIP', name: '插件电解电容', qty: 1, refs: ['EC1']),
    ];
    final stations = [
      StationItem(partNo: 'P-IC', side: StationSide.a, slot: '1', refs: ['U5']),
      StationItem(partNo: 'P-DDR', side: StationSide.a, slot: '2', refs: ['3U2']),
      StationItem(partNo: 'P-DDR', side: StationSide.b, slot: '3', refs: ['3U3']),
      StationItem(partNo: 'P-R', side: StationSide.a, slot: '4', refs: ['R1', 'R2']),
      StationItem(partNo: 'P-R-ALT', side: StationSide.a, slot: '5', refs: ['R3']),
      StationItem(partNo: 'P-C', side: StationSide.b, slot: '6', refs: ['C1', 'C9']),
      StationItem(partNo: 'P-X', side: StationSide.b, slot: '7', refs: ['L1']),
    ];
    final report = runCheck(bom, stations, CheckRules());
    CheckRow row(String pn) => report.rows.firstWhere((r) => r.partNo == pn);

    test('categories are disjoint and sum to the total', () {
      final sum = CheckCategory.values.map(report.count).reduce((a, b) => a + b);
      expect(sum, report.rows.length);
    });
    test('pass across sides A and B', () {
      expect(row('P-IC').category, CheckCategory.pass);
      expect(row('P-DDR').category, CheckCategory.pass);
      expect(row('P-DDR').sides, {StationSide.a, StationSide.b});
    });
    test('alternate coverage goes to the substitute area', () {
      final r = row('P-R');
      expect(r.category, CheckCategory.substitute);
      expect(r.smtPartNos, ['P-R', 'P-R-ALT']);
      expect(r.bomRefs.firstWhere((m) => m.ref == 'R3').state, RefState.alternate);
      expect(report.rows.where((x) => x.partNo == 'P-R-ALT'), isEmpty);
    });
    test('missing and extra designators are NG with reasons', () {
      final r = row('P-C');
      expect(r.category, CheckCategory.ng);
      expect(r.reasons.map((e) => e.code), containsAll(['station_missing_refs', 'station_extra_refs']));
      expect(r.reasons.firstWhere((e) => e.code == 'station_missing_refs').args['refs'], 'C2');
    });
    test('exclusions', () {
      expect(row('P-PCB').category, CheckCategory.excluded);
      expect(row('P-DIP').category, CheckCategory.excluded);
      expect(row('P-DIP').reasons.single.code, 'excl_keyword');
    });
    test('station part not in BOM', () {
      final r = row('P-X');
      expect(r.category, CheckCategory.ng);
      expect(r.reasons.first.code, 'not_in_bom');
    });
    test('qty mismatch', () {
      final rep = runCheck([BomItem(partNo: 'A', name: 'x', qty: 3, refs: ['R1', 'R2'])],
          [StationItem(partNo: 'A', side: StationSide.a, refs: ['R1', 'R2'])], CheckRules());
      expect(rep.rows.single.category, CheckCategory.ng);
      expect(rep.rows.single.reasons.single.code, 'qty_mismatch');
    });

    test('CAD file joins coordinates with merged list', () {
      final placements = [
        Placement(ref: 'U5', x: 10, y: 20, rotation: 90),
        Placement(ref: '3U3', x: 1.23456, y: 2, rotation: -90),
        Placement(ref: 'MARK1', x: 0, y: 0),
        Placement(ref: 'TP1', x: 5, y: 5),
      ];
      final cad = buildCad(placements, report, CadTemplate(), CheckRules());
      expect(cad.header, ['Location', 'X', 'Y', 'Angle', 'Specification', 'PartNo', 'Layer', 'Qty']);
      expect(cad.cells.length, 2);
      expect(cad.cells[0], ['3U3', closeTo(1.23456, 1e-9), 2.0, 270, 'DDR3L', 'P-DDR', 'BOTTOM', 1]);
      expect(cad.cells[1][0], 'U5');
      expect(cad.cells[1][6], 'TOP');
      final grid = readTableBytes(cad.encode(), 'cad.xlsx').single;
      expect(grid.rows[0], ['Location', 'X', 'Y', 'Angle', 'Specification', 'PartNo', 'Layer', 'Qty']);
      expect(grid.rows[1], ['3U3', '1.235', '2', '270', 'DDR3L', 'P-DDR', 'BOTTOM', '1']);
      final text = buildCad(placements, report, CadTemplate(format: CadFormat.text, delimiter: ','), CheckRules()).text;
      expect(text.split('\r\n')[1], '3U3,1.235,2.000,270,DDR3L,P-DDR,BOTTOM,1');
      expect(cad.notInBomRefs, ['TP1']);
      expect(cad.noCoordRefs, contains('R1'));
    });
  });

  group('exports and strings', () {
    test('check workbook round-trips through the reader', () {
      final report = runCheck(
          [BomItem(partNo: 'A', name: 'x', qty: 1, refs: ['R1'])],
          [StationItem(partNo: 'A', side: StationSide.a, refs: ['R1'])],
          CheckRules());
      final bytes = exportCheckWorkbook(
          report,
          ExportLabels(
            sheetCheck: 'Check',
            sheetMerged: 'Merged',
            checkHeaders: List.generate(12, (i) => 'h$i'),
            mergedHeaders: List.generate(7, (i) => 'm$i'),
            category: (c) => c.name,
            reason: (r) => r.code,
            side: (s) => s?.name ?? '',
          ));
      final grids = readTableBytes(bytes, 'x.xlsx');
      final check = grids.firstWhere((g) => g.name == 'Check');
      expect(check.rows[1][1], 'A');
      expect(check.rows[1][10], 'pass');
      final merged = grids.firstWhere((g) => g.name == 'Merged');
      expect(merged.rows[1][0], 'R1');
    });

    test('every string has zh, en and th text', () {
      for (final k in Texts.keys) {
        for (final lang in supportedLanguages) {
          expect(Strings(lang).t(k), isNot(isEmpty), reason: '$k/$lang');
        }
      }
    });

    test('every reason and parse code is translated', () {
      const codes = [
        'not_on_station', 'station_missing_refs', 'station_extra_refs', 'bom_no_refs', 'bom_dup_refs',
        'bom_ref_conflict', 'station_ref_conflict', 'ref_both_sides', 'qty_mismatch', 'alt_used',
        'not_in_bom', 'alt_outside_main', 'ref_belongs_to', 'excl_keyword', 'excl_prefix', 'excl_no_refs',
        'parse_bad_qty', 'parse_bad_xy', 'parse_dup_ref', 'err_xls_unsupported', 'err_read_failed', 'err_empty',
        'err_parse_no_header_bom', 'err_parse_no_header_station', 'err_parse_no_header_coord',
      ];
      for (final c in codes) {
        expect(Texts.has(c), isTrue, reason: c);
      }
    });
  });

  group('real export quirks', () {
    test('soft-wrapped designator cells from T100', () {
      expect(splitRefs('8R20,8R\n23,1\nC39'), ['8R20', '8R23', '1C39']);
      expect(splitRefs('2R1 3R6\n10R2'), ['2R1', '3R6', '10R2']);
    });
    test('station alternates listed under the main row', () {
      final st = parseStation([
        g([
          ['站位', '料号', '关联料号', '物料描述', '数量', '位号'],
          ['11-B- 2', 'P-DDR', 'P-DDR', 'DDR', '1', '3U2'],
          ['', 'P-DDR-ALT', 'P-DDR-ALT', 'DDR alt', '', ''],
        ])
      ], StationSide.a).items;
      expect(st.single.slot, '11-B-2');
      expect(st.single.alternates, ['P-DDR-ALT']);
      final rep = runCheck([BomItem(partNo: 'P-DDR', name: 'DDR', qty: 1, refs: ['3U2'])], st, CheckRules());
      expect(rep.rows.single.category, CheckCategory.substitute);
      expect(rep.rows.single.reasons.single.code, 'alt_listed');
    });
    test('blank part placed as programmed part', () {
      final rep = runCheck([
        BomItem(partNo: 'FW', name: 'PRG F/W 烧录后', qty: 1, refs: ['4U1']),
        BomItem(partNo: 'EMMC', name: '贴片IC EMMC', qty: 1, refs: ['4U1']),
      ], [StationItem(partNo: 'FW', side: StationSide.a, refs: ['4U1'])], CheckRules());
      expect(rep.rows.firstWhere((r) => r.partNo == 'FW').category, CheckCategory.pass);
      final emmc = rep.rows.firstWhere((r) => r.partNo == 'EMMC');
      expect(emmc.category, CheckCategory.excluded);
      expect(emmc.reasons.single.code, 'excl_programmed');
    });
    test('coordinate headers with /mm units and Orientation', () {
      final p = parseCoordinates([
        g([
          ['Name', 'Part Type', 'X/mm', 'Y/mm', 'Orientation', 'SMD', 'Layer'],
          ['1C1', 'CAPNP_2', '119.946', '149.195', '90', 'Yes', 'TOP'],
        ])
      ]).items.single;
      expect(p.x, 119.946);
      expect(p.rotation, 90);
      expect(p.side, BoardSide.top);
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
            'SMT-FAI-1.3.0-windows-x64.zip', 'SMT-FAI-1.3.0-windows-arm64.zip', 'SMT-FAI-1.3.0-linux-x64.tar.gz',
            'SMT-FAI-1.3.0-linux-arm64.tar.gz', 'SMT-FAI-1.3.0-android-arm64-v8a.apk', 'SMT-FAI-1.3.0-android-universal.apk',
          ])
            {'name': n, 'browser_download_url': 'https://x/$n', 'size': 1},
        ],
      });
      expect(r.version, '1.3.0');
      expect(pickAsset(r, Abi.windowsArm64)!.name, endsWith('windows-arm64.zip'));
      expect(pickAsset(r, Abi.linuxX64)!.name, endsWith('linux-x64.tar.gz'));
      expect(pickAsset(r, Abi.androidArm64)!.name, endsWith('arm64-v8a.apk'));
      expect(pickAsset(r, Abi.androidArm)!.name, endsWith('universal.apk'));
      expect(pickAsset(r, Abi.macosArm64), isNull);
    });
  });

  group('assembly drawing shapes', () {
    test('designator prefixes and package sizes', () {
      expect(shapeOf('15R3', description: '贴片电阻 RT0201 22R').kind, PartKind.resistor);
      expect(shapeOf('15R3', description: '贴片电阻 RT0201 22R').width, 0.6);
      expect(shapeOf('1C4', description: '贴片电容 CC0603 22UF').width, 1.6);
      expect(shapeOf('1L2', description: '贴片工字电感 一体252012').kind, PartKind.inductor);
      expect(shapeOf('Y1', description: '贴片晶振 SMD3225').width, 3.2);
      expect(shapeOf('U5', footprint: 'AML_C3_C308L_BGA_PACKAGE_1').bga, isTrue);
      expect(shapeOf('8U1', description: 'MSOP_8').pins, 4);
      expect(shapeOf('1Q2', footprint: 'SOT23').kind, PartKind.transistor);
      expect(shapeOf('MARK1').kind, PartKind.fiducial);
      expect(shapeOf('TP10_1').kind, PartKind.testPoint);
    });
  });

  group('discrepancies', () {
    test('description, coordinates and side are cross-checked', () {
      final bom = [
        BomItem(partNo: 'A', name: '贴片电感', spec: 'UR0420', qty: 2, refs: ['L1', 'L2']),
      ];
      final st = [StationItem(partNo: 'A', side: StationSide.a, slot: '9-17', desc: '贴片电感 4040', refs: ['L1', 'L2'])];
      final rep = runCheck(bom, st, CheckRules());
      final ds = findDiscrepancies(
        bom: bom,
        stations: st,
        report: rep,
        rules: CheckRules(),
        placements: [
          Placement(ref: 'L1', x: 0, y: 0, side: BoardSide.bottom),
          Placement(ref: 'NC9', x: 1, y: 1),
        ],
      );
      final codes = ds.map((d) => d.code).toList();
      expect(codes, containsAll(['d_desc_mismatch', 'd_coord_missing', 'd_side_mismatch', 'd_coord_extra']));
      expect(ds.firstWhere((d) => d.code == 'd_coord_missing').subject, 'L2');
      expect(ds.first.severity, Severity.error);
      for (final d in ds) {
        expect(Texts.has(d.code), isTrue, reason: d.code);
        expect(Texts.has('why_${d.code}'), isTrue, reason: 'why_${d.code}');
      }
    });

    test('every check reason has an explanation', () {
      for (final code in [
        'not_on_station', 'station_missing_refs', 'station_extra_refs', 'bom_no_refs', 'bom_dup_refs', 'bom_ref_conflict',
        'station_ref_conflict', 'ref_both_sides', 'qty_mismatch', 'alt_used', 'alt_listed', 'not_in_bom', 'alt_outside_main',
        'ref_belongs_to', 'excl_keyword', 'excl_prefix', 'excl_no_refs', 'excl_parent', 'excl_programmed',
        'd_parse_bad_qty', 'd_parse_bad_xy', 'd_parse_dup_ref', 'd_parse_station_qty', 'd_station_dup',
      ]) {
        expect(Texts.has('why_$code'), isTrue, reason: code);
      }
    });
  });

  group('1.2.1', () {
    test('part-level findings make the row NG with a reason', () {
      final bom = [BomItem(partNo: 'A', name: '贴片电感 UR0420', qty: 2, refs: ['L1', 'L2'])];
      final st = [StationItem(partNo: 'A', side: StationSide.a, slot: '9-17', desc: '贴片电感 4040', refs: ['L1', 'L2'])];
      final raw = runCheck(bom, st, CheckRules());
      expect(raw.rows.single.category, CheckCategory.pass);
      final found = findDiscrepancies(
        bom: bom,
        stations: st,
        report: raw,
        rules: CheckRules(),
        placements: [Placement(ref: 'L1', x: 0, y: 0, side: BoardSide.top)],
      );
      final folded = foldIntoReport(raw, found);
      final row = folded.rows.single;
      expect(row.category, CheckCategory.ng);
      expect(row.reasons.map((r) => r.code), containsAll(['d_desc_mismatch', 'row_coord_missing']));
      expect(folded.merged.every((m) => m.category == CheckCategory.ng), isTrue);
      // The list does not repeat folded reasons as BOM↔station findings.
      final again = findDiscrepancies(bom: bom, stations: st, report: folded, rules: CheckRules());
      expect(again.where((d) => d.code.startsWith('row_')), isEmpty);
    });

    test('CAD output keeps every placed part, SMD flag or not', () {
      final rep = runCheck([BomItem(partNo: 'ST', name: '贴片螺柱', qty: 1, refs: ['J4'])],
          [StationItem(partNo: 'ST', side: StationSide.a, refs: ['J4'])], CheckRules());
      final cad = buildCad([Placement(ref: 'J4', x: 2, y: 2, smd: false)], rep, CadTemplate(), CheckRules());
      expect(cad.cells.map((r) => r.first), ['J4']);
    });
  });
}
