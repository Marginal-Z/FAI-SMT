// Generates demo input files under samples/demo/ for trying the app.
//
//   dart run tool/gen_demo.dart
import 'dart:io';
import 'dart:math';

import 'package:excel/excel.dart';

void main() {
  final dir = Directory('samples/demo')..createSync(recursive: true);
  final rnd = Random(7);

  // (part no, name, spec, refs, alternate)
  final bom = <(String, String, String, List<String>, String)>[
    ('K1101-1C302X-001A', '贴片IC 主芯片', 'C302XS BGA128 Amlogic', ['U5'], ''),
    ('K1101-2512M0-301A', '贴片IC DDR3L', 'NT5CC256M16EP-EK 512MB', ['3U2', '3U3'], ''),
    ('K1101-42836E-001A', '贴片IC LDO', 'WL2836E12-5 SOT23-5L 韦尔半导体', ['9U2'], ''),
    ('K1101-42836E-002A', '贴片IC LDO', 'WL2836E33-5 SOT23-5L 韦尔半导体', ['9U3'], ''),
    ('K1101-EMMC08-001A', '贴片IC eMMC', '8GB FBGA153', ['U7'], ''),
    ('K1101-WIFI01-001A', '贴片模组 WiFi', 'RTL8189FTV QFN', ['U9'], ''),
    ('K1102-1020K0-001A', '贴片电阻', '10K ±1% 0402', ['R1', 'R2', 'R3', 'R4', 'R5', 'R6'], ''),
    ('K1102-1022K2-001A', '贴片电阻', '2.2K ±1% 0402', ['R10', 'R11', 'R12'], ''),
    ('K1102-1020R0-001A', '贴片电阻', '0R ±5% 0402', ['R20', 'R21', 'R22', 'R23'], ''),
    ('K1102-1049K9-001A', '贴片电阻', '49.9R ±1% 0402', ['R30', 'R31'], ''),
    ('K1102-1100K0-001A', '贴片电阻', '100K ±1% 0402', ['R40', 'R41', 'R42'], ''),
    ('K1103-0104K0-001A', '贴片电容', '100nF 16V X7R 0402', ['C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7', 'C8'], ''),
    ('K1103-0106K0-001A', '贴片电容', '10uF 6.3V X5R 0603', ['C10', 'C11', 'C12', 'C13'], 'K1103-0106K0-002A'),
    ('K1103-0220P0-001A', '贴片电容', '22pF 50V NPO 0402', ['C20', 'C21'], ''),
    ('K1103-0475K0-001A', '贴片电容', '4.7uF 10V X5R 0402', ['C30', 'C31', 'C32'], ''),
    ('K1103-0226K0-001A', '贴片电容', '22uF 6.3V X5R 0805', ['C40', 'C41'], ''),
    ('K1104-2R2M00-001A', '贴片电感', '2.2uH 2A 2520', ['L1', 'L2'], ''),
    ('K1105-24M000-001A', '贴片晶振', '24MHz 3225 ±10ppm', ['Y1'], ''),
    ('K1106-LED0G0-001A', '贴片LED', '绿色 0603', ['LED1'], ''),
    ('K1106-LED0R0-001A', '贴片LED', '红色 0603', ['LED2'], ''),
    ('K1107-ESD050-001A', '贴片TVS', 'ESD5V0 SOD-523', ['D1', 'D2', 'D3', 'D4'], ''),
    ('K1108-USB2A0-001A', '贴片USB座', 'USB2.0 A型 母座', ['J1'], ''),
    ('K1108-HDMI00-001A', '贴片HDMI座', 'HDMI A型 19P', ['J2'], ''),
    ('K1109-MOS340-001A', '贴片MOS', 'AO3400 SOT23', ['Q1', 'Q2'], ''),
    ('K1102-1004K7-001A', '贴片电阻', '4.7K ±1% 0402', ['R50', 'R51', 'R52'], ''),
    ('K1103-0105K0-001A', '贴片电容', '1uF 16V X5R 0402', ['C50', 'C51', 'C52', 'C53'], ''),
    ('K1201-PCB000-001A', 'PCB 光板', 'FR4 1.6mm 4层', [], ''),
    ('K1301-DIPCAP-001A', '插件电解电容', '470uF 16V 8x12', ['EC1', 'EC2'], ''),
    ('K1302-DCJACK-001A', 'DIP DC座', 'DC-005 5.5x2.1', ['J5'], ''),
    ('K1401-SOLDER-001A', '锡膏', 'SAC305 500g', [], ''),
    ('K1402-LABEL0-001A', '标签', '条码标签 30x10', [], ''),
  ];

  // Deliberate problems so every result area has content.
  final stationRefs = {for (final b in bom) b.$1: [...b.$4]};
  stationRefs['K1103-0220P0-001A'] = ['C20']; // missing C21
  stationRefs['K1102-1049K9-001A'] = ['R30', 'R31', 'R32']; // extra R32
  stationRefs['K1103-0106K0-001A'] = ['C10', 'C11']; // C12, C13 loaded with the alternate
  final qtyOverride = {'K1104-2R2M00-001A': 3}; // BOM qty disagrees with 2 designators

  // ---- T100 BOM workbook
  final book = Excel.createExcel();
  final sheet = book['BOM'];
  book.delete('Sheet1');
  sheet.appendRow([TextCellValue('T100 BOM 资料打印  主件料号: S905-MB-V1.2')]);
  sheet.appendRow([
    for (final h in ['主件料件编号', '项次', '料件编号', '品名', '规格', '组成用量', '插件位置', '替代料号'])
      TextCellValue(h)
  ]);
  var seq = 0;
  for (final b in bom) {
    seq += 10;
    final refs = b.$4;
    // Long designator lists continue on the next row, like the T100 export.
    final first = refs.length > 5 ? refs.sublist(0, 5) : refs;
    final rest = refs.length > 5 ? refs.sublist(5) : const <String>[];
    sheet.appendRow([
      TextCellValue('S905-MB-V1.2'),
      IntCellValue(seq),
      TextCellValue(b.$1),
      TextCellValue(b.$2),
      TextCellValue(b.$3),
      DoubleCellValue((qtyOverride[b.$1] ?? (refs.isEmpty ? 1 : refs.length)).toDouble()),
      TextCellValue(first.join(',')),
      TextCellValue(b.$5),
    ]);
    if (rest.isNotEmpty) {
      sheet.appendRow([TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(''), TextCellValue(rest.join(',')), TextCellValue('')]);
    }
  }
  File('${dir.path}/demo_T100_BOM.xlsx').writeAsBytesSync(book.encode()!);

  // ---- Station lists: big ICs and connectors on side A, passives split.
  final sideB = {'K1103-0104K0-001A', 'K1102-1020K0-001A', 'K1103-0475K0-001A', 'K1107-ESD050-001A'};
  final skip = {'K1201-PCB000-001A', 'K1301-DIPCAP-001A', 'K1302-DCJACK-001A', 'K1401-SOLDER-001A', 'K1402-LABEL0-001A'};
  for (final side in ['A', 'B']) {
    final b = Excel.createExcel();
    final s = b['站位表'];
    b.delete('Sheet1');
    s.appendRow([TextCellValue('SMT 站位表  线别: SMT-0$side  机种: S905-MB-V1.2')]);
    s.appendRow([for (final h in ['站位', '料号', '物料描述', '数量', '位号']) TextCellValue(h)]);
    var slot = 0;
    void add(String pn, String desc, List<String> refs) {
      slot++;
      s.appendRow([
        TextCellValue('$side-${slot.toString().padLeft(2, '0')}'),
        TextCellValue(pn),
        TextCellValue(desc),
        IntCellValue(refs.length),
        TextCellValue(refs.join(',')),
      ]);
    }

    for (final item in bom) {
      if (skip.contains(item.$1)) continue;
      if ((side == 'B') != sideB.contains(item.$1)) continue;
      add(item.$1, '${item.$2} ${item.$3}', stationRefs[item.$1]!);
    }
    if (side == 'A') {
      add('K1103-0106K0-002A', '贴片电容 10uF 6.3V X5R 0603 (替代)', ['C12', 'C13']);
      add('K1102-1000R0-009A', '贴片电阻 1K 0402', ['R99']); // not in BOM
    }
    File('${dir.path}/demo_station_$side.xlsx').writeAsBytesSync(b.encode()!);
  }

  // ---- Coordinates (Altium pick & place style CSV, mm)
  final buf = StringBuffer()
    ..writeln('Altium Designer Pick and Place Locations')
    ..writeln('Units used in this file : mm')
    ..writeln()
    ..writeln('"Designator","Comment","Layer","Footprint","Center-X(mm)","Center-Y(mm)","Rotation","Description"');
  final allRefs = <String, (String, bool)>{};
  for (final item in bom) {
    for (final r in {...item.$4, ...?stationRefs[item.$1]}) {
      allRefs[r] = (item.$3, sideB.contains(item.$1));
    }
  }
  allRefs['R99'] = ('1K', false);
  allRefs.remove('EC1');
  allRefs.remove('EC2');
  allRefs.remove('J5');
  for (final m in ['MARK1', 'MARK2', 'MARK3']) {
    allRefs[m] = ('MARK', false);
  }
  allRefs['TP1'] = ('TP', false);
  var i = 0;
  for (final e in allRefs.entries) {
    final x = 6 + (i % 14) * 6.5 + rnd.nextDouble();
    final y = 6 + (i ~/ 14) * 9.0 + rnd.nextDouble();
    final rot = [0, 90, 180, 270][rnd.nextInt(4)];
    buf.writeln('"${e.key}","${e.value.$1}","${e.value.$2 ? 'BottomLayer' : 'TopLayer'}","FP","${x.toStringAsFixed(3)}","${y.toStringAsFixed(3)}","$rot",""');
    i++;
  }
  File('${dir.path}/demo_coordinates.csv').writeAsStringSync(buf.toString());
  stdout.writeln('Demo files written to ${dir.path}');
}
