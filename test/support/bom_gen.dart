// Generates BOM sheets with randomly chosen layouts and known answers, for
// testing the reader and the check on files it has never seen. Nothing here
// is used by the app.
import 'dart:math';

import 'package:smt_fai/core/table_reader.dart';

/// What a generated part really is.
class TruePart {
  TruePart(this.partNo, this.name, this.spec, this.refs, this.qty, this.kind);

  final String partNo;
  final String name;
  final String spec;
  final List<String> refs;
  final num qty;
  final String kind;

  /// Excel row of its first line, filled in when the sheet is laid out.
  int row = 0;

  // Optional attributes, set when the sheet has the column.
  String maker = '';
  String mpn = '';
  List<String> alternates = const [];
  bool dnp = false;
  int? level;
}

/// How the sheet was laid out, for per-category statistics.
class Layout {
  Layout({required this.language, required this.headerless, required this.titleRows, required this.splitDescription, required this.headerStyle, this.partNoStyle = 0});

  final String language;
  final bool headerless;
  final int titleRows;
  final bool splitDescription;

  /// `common` (words a BOM usually uses), `rare` (unusual wording) or `none`.
  final String headerStyle;

  /// 0 letters+digits with dashes, 1 digit groups, 2 digits only, 3 prefix-number.
  final int partNoStyle;

  String get category => headerless ? 'headerless' : '$headerStyle-header';
}

class GeneratedBom {
  GeneratedBom(this.grid, this.parts, this.layout, this.columnOf);

  final Grid grid;
  final List<TruePart> parts;
  final Layout layout;

  /// Field → 0-based column index in [grid].
  final Map<String, int> columnOf;
}

// Part families: designator prefix, names per language, spec builder.
class _Family {
  const _Family(this.kind, this.prefix, this.names, this.spec, {this.refs = true});

  final String kind;
  final String prefix;
  final Map<String, String> names;
  final String Function(Random r) spec;
  final bool refs;
}

String _pick(Random r, List<String> l) => l[r.nextInt(l.length)];

/// Name of an item kind in a language (zh, en, de, th), as the generator
/// writes it.
String nameOf(String kind, String language) => _families.firstWhere((f) => f.kind == kind).names[language] ?? kind;

/// Kinds the generator makes.
List<String> get generatorKinds => [for (final f in _families) f.kind];

final _sizes = ['0201', '0402', '0603', '0805', '1206'];

final _families = <_Family>[
  _Family('resistor', 'R', {'zh': '贴片电阻', 'en': 'Chip resistor', 'de': 'SMD-Widerstand', 'th': 'ตัวต้านทาน'}, (r) => '${_pick(r, ['10K', '4.7K', '100R', '0R', '49.9R', '1M', '2.2K'])} ${_pick(r, ['±1%', '±5%'])} ${_pick(r, _sizes)}'),
  _Family('capacitor', 'C', {'zh': '贴片电容', 'en': 'MLCC', 'de': 'Keramikkondensator', 'th': 'ตัวเก็บประจุ'}, (r) => '${_pick(r, ['100nF', '1uF', '10uF', '22pF', '4.7uF'])} ${_pick(r, ['6.3V', '16V', '25V', '50V'])} ${_pick(r, ['X5R', 'X7R', 'NPO'])} ${_pick(r, _sizes)}'),
  _Family('inductor', 'L', {'zh': '功率电感', 'en': 'Power inductor', 'de': 'Speicherdrossel', 'th': 'ตัวเหนี่ยวนำ'}, (r) => '${_pick(r, ['1uH', '2.2uH', '4.7uH', '10uH'])} ${_pick(r, ['1A', '2A', '3A'])} ${_pick(r, ['2520', '3015', '4040'])}'),
  _Family('ic', 'U', {'zh': '集成电路', 'en': 'IC', 'de': 'IC', 'th': 'ไอซี'}, (r) => '${_pick(r, ['TPS62130', 'STM32F103C8T6', 'LM358', 'AMS1117-3.3', 'W25Q64JV'])} ${_pick(r, ['QFN16', 'LQFP48', 'SOIC8', 'SOT223'])}'),
  _Family('diode', 'D', {'zh': '二极管', 'en': 'Diode', 'de': 'Diode', 'th': 'ไดโอด'}, (r) => '${_pick(r, ['1N4148W', 'SS34', 'BAT54C', 'ESD5V0'])} ${_pick(r, ['SOD-123', 'SMA', 'SOT-23', 'SOD-523'])}'),
  _Family('led', 'LED', {'zh': '发光二极管', 'en': 'LED', 'de': 'LED', 'th': 'แอลอีดี'}, (r) => '${_pick(r, ['RED', 'GREEN', 'BLUE'])} ${_pick(r, ['0603', '0805'])}'),
  _Family('transistor', 'Q', {'zh': '三极管', 'en': 'Transistor', 'de': 'Transistor', 'th': 'ทรานซิสเตอร์'}, (r) => '${_pick(r, ['AO3400', 'MMBT3904', '2N7002'])} SOT-23'),
  _Family('connector', 'J', {'zh': '连接器', 'en': 'Connector', 'de': 'Steckverbinder', 'th': 'คอนเนคเตอร์'}, (r) => '${_pick(r, ['2P', '4P', '6P', '10P'])} ${_pick(r, ['1.25mm', '2.0mm', '2.54mm'])}'),
  _Family('crystal', 'Y', {'zh': '晶振', 'en': 'Crystal', 'de': 'Quarz', 'th': 'คริสตัล'}, (r) => '${_pick(r, ['8MHz', '12MHz', '24MHz', '32.768KHz'])} ${_pick(r, ['3225', '2016'])}'),
  _Family('mechanical', '', {'zh': '屏蔽罩', 'en': 'Shield can', 'de': 'Abschirmung', 'th': 'ฝาครอบ'}, (r) => '${_pick(r, ['20x20mm', '15x30mm'])} SPTE', refs: false),
  _Family('packaging', '', {'zh': '防静电袋', 'en': 'ESD bag', 'de': 'ESD-Beutel', 'th': 'ถุงกันไฟฟ้าสถิต'}, (r) => '${_pick(r, ['100x150', '200x300'])}mm', refs: false),
];

// Header words: common ones a BOM usually uses, and rarer wordings.
const _common = {
  'partNo': {'zh': ['料号', '物料编码'], 'en': ['Part Number', 'P/N'], 'de': ['Materialnummer'], 'th': ['รหัสชิ้นส่วน']},
  'name': {'zh': ['品名', '名称'], 'en': ['Description', 'Name'], 'de': ['Bezeichnung'], 'th': ['ชื่อ']},
  'spec': {'zh': ['规格'], 'en': ['Value', 'Spec'], 'de': ['Wert'], 'th': ['สเปค']},
  'qty': {'zh': ['用量', '数量'], 'en': ['Qty', 'Quantity'], 'de': ['Menge'], 'th': ['จำนวน']},
  'refs': {'zh': ['位号'], 'en': ['Designator', 'Reference'], 'de': ['Bestückungsplatz'], 'th': ['ตำแหน่ง']},
};
const _rare = {
  'partNo': ['Item ID', 'Stock code', 'Sachnummer', 'SKU', '内部编码'],
  'name': ['Article', 'Bauteil', 'Benennung', '物料说明'],
  'spec': ['Details', 'Kennwert', '参数'],
  'qty': ['Pcs/board', 'Stk', 'Usage per unit', '每板个数'],
  'refs': ['Placement', 'Ref Des', 'Positions', 'Bestückung', '点位号'],
};
const _junk = ['Remark', '备注', 'Supplier', 'Lead time', 'RoHS', 'Unit price'];

// Real makers; some are deliberately not in the app's knowledge list.
const _makers = ['Murata', 'Yageo', 'Samsung', 'TDK', 'Vishay', 'Texas Instruments', 'Nexperia', 'Molex', 'Kemet', 'Everlight', 'Hirose', 'Diodes Inc', 'Hongfa', 'Torex', '3PEAK', 'Chipown', 'UNI-ROYAL', 'Fenghua'];

// Attribute column headers: common wordings, then rarer ones.
const _attrHeaders = {
  'maker': (['Manufacturer', '厂商', 'Hersteller', 'ผู้ผลิต', 'Brand'], ['Make', 'Source', '供应商品牌']),
  'mpn': (['MPN', '厂商料号', 'Herstellerteilenummer', 'Mfr P/N'], ['Maker P/N', 'OEM No.', '原厂编码']),
  'alt': (['Alternate', '替代料号', 'Ersatzteil'], ['Second source', 'Sub P/N', '代料']),
  'dnp': (['DNP', '贴装', 'Fitted'], ['Bestückt', 'Assembly option', '是否装配']),
  'level': (['Level', '阶层', 'Ebene'], ['Lvl.', 'BOM depth', '层']),
  'remark': (['Remark', '备注', 'Bemerkung', 'หมายเหตุ'], ['Note', 'Hinweis', '说明']),
};

String _mpn(Random r) {
  const al = 'ABCDEFGHJKLMNPRSTUVWXYZ0123456789';
  final n = 9 + r.nextInt(9);
  final b = StringBuffer(String.fromCharCodes([65 + r.nextInt(26), 65 + r.nextInt(26)]));
  for (var i = 0; i < n; i++) {
    if (i == 6 && r.nextBool()) b.write('-');
    b.write(al[r.nextInt(al.length)]);
  }
  return b.toString();
}

String _partNo(Random r, int style, int i) => switch (style) {
  0 => 'K${1100 + r.nextInt(400)}-${r.nextInt(999999).toString().padLeft(6, '0')}-${i.toString().padLeft(3, '0')}A',
  1 => '${10 + r.nextInt(80)}-${r.nextInt(9999).toString().padLeft(4, '0')}-${i.toString().padLeft(3, '0')}',
  2 => '${4 + r.nextInt(5)}${r.nextInt(99999999).toString().padLeft(8, '0')}',
  _ => '${String.fromCharCodes([65 + r.nextInt(26), 65 + r.nextInt(26), 65 + r.nextInt(26)])}-${(10000 + i * 7 + r.nextInt(5)).toString()}',
};

/// Writes designators the way different tools do.
String _refsText(Random r, List<String> refs, int style) {
  if (refs.isEmpty) return '';
  switch (style) {
    case 1:
      return refs.join(' ');
    case 2:
      return refs.join(';');
    case 3:
      return refs.join('、');
    case 4:
      // Ranges where the numbers run on.
      final out = <String>[];
      var i = 0;
      while (i < refs.length) {
        var j = i;
        final p = refs[i].replaceAll(RegExp(r'\d+$'), '');
        int n(String s) => int.parse(RegExp(r'\d+$').firstMatch(s)!.group(0)!);
        while (j + 1 < refs.length && refs[j + 1].startsWith(p) && n(refs[j + 1]) == n(refs[j]) + 1) {
          j++;
        }
        out.add(j - i >= 2 ? '${refs[i]}-${refs[j]}' : refs.sublist(i, j + 1).join(','));
        i = j + 1;
      }
      return out.join(',');
    default:
      return refs.join(',');
  }
}

GeneratedBom generateBom(int seed) {
  final r = Random(seed);
  final language = _pick(r, ['zh', 'en', 'de', 'th']);
  final headerless = r.nextDouble() < 0.2;
  final headerStyle = headerless ? 'none' : (r.nextBool() ? 'common' : 'rare');
  final split = r.nextBool();
  final titleRows = headerless ? 0 : r.nextInt(4);
  final pnStyle = r.nextInt(4);
  final refStyle = r.nextInt(5);

  // Parts, designators numbered per prefix.
  final count = 6 + r.nextInt(40);
  final used = <String, int>{};
  final parts = <TruePart>[];
  final seenPn = <String>{};
  for (var i = 0; i < count; i++) {
    final f = _families[r.nextInt(_families.length)];
    var pn = _partNo(r, pnStyle, i);
    while (!seenPn.add(pn)) {
      pn = _partNo(r, pnStyle, i);
    }
    final n = f.refs ? 1 + r.nextInt(r.nextDouble() < 0.2 ? 14 : 4) : 0;
    final refs = [for (var k = 0; k < n; k++) '${f.prefix}${used[f.prefix] = (used[f.prefix] ?? 0) + 1}'];
    final qty = f.refs ? n : 1 + r.nextInt(3);
    parts.add(TruePart(pn, f.names[language]!, f.spec(r), refs, qty, f.kind));
  }

  // Optional attribute columns, from their own random stream so the base
  // layout of a seed stays the same.
  final r2 = Random(seed * 7919 + 17);
  final attr = <String>[
    if (r2.nextDouble() < 0.45) 'maker',
    if (r2.nextDouble() < 0.35) 'mpn',
    if (r2.nextDouble() < 0.3) 'alt',
    if (r2.nextDouble() < 0.25) 'dnp',
    if (r2.nextDouble() < 0.15) 'level',
    if (r2.nextDouble() < 0.3) 'remark',
  ];
  final dottedLevel = r2.nextBool();
  final dnpHeader = _pick(r2, headerStyle == 'rare' ? _attrHeaders['dnp']!.$2 : _attrHeaders['dnp']!.$1);
  final fittedStyle = !dnpHeader.contains('DNP');
  if (attr.contains('level')) {
    // One sub-assembly on level 1; the parts below it on level 2.
    final asm = TruePart(_partNo(r2, pnStyle, 900), {'zh': 'PCBA 主板', 'en': 'PCBA main board', 'de': 'Leiterplattenbaugruppe', 'th': 'แผงวงจร PCBA'}[language]!, 'V1.0', const [], 1, 'pcb')..level = 1;
    for (final p in parts) {
      p.level = 2;
    }
    parts.insert(0, asm);
  }
  for (final p in parts) {
    if (attr.contains('maker')) p.maker = _pick(r2, _makers);
    if (attr.contains('mpn')) p.mpn = _mpn(r2);
    if (attr.contains('alt') && r2.nextDouble() < 0.35) p.alternates = [_partNo(r2, pnStyle, 500 + r2.nextInt(400))];
    if (attr.contains('dnp') && p.refs.isNotEmpty && r2.nextDouble() < 0.15) p.dnp = true;
  }

  // Columns in random order, with unrelated ones.
  final fields = ['partNo', if (split) ...['name', 'spec'] else 'desc', 'qty', 'refs', ...attr];
  final junk = {for (var k = 0; k < r.nextInt(3); k++) _junk[r.nextInt(_junk.length)]}.toList();
  final order = [...fields, ...junk.map((j) => 'junk:$j')]..shuffle(r);
  if (r.nextDouble() < 0.5) order.insert(0, 'serial');
  final columnOf = {for (var c = 0; c < order.length; c++) order[c]: c};

  String header(String f) {
    if (f == 'serial') return _pick(r, ['No.', '序号', 'Pos', '#']);
    if (f.startsWith('junk:')) return f.substring(5);
    if (f == 'dnp') return dnpHeader;
    if (_attrHeaders.containsKey(f)) return _pick(r2, headerStyle == 'rare' ? _attrHeaders[f]!.$2 : _attrHeaders[f]!.$1);
    final key = f == 'desc' ? 'name' : f;
    if (headerStyle == 'rare') return _pick(r, _rare[key]!);
    final byLang = _common[key]!;
    return _pick(r, byLang[language] ?? byLang['en']!);
  }

  final rows = <List<String>>[];
  for (var t = 0; t < titleRows; t++) {
    rows.add([_pick(r, ['BOM', 'Bill of Materials', '物料清单', 'Stückliste']), 'Rev ${r.nextInt(9)}']);
  }
  if (!headerless) rows.add([for (final f in order) header(f)]);
  var serial = 0;
  for (final p in parts) {
    if (r.nextDouble() < 0.06) rows.add(const []);
    // Long designator lists continue on the next row sometimes.
    final cont = p.refs.length > 6 && r.nextDouble() < 0.4;
    final first = cont ? p.refs.sublist(0, 5) : p.refs;
    serial++;
    final qtyText = r.nextDouble() < 0.15 ? '${p.qty}.0' : '${p.qty}';
    rows.add([
      for (final f in order)
        switch (f) {
          'serial' => '$serial',
          'partNo' => p.partNo,
          'name' => p.name,
          'spec' => p.spec,
          'desc' => '${p.name} ${p.spec}',
          'qty' => qtyText,
          'refs' => _refsText(r, first, refStyle),
          'maker' => p.maker,
          'mpn' => p.mpn,
          'alt' => p.alternates.join(','),
          'dnp' => p.dnp ? _pick(r2, fittedStyle ? ['N', '否', 'NO'] : ['DNP', 'NC', '不贴']) : (fittedStyle ? _pick(r2, ['Y', '是', 'YES']) : ''),
          'level' => dottedLevel ? '${'.' * p.level!}${p.level}' : '${p.level}',
          'remark' => _pick(r2, ['RoHS', '无铅', 'Lead-free', '环保 RoHS', 'REACH']),
          _ => r.nextDouble() < 0.5 ? '' : _pick(r, ['Y', 'N/A', 'OK', '3 weeks', '0.02']),
        },
    ]);
    p.row = rows.length;
    if (cont) {
      rows.add([
        for (final f in order) f == 'refs' ? _refsText(r, p.refs.sublist(5), refStyle) : '',
      ]);
    }
  }
  return GeneratedBom(
    Grid('Sheet1', rows),
    parts,
    Layout(language: language, headerless: headerless, titleRows: titleRows, splitDescription: split, headerStyle: headerStyle, partNoStyle: pnStyle),
    columnOf,
  );
}
