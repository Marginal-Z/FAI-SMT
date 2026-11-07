// Generates the demo BOMs under samples/demo/ used by the guided tour and
// the screenshots: a single BOM, and an A-BOM and B-BOM that together should
// match it, with deliberate differences so every result appears.
//
//   dart run tool/gen_demo.dart
import 'dart:io';

import 'package:smt_fai/core/xlsx_writer.dart';

/// (part no, name, spec, designators, brand)
typedef Part = (String, String, String, List<String>, String);

const _bom = <Part>[
  ('K1101-1C302X-001A', '贴片IC 主芯片', 'C302XS BGA128', ['U5'], 'Amlogic'),
  ('K1101-2512M0-301A', '贴片IC DDR3L', 'NT5CC256M16EP-EK 512MB', ['U2', 'U3'], 'Nanya'),
  ('K1101-42836E-001A', '贴片IC LDO', 'WL2836E12-5 SOT23-5L', ['U12'], 'Will Semi'),
  ('K1101-42836E-002A', '贴片IC LDO', 'WL2836E33-5 SOT23-5L', ['U13'], 'Will Semi'),
  ('K1101-EMMC08-001A', '贴片IC eMMC', '8GB FBGA153', ['U7'], 'Samsung'),
  ('K1101-WIFI01-001A', '贴片模组 WiFi', 'RTL8189FTV QFN', ['U9'], 'Realtek'),
  ('K1102-1020K0-001A', '贴片电阻', '10K ±1% 0402', ['R1', 'R2', 'R3', 'R4', 'R5', 'R6', 'R7', 'R8'], 'Yageo'),
  ('K1102-1022K2-001A', '贴片电阻', '2.2K ±1% 0402', ['R10', 'R11', 'R12'], 'Yageo'),
  ('K1102-1020R0-001A', '贴片电阻', '0R ±5% 0402', ['R20', 'R21', 'R22', 'R23'], 'Yageo'),
  ('K1102-1049K9-001A', '贴片电阻', '49.9R ±1% 0402', ['R30', 'R31'], 'Yageo'),
  ('K1102-1100K0-001A', '贴片电阻', '100K ±1% 0402', ['R40', 'R41', 'R42'], 'Yageo'),
  ('K1102-1004K7-001A', '贴片电阻', '4.7K ±1% 0402', ['R50', 'R51', 'R52'], 'Yageo'),
  ('K1103-0104K0-001A', '贴片电容', '100nF 16V X7R 0402', ['C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7', 'C8'], 'Murata'),
  ('K1103-0106K0-001A', '贴片电容', '10uF 6.3V X5R 0603', ['C10', 'C11', 'C12', 'C13'], 'Murata'),
  ('K1103-0220P0-001A', '贴片电容', '22pF 50V NPO 0402', ['C20', 'C21'], 'Murata'),
  ('K1103-0475K0-001A', '贴片电容', '4.7uF 10V X5R 0402', ['C30', 'C31', 'C32'], 'Samsung'),
  ('K1103-0226K0-001A', '贴片电容', '22uF 6.3V X5R 0805', ['C40', 'C41'], 'Samsung'),
  ('K1103-0105K0-001A', '贴片电容', '1uF 16V X5R 0402', ['C50', 'C51', 'C52', 'C53'], 'Murata'),
  ('K1104-2R2M00-001A', '贴片电感', '2.2uH 2A 2520', ['L1', 'L2'], 'Sunlord'),
  ('K1105-24M000-001A', '贴片晶振', '24MHz 3225 ±10ppm', ['Y1'], 'TXC'),
  ('K1106-LED0G0-001A', '贴片LED 绿色', '0603 GREEN', ['LED1'], 'Everlight'),
  ('K1106-LED0R0-001A', '贴片LED 红色', '0603 RED', ['LED2'], 'Everlight'),
  ('K1107-ESD050-001A', '贴片TVS', 'ESD5V0 SOD-523', ['D1', 'D2', 'D3', 'D4'], 'Prisemi'),
  ('K1108-USB2A0-001A', '贴片USB座', 'USB2.0 A型 母座', ['J1'], 'Kinghelm'),
  ('K1108-HDMI00-001A', '贴片HDMI座', 'HDMI A型 19P', ['J2'], 'Kinghelm'),
  ('K1109-MOS340-001A', '贴片MOS', 'AO3400 SOT23', ['Q1', 'Q2'], 'AOS'),
  ('K1402-LABEL0-001A', '标签', '条码标签 30x10', [], ''),
];

/// Parts on the B-BOM (the passives); everything else is on the A-BOM.
const _onB = {'K1102-1020K0-001A', 'K1102-1022K2-001A', 'K1103-0104K0-001A', 'K1103-0475K0-001A', 'K1107-ESD050-001A', 'K1105-24M000-001A'};

void main() {
  final dir = Directory('samples/demo')..createSync(recursive: true);
  for (final f in dir.listSync()) {
    if (f is File) f.deleteSync();
  }

  // ---- Single BOM: a title line, then 序号 / 料号 / 品名 / 规格 / 用量 / 位号 / 品牌.
  final book = XlsxWriter();
  final sheet = book.addSheet('BOM');
  sheet.appendRow(['BOM 物料清单  机种: S905-MB-V1.2']);
  sheet.appendRow([for (final h in ['序号', '料号', '品名', '规格', '用量', '位号', '品牌']) h]);
  var n = 0;
  for (final p in _bom) {
    n++;
    final refs = p.$4;
    // Long designator lists continue on the next row.
    final first = refs.length > 5 ? refs.sublist(0, 5) : refs;
    final rest = refs.length > 5 ? refs.sublist(5) : const <String>[];
    sheet.appendRow([
      n,
      p.$1,
      p.$2,
      p.$3,
      refs.isEmpty ? 1 : refs.length,
      first.join(','),
      p.$5,
    ]);
    if (rest.isNotEmpty) {
      sheet.appendRow(['', '', '', '', '', rest.join(','), '']);
    }
  }
  File('${dir.path}/demo_single_BOM.xlsx').writeAsBytesSync(book.encode());

  // ---- A-BOM: English headers, name and spec in one description column,
  // the Chinese names worded differently (which still matches).
  final a = XlsxWriter();
  final sa = a.addSheet('A-BOM');
  sa.appendRow([for (final h in ['Item', 'Part Number', 'Description', 'Qty', 'Reference', '品牌', '替代料号']) h]);
  const reworded = {'贴片电阻': '贴片电阻器', '贴片电容': '贴片陶瓷电容', '贴片电感': '功率电感', '贴片MOS': '贴片MOS管'};
  var item = 0;
  for (final p in _bom) {
    if (_onB.contains(p.$1)) continue;
    var refs = [...p.$4];
    var spec = p.$3;
    var qty = refs.isEmpty ? 1 : refs.length;
    var brand = p.$5;
    var pn = p.$1, alt = '';
    switch (p.$1) {
      case 'K1103-0220P0-001A':
        refs = ['C20']; // C21 missing
        qty = 1;
      case 'K1102-1049K9-001A':
        refs = ['R30', 'R31', 'R32']; // R32 extra
        qty = 3;
      case 'K1103-0106K0-001A':
        spec = '10uF 10V X5R 0603'; // voltage differs
      case 'K1104-2R2M00-001A':
        qty = 3; // quantity differs from the single BOM
      case 'K1109-MOS340-001A':
        brand = 'Alpha&Omega'; // brand differs
      case 'K1106-LED0G0-001A':
        // Another part number that lists the single BOM's as an alternate.
        pn = 'K1106-LED0G0-002A';
        alt = 'K1106-LED0G0-001A';
      case 'K1108-HDMI00-001A':
        pn = 'K1108-HDMI00-009A'; // another part number, not listed: review
      case 'K1402-LABEL0-001A':
        continue; // only on the single BOM
    }
    item++;
    sa.appendRow([
      item,
      pn,
      '${reworded[p.$2] ?? p.$2} $spec',
      qty,
      refs.join(' '),
      brand,
      alt,
    ]);
  }
  item++;
  sa.appendRow([item, 'K1102-1000R0-009A', '贴片电阻 1K ±1% 0402', 1, 'R99', 'Yageo', '']);
  File('${dir.path}/demo_A_BOM.xlsx').writeAsBytesSync(a.encode());

  // ---- B-BOM: no header row and the columns in another order
  // (designators, part number, description, quantity, brand).
  final b = XlsxWriter();
  final sb = b.addSheet('B');
  for (final p in _bom) {
    if (!_onB.contains(p.$1)) continue;
    sb.appendRow([p.$4.join(','), p.$1, '${p.$2}，${p.$3}', p.$4.length, p.$5]);
  }
  File('${dir.path}/demo_B_BOM.xlsx').writeAsBytesSync(b.encode());
  stdout.writeln('Demo files written to ${dir.path}');
}
