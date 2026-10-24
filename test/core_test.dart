import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/app_state.dart';
import 'package:smt_fai/core/board_layout.dart';
import 'package:smt_fai/core/checker.dart';
import 'package:smt_fai/core/discrepancies.dart';
import 'package:smt_fai/core/footprints.dart';
import 'package:smt_fai/core/package_parser.dart';
import 'package:smt_fai/core/part_library.dart';
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

    test('confirmations go to the report and survive a re-check', () {
      final state = AppState(AppSettings(), Directory.systemTemp.path);
      final report = runCheck(
          [BomItem(partNo: 'A', name: 'x', qty: 1, refs: ['R1'])],
          [StationItem(partNo: 'A', side: StationSide.a, refs: ['R1'])],
          CheckRules());
      state.report = report;
      state.setConfirmed(report.rows, true);
      state.setConfirmNote(report.rows.first, 'ok by QA');
      expect(state.confirmedCount(CheckCategory.pass), 1);
      // Same content in a new report keeps the sign-off.
      final again = runCheck(
          [BomItem(partNo: 'A', name: 'x', qty: 1, refs: ['R1'])],
          [StationItem(partNo: 'A', side: StationSide.a, refs: ['R1'])],
          CheckRules());
      state.report = again;
      expect(state.confirmationOf(again.rows.first)?.note, 'ok by QA');
      final bytes = exportCheckWorkbook(
          again,
          ExportLabels(
            sheetCheck: 'Check',
            sheetMerged: 'Merged',
            checkHeaders: List.generate(14, (i) => 'h$i'),
            mergedHeaders: List.generate(7, (i) => 'm$i'),
            category: (c) => c.name,
            reason: (r) => r.code,
            side: (s) => s?.name ?? '',
          ),
          confirmations: state.confirmations);
      final check = readTableBytes(bytes, 'x.xlsx').firstWhere((g) => g.name == 'Check');
      expect(check.rows[1][12], isNotEmpty);
      expect(check.rows[1][13], 'ok by QA');
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

  group('assembly drawing shapes', () {
    test('designator prefixes and package sizes', () {
      expect(shapeOf('15R3', description: '贴片电阻 RT0201 22R').kind, PartKind.resistor);
      expect(shapeOf('15R3', description: '贴片电阻 RT0201 22R').width, 0.6);
      expect(shapeOf('1C4', description: '贴片电容 CC0603 22UF').width, 1.6);
      expect(shapeOf('1L2', description: '贴片工字电感 一体252012').kind, PartKind.inductor);
      expect(shapeOf('Y1', description: '贴片晶振 SMD3225').width, 3.2);
      // Power inductor codes are square: 4020 = 4.0 x 4.0 mm.
      final l = shapeOf('L3', description: '一体成型电感 4020 2.2uH');
      expect((l.width, l.height), (4.0, 4.0));
      // Connector length from pins and pitch, not a fixed 0.8 mm per pin.
      final btb = shapeOf('J1', description: 'BTB 板对板连接器 40PIN 0.4MM');
      expect(btb.width, closeTo(19 * 0.4 + 1.8, 1e-9));
      expect(shapeOf('J2', description: 'FPC 翻盖 24PIN 0.5MM').width, closeTo(23 * 0.5 + 3.6, 1e-9));
      expect(shapeOf('U5', footprint: 'AML_C3_C308L_BGA_PACKAGE_1').bga, isTrue);
      expect(shapeOf('8U1', description: 'MSOP_8').pins, 8);
      expect(shapeOf('1Q2', footprint: 'SOT23').kind, PartKind.transistor);
      expect(shapeOf('MARK1').kind, PartKind.fiducial);
      expect(shapeOf('TP10_1').kind, PartKind.testPoint);
    });
  });

  group('part library', () {
    test('recognises common component families', () {
      String m(String ref, {String fp = '', String d = ''}) => shapeOf(ref, footprint: fp, description: d).model;
      expect(m('R5', d: '贴片电阻 RT0402 10K'), 'chip_resistor');
      expect(m('RN1', d: '排阻 0402X4 22R'), 'res_array');
      expect(m('C3', d: '贴片电容 CC0603 22UF'), 'mlcc');
      expect(m('EC1', d: '贴片铝电解 220UF 16V 6.3X5.4'), 'elcap');
      expect(m('C9', d: '钽电容 TAJ 3528 10UF'), 'tantalum');
      expect(m('FB2', d: '磁珠 0402 600R'), 'bead');
      expect(m('L1', d: '绕线工字电感 CD54 10UH'), 'drum_inductor');
      expect(m('D4', fp: 'SMA'), 'diode_sma');
      expect(m('LED1', d: 'LED 5050 RGB'), 'led_plcc');
      expect(m('Q1', fp: 'SOT-223'), 'sot223');
      expect(m('U2', fp: 'LQFP48_7X7'), 'qfp');
      expect(m('U3', fp: 'QFN24_4X4'), 'qfn');
      expect(m('U5', fp: 'AML_C3_C308L_BGA_PACKAGE_1'), 'bga');
      expect(m('Y1', d: '有源晶振 25MHZ 3225'), 'oscillator');
      expect(m('J1', d: 'USB TYPE-C 16P'), 'usb_c');
      expect(m('J2', fp: 'FPC-CON24'), 'fpc');
      expect(m('SW1', d: '轻触按键 6X6'), 'tact_switch');
      expect(m('BZ1', d: '蜂鸣器'), 'buzzer');
      expect(m('9R2', d: '291A主板BOT屏蔽框材料'), 'shield');
      expect(m('MARK1'), 'fiducial');
      expect(m('TP3'), 'test_point');
    });

    test('a user rule overrides recognition, most specific first', () {
      final rules = [const PartModelRule('footprint', 'SOT23', 'sot23_6'), const PartModelRule('ref', 'Q7', 'dpak')];
      expect(ruleModel(rules, ref: 'Q1', partNo: 'X', footprint: 'SOT23'), 'sot23_6');
      expect(ruleModel(rules, ref: 'Q7', partNo: 'X', footprint: 'SOT23'), 'dpak');
      expect(ruleModel(rules, ref: 'Q2', partNo: 'X', footprint: 'SOT89'), isNull);
      final forced = shapeOf('Q7', footprint: 'SOT23', model: 'dpak');
      expect(forced.model, 'dpak');
      expect(forced.width, greaterThan(2.9));
    });

    test('every library model has a name and a positive size', () {
      for (final m in partLibrary) {
        expect(Texts.has('pm_${m.id}'), isTrue, reason: m.id);
        expect(m.width > 0 && m.height > 0, isTrue, reason: m.id);
      }
    });
  });

  group('package recognition', () {
    test('pins, rows, pitch and body from EDA names and BOM text', () {
      PackageInfo p(String fp, [String d = '']) => parsePackage(fp, d);
      final soic = p('SOIC-8_3.9x4.9mm_P1.27mm');
      expect((soic.family, soic.pins, soic.pitch, soic.length, soic.width), ('SOIC', 8, 1.27, 4.9, 3.9));
      final qfn = p('QFN-32-1EP_5x5mm_P0.5mm');
      expect((qfn.family, qfn.pins, qfn.length), ('QFN', 32, 5.0));
      expect(p('SOT-23-5').pins, 5);
      expect(p('SOT-23').pins, 3);
      expect(p('', 'LDO稳压IC SOT-23-6').pins, 6);
      expect(p('TSSOP20').pins, 20);
      expect(p('LQFP-64').family, 'QFP');
      final header = p('PinHeader_2x05_P2.54mm_Vertical');
      expect((header.rows, header.pins, header.pitch), (2, 10, 2.54));
      final jst = p('JST_SH_SM04B-SRSS-TB_1x04-1MP_P1.00mm_Horizontal');
      expect((jst.pins, jst.pitch), (4, 1.0));
      final fpc = p('', '连接器 FPC 0.5MM 24P 翻盖下接');
      expect((fpc.pins, fpc.pitch), (24, 0.5));
      final btb = p('', '板对板连接器 40PIN 0.4mm 母座');
      expect((btb.pins, btb.pitch), (40, 0.4));
      expect(p('', '排针 2*20PIN 2.54MM').pins, 40);
      expect(p('', 'PH2.0 4P 立贴').pitch, 2.0);
      // A 10P capacitor value is not a pin count for packages with a family.
      expect(p('QFN24_4X4').length, 4.0);
    });

    test('shapes follow the recognised package for any product', () {
      final sop16 = shapeOf('U9', footprint: 'SOIC-16_3.9x9.9mm_P1.27mm');
      expect((sop16.width, sop16.height, sop16.pins), (9.9, 3.9, 16));
      final tssop = shapeOf('U2', description: '运放 TSSOP-14');
      expect(tssop.pins, 14);
      expect(tssop.height, 4.4);
      final qfp = shapeOf('U1', description: 'MCU LQFP-100');
      expect((qfp.width, qfp.pins), (14.0, 100));
      final sot5 = shapeOf('U4', footprint: 'SOT-23-5');
      expect((sot5.pins, sot5.model), (5, 'sot23_6'));
      final header = shapeOf('J5', footprint: 'PinHeader_2x05_P2.54mm_Vertical');
      expect((header.pins, header.rows, header.model), (10, 2, 'pin_header'));
      expect(header.width, closeTo(4 * 2.54 + 2.54, 1e-9));
      final fpc = shapeOf('J3', description: 'FPC连接器 0.5MM 30P 翻盖');
      expect((fpc.pins, fpc.model), (30, 'fpc'));
      expect(fpc.width, closeTo(29 * 0.5 + 3.6, 1e-9));
      // General rules learnt from real boards.
      expect(shapeOf('1U1', footprint: 'MP1495_1', description: '贴片IC DC-DC SOT563').model, 'sot23_6');
      expect(shapeOf('9R1', footprint: 'PBG-BGA-EMMC', description: '主板屏蔽框 洋白铜').model, 'shield');
      expect(shapeOf('2R59', footprint: 'R-PIN-MARK', description: '贴片热敏电阻 RT0402 10K').model, 'thermistor');
      final l = shapeOf('1L2', description: '贴片电感 一体252012 6.8UH');
      expect((l.width, l.height), (2.5, 2.0));
      expect(shapeOf('9U1', description: '图像传感器 OS04C10-A43A-1B 43pin CSP').pins, 43);
      expect(shapeOf('10J1', description: 'IPEX公座 射频座一代 3PIN').model, 'rf_connector');
      expect(shapeOf('J2', footprint: 'CONNEC4_125MM_DIP').pins, 4);
      // Coordinates are never part of the shape: only size and pins change.
      final plain = shapeOf('R1', description: '贴片电阻 0402 10K');
      expect((plain.width, plain.height), (1.0, 0.5));
    });
  });

  group('body fitting', () {
    test('neighbours shrink apart, centres stay, stacked alternates are left', () {
      final f = fitBodies(const [
        // Two estimated test points 0.5 mm apart (1.2 mm default bodies).
        BodyBox(x: 0, y: 0, rotation: 0, width: 1.2, height: 1.2, side: 1),
        BodyBox(x: 0.5, y: 0, rotation: 0, width: 1.2, height: 1.2, side: 1),
        // Same spot on the other side: never compared with the first two.
        BodyBox(x: 0, y: 0, rotation: 0, width: 3, height: 3, side: 2),
        // Alternate footprints sharing one spot.
        BodyBox(x: 10, y: 10, rotation: 0, width: 4, height: 4, side: 1),
        BodyBox(x: 10.1, y: 10.3, rotation: 0, width: 3, height: 2, side: 1, exact: true),
      ]);
      // The pair along X now fits: 0.6 * w0 + 0.6 * w1 <= 0.5 - gap.
      expect(0.6 * f[0].$1 + 0.6 * f[1].$1, lessThanOrEqualTo(0.5));
      // Bodies keep their proportions.
      expect(f[0].$2, f[0].$1);
      expect(f[1].$2, f[1].$1);
      expect(f[2], (1.0, 1.0));
      expect(f[3], (1.0, 1.0));
      expect(f[4], (1.0, 1.0));
    });

    test('all-sides view: the far side gives way, empty footprints never push', () {
      const top = BodyBox(x: 0, y: 0, rotation: 0, width: 2, height: 2, side: 1);
      const bottom = BodyBox(x: 1.2, y: 0, rotation: 0, width: 2, height: 2, side: 2);
      // Separate views: different sides never collide.
      expect(fitBodies(const [top, bottom]), [(1.0, 1.0), (1.0, 1.0)]);
      // All sides: only the bottom body shrinks.
      final f = fitBodies(const [top, bottom], yieldingSides: {2});
      expect(f[0], (1.0, 1.0));
      expect(f[1].$1, lessThan(1));
      // An empty top footprint does not make a placed bottom part shrink.
      const emptyTop = BodyBox(x: 0, y: 0, rotation: 0, width: 2, height: 2, side: 1, solid: false);
      expect(fitBodies(const [emptyTop, bottom], yieldingSides: {2})[1], (1.0, 1.0));
      // Same side: the empty footprint is the one that gives way.
      const placed = BodyBox(x: 1.2, y: 0, rotation: 0, width: 2, height: 2, side: 1);
      final g = fitBodies(const [emptyTop, placed]);
      expect(g[1], (1.0, 1.0));
      expect(g[0].$1, lessThan(1));
    });

    test('identical packages share one size and never overlap', () {
      // A row of 0402 parts 0.8 mm apart (1.0 mm long) and one far away.
      final row = [
        for (var i = 0; i < 6; i++) BodyBox(x: i * 0.8, y: 0, rotation: 0, width: 1.0, height: 0.5, side: 1, exact: true),
        const BodyBox(x: 30, y: 30, rotation: 0, width: 1.0, height: 0.5, side: 1, exact: true),
      ];
      final f = fitBodies(row);
      for (final e in f) {
        expect(e.$1, e.$2);
        expect(e.$1, f.first.$1);
      }
      expect(f.first.$1 * 1.0, lessThanOrEqualTo(0.8));
    });

    test('random crowded boards: no overlaps left, proportions kept', () {
      final rnd = math.Random(7);
      final bodies = [
        for (var i = 0; i < 300; i++)
          BodyBox(
            x: rnd.nextDouble() * 20,
            y: rnd.nextDouble() * 20,
            rotation: [0.0, 90.0, 45.0, 180.0][rnd.nextInt(4)],
            width: [1.0, 1.6, 2.9, 4.0][rnd.nextInt(4)],
            height: [0.5, 0.8, 1.3, 4.0][rnd.nextInt(4)],
            side: 1,
            exact: rnd.nextBool(),
          ),
      ];
      final f = fitBodies(bodies);
      List<(double, double)> corners(int i) {
        final b = bodies[i], c = math.cos(b.rotation * math.pi / 180), s = math.sin(b.rotation * math.pi / 180);
        final w = b.width * f[i].$1 / 2, h = b.height * f[i].$2 / 2;
        return [for (final (x, y) in [(-w, -h), (w, -h), (w, h), (-w, h)]) (b.x + x * c - y * s, b.y + x * s + y * c)];
      }

      bool overlap(int a, int b) {
        final ca = corners(a), cb = corners(b);
        for (final poly in [ca, cb]) {
          for (var k = 0; k < 4; k++) {
            final (x1, y1) = poly[k];
            final (x2, y2) = poly[(k + 1) % 4];
            final nx = y1 - y2, ny = x2 - x1;
            final pa = [for (final (x, y) in ca) x * nx + y * ny], pb = [for (final (x, y) in cb) x * nx + y * ny];
            if (pa.reduce(math.max) <= pb.reduce(math.min) + 1e-9 || pb.reduce(math.max) <= pa.reduce(math.min) + 1e-9) return false;
          }
        }
        return true;
      }

      var left = 0;
      for (var a = 0; a < bodies.length; a++) {
        expect(f[a].$1, f[a].$2);
        for (var b = a + 1; b < bodies.length; b++) {
          final d = math.sqrt(math.pow(bodies[a].x - bodies[b].x, 2) + math.pow(bodies[a].y - bodies[b].y, 2));
          // Alternate footprints (centres nearly on one spot) and bodies
          // already at the minimum scale may stay overlapped.
          final long = [bodies[a].width, bodies[a].height, bodies[b].width, bodies[b].height].reduce(math.max);
          double short(BodyBox e) => math.min(math.min(e.width, e.height), e.exact ? double.infinity : 0.5);
          if (d < 0.6 * math.min(short(bodies[a]), short(bodies[b])) || d < 0.12 * long) continue;
          if (f[a].$1 <= 0.2 || f[b].$1 <= 0.2) continue;
          if (overlap(a, b)) left++;
        }
      }
      expect(left, 0);
    });

    test('an estimated body gives way to a package-code body', () {
      final f = fitBodies(const [
        BodyBox(x: 0, y: 0, rotation: 0, width: 4, height: 4, side: 1),
        BodyBox(x: 2.1, y: 0, rotation: 90, width: 1.0, height: 0.5, side: 1, exact: true),
      ]);
      expect(f[1], (1.0, 1.0));
      expect(f[0].$1, lessThan(1));
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
