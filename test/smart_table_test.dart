import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/models.dart';
import 'package:smt_fai/core/parsers.dart';
import 'package:smt_fai/core/smart_table.dart';
import 'package:smt_fai/core/table_reader.dart';

Grid g(List<List<String>> rows) => Grid('s', rows);

Map<ColumnRole, String> roles(TableLayout l) => {
      for (final c in l.columns)
        if (c.role != ColumnRole.other && !(c.role == ColumnRole.desc && l.cols(ColumnRole.desc).first != c.index)) c.role: c.header,
    };

void main() {
  group('content recognition', () {
    test('BOM with header names no rule knows', () {
      final l = detectTable([
        g([
          ['导出时间 2026-10-01', '', '', '', ''],
          ['甲', '乙', '丙', '丁', '戊'],
          ['10', 'K1102-1020K0-001A', '贴片电阻 10K ±1% 0402', '3', 'R1,R2,R3'],
          ['20', 'K1103-0104K0-001A', '贴片电容 100nF 16V 0402', '2', 'C1,C2'],
          ['30', 'K1101-1C302X-001A', '主芯片 BGA128', '1', 'U5'],
          ['40', 'K1104-2R2M00-001A', '贴片电感 2.2uH 2520', '2', 'L1,L2'],
        ])
      ], TableKind.bom)!;
      expect(l.headerRow, 1);
      expect(roles(l), {ColumnRole.partNo: '乙', ColumnRole.desc: '丙', ColumnRole.qty: '丁', ColumnRole.refs: '戊'});
    });

    test('headerless BOM with shuffled columns', () {
      final l = detectTable([
        g([
          ['C1 C2 C3', '100nF 16V X7R 0402', '3', '1003-000104'],
          ['R1 R2', '10K 1% 0402', '2', '1002-000103'],
          ['U1', 'MCU QFN48', '1', '1001-000001'],
          ['D1-D4', 'ESD5V0 SOD-523', '4', '1007-000050'],
        ])
      ], TableKind.bom)!;
      expect(l.headerRow, -1);
      expect(l.col(ColumnRole.refs), 0);
      expect(l.col(ColumnRole.desc), 1);
      expect(l.col(ColumnRole.qty), 2);
      expect(l.col(ColumnRole.partNo), 3);
      final items = parseBom([], layout: l).items;
      expect(items.map((e) => e.partNo), ['1003-000104', '1002-000103', '1001-000001', '1007-000050']);
      expect(items[3].refs, ['D1', 'D2', 'D3', 'D4']);
    });

    test('parent part number, item sequence and alternates are told apart', () {
      final l = detectTable([
        g([
          ['Parent', 'Seq', 'Item', 'Name', 'Spec', 'Usage', 'Where', 'Second source'],
          ['MB-V1', '10', 'K1-0001', 'Resistor', '10K 0402', '2', 'R1,R2', ''],
          ['MB-V1', '20', 'K1-0002', 'Capacitor', '1uF 0402', '1', 'C1', 'K1-0902'],
          ['MB-V1', '30', 'K1-0003', 'IC', 'LDO SOT23-5', '1', 'U1', ''],
          ['MB-V1', '40', 'K1-0004', 'LED', 'Green 0603', '2', 'LED1,LED2', ''],
        ])
      ], TableKind.bom)!;
      expect(l.headerOf(l.col(ColumnRole.partNo)!), 'Item');
      expect(l.headerOf(l.col(ColumnRole.qty)!), 'Usage');
      expect(l.headerOf(l.col(ColumnRole.refs)!), 'Where');
      expect(l.headerOf(l.col(ColumnRole.alt)!), 'Second source');
      expect(l.cols(ColumnRole.desc).map(l.headerOf), ['Name', 'Spec']);
    });

    test('station list with a side column', () {
      final l = detectTable([
        g([
          ['F', 'Material', 'Text', 'N', 'Points', 'Face'],
          ['1-01', 'K1-0001', '10K 0402', '2', 'R1 R2', 'TOP'],
          ['1-02', 'K1-0002', '1uF 0402', '1', 'C1', 'TOP'],
          ['2-01', 'K1-0003', 'LDO SOT23-5', '1', 'U1', 'BOT'],
          ['2-02', 'K1-0004', 'LED 0603', '2', 'LED1 LED2', 'BOT'],
        ])
      ], TableKind.station)!;
      expect(l.headerOf(l.col(ColumnRole.slot)!), 'F');
      expect(l.headerOf(l.col(ColumnRole.side)!), 'Face');
      final items = parseStation([], StationSide.a, layout: l).items;
      expect(items.map((e) => e.side), [StationSide.a, StationSide.a, StationSide.b, StationSide.b]);
    });

    test('a role set by hand moves away from the column that had it', () {
      final l = detectTable([
        g([
          ['a', 'b', 'c'],
          ['K1-0001', 'R1,R2', '2'],
          ['K1-0002', 'C1', '1'],
        ])
      ], TableKind.bom)!;
      final m = l.withRole(2, ColumnRole.partNo);
      expect(m.col(ColumnRole.partNo), 2);
      expect(m.columns.firstWhere((c) => c.index == 0).role, ColumnRole.other);
    });

    test('cover sheet is skipped; one designator per row merges', () {
      final cover = g([
        ['Product', 'MB-V1'],
        ['Revision', 'A2'],
        ['Date', '2026-10-01'],
      ]);
      final rows = g([
        ['No', 'Code', 'Description', 'Loc'],
        ['1', 'K1-0001', 'RES 10K 0402', 'R1'],
        ['2', 'K1-0001', 'RES 10K 0402', 'R2'],
        ['3', 'K1-0002', 'CAP 1uF 0402', 'C1'],
        ['4', 'K1-0003', 'LDO SOT23-5', 'U1'],
      ]);
      final items = parseBom([cover, rows]).items;
      expect(items.map((e) => e.partNo), ['K1-0001', 'K1-0002', 'K1-0003']);
      expect(items.first.refs, ['R1', 'R2']);
    });

    test('large table is recognised quickly', () {
      final rows = [
        ['序号', '编码', '名称', '规格', '数量', '位置', '厂商', '备注'],
        for (var i = 0; i < 3000; i++) ['${i + 1}', 'K${1000 + i}-${i % 97}A', '贴片电阻', '${i % 50}K 0402', '2', 'R${2 * i + 1},R${2 * i + 2}', 'Yageo', ''],
      ];
      final sw = Stopwatch()..start();
      final l = detectTable([g(rows)], TableKind.bom)!;
      expect(sw.elapsedMilliseconds, lessThan(5000));
      expect(l.headerOf(l.col(ColumnRole.partNo)!), '编码');
      expect(l.headerOf(l.col(ColumnRole.refs)!), '位置');
      expect(l.headerOf(l.col(ColumnRole.qty)!), '数量');
    });

    test('demo files', () async {
      final bom = detectTable(await readTableFile('samples/demo/demo_T100_BOM.xlsx'), TableKind.bom)!;
      expect(bom.headerOf(bom.col(ColumnRole.partNo)!), '料件编号');
      expect(bom.headerOf(bom.col(ColumnRole.refs)!), '插件位置');
      expect(bom.headerOf(bom.col(ColumnRole.qty)!), '组成用量');
      expect(bom.headerOf(bom.col(ColumnRole.alt)!), '替代料号');
      for (final f in ['demo_station_A.xlsx', 'demo_station_B.xlsx']) {
        final st = detectTable(await readTableFile('samples/demo/$f'), TableKind.station)!;
        expect(st.headerOf(st.col(ColumnRole.partNo)!), '料号', reason: f);
        expect(st.headerOf(st.col(ColumnRole.refs)!), '位号', reason: f);
        expect(st.headerOf(st.col(ColumnRole.slot)!), '站位', reason: f);
      }
    });
  }, skip: !File('pubspec.yaml').existsSync());
}
