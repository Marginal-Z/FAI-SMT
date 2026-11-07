// A second BOM generator, written apart from the first and never used while
// tuning the reader or the check: other vocabulary, other structures (a
// purchase BOM without designators, a multi-level product BOM with
// mechanical and packaging parts, a PCBA BOM with manufacturer columns) and
// other languages (Japanese, Korean, Spanish, English). Its results are a
// held-out measure. Nothing here is used by the app.
import 'dart:math';

import 'package:smt_fai/core/table_reader.dart';

/// One true line: what the check should find.
class HoldPart {
  HoldPart({required this.pn, required this.kind, required this.desc, required this.qty, required this.refs, this.mpn = '', this.maker = '', this.level});

  final String pn;
  final String kind;
  String desc;
  num qty;
  List<String> refs;
  final String mpn;
  final String maker;
  final int? level;
}

class HoldBom {
  HoldBom(this.grid, this.parts, this.structure, this.language, this.columns);

  final Grid grid;
  final List<HoldPart> parts;

  /// `pcba`, `purchase` or `product`.
  final String structure;
  final String language;

  /// Field → 0-based column.
  final Map<String, int> columns;
}

String _p(Random r, List<String> l) => l[r.nextInt(l.length)];

// Item kinds with names per language and value writers (different
// wordings and value styles from the first generator).
final _items = <String, (Map<String, String>, String Function(Random), String)>{
  'resistor': ({'ja': 'チップ抵抗', 'ko': '칩저항', 'es': 'Resistencia SMD', 'en': 'RES THICK FILM'}, (r) => '${_p(r, ['1k', '47R', '330R', '100k', '10R', '68k'])}Ω ${_p(r, ['1%', '5%'])} ${_p(r, ['0402', '0603'])}', 'R'),
  'capacitor': ({'ja': '積層セラミックコンデンサ', 'ko': '적층세라믹콘덴서', 'es': 'Condensador cerámico', 'en': 'CAP CER'}, (r) => '${_p(r, ['470nF', '2.2uF', '47pF', '10nF', '1nF'])} ${_p(r, ['10V', '25V', '50V'])} ${_p(r, ['X7R', 'C0G'])} ${_p(r, ['0402', '0603', '0805'])}', 'C'),
  'inductor': ({'ja': 'パワーインダクタ', 'ko': '파워인덕터', 'es': 'Inductor de potencia', 'en': 'IND PWR'}, (r) => '${_p(r, ['3.3uH', '6.8uH', '15uH'])} ${_p(r, ['1.2A', '2.5A'])}', 'L'),
  'diode': ({'ja': 'ショットキーダイオード', 'ko': '쇼트키다이오드', 'es': 'Diodo Schottky', 'en': 'DIODE SCHOTTKY'}, (r) => '${_p(r, ['B5819W', 'RB520S30', 'MBR0530'])} ${_p(r, ['SOD-123', 'SOD-523'])}', 'D'),
  'ic': ({'ja': 'IC', 'ko': 'IC', 'es': 'Circuito integrado', 'en': 'IC MCU'}, (r) => '${_p(r, ['ATSAMD21G18A', 'ESP32-S3', 'CH340C', 'MP2315'])} ${_p(r, ['QFN48', 'SOIC16', 'TSOT23-8'])}', 'U'),
  'connector': ({'ja': 'コネクタ', 'ko': '커넥터', 'es': 'Conector', 'en': 'CONN HEADER'}, (r) => '${_p(r, ['1x8P', '2x5P', '1x3P'])} ${_p(r, ['2.54mm', '1.27mm'])}', 'J'),
  'mechanical': ({'ja': 'ネジ', 'ko': '나사', 'es': 'Tornillo', 'en': 'SCREW'}, (r) => 'M${_p(r, ['2', '2.5', '3'])}x${_p(r, ['4', '6', '8'])}', ''),
  'packaging': ({'ja': '梱包箱', 'ko': '포장박스', 'es': 'Caja de embalaje', 'en': 'CARTON BOX'}, (r) => '${_p(r, ['200x150x80', '320x240x60'])}mm', ''),
};

const _heads = {
  'pn': {'ja': '品番', 'ko': '품번', 'es': 'Código', 'en': 'Item No.'},
  'desc': {'ja': '品名・仕様', 'ko': '품명/규격', 'es': 'Descripción', 'en': 'Description'},
  'qty': {'ja': '員数', 'ko': '수량', 'es': 'Cantidad', 'en': 'Qty Per'},
  'refs': {'ja': '部品番号', 'ko': '부품위치', 'es': 'Referencias', 'en': 'Ref Designators'},
  'mpn': {'ja': 'メーカー品番', 'ko': '제조사 품번', 'es': 'Ref. fabricante', 'en': 'Mfr Part #'},
  'maker': {'ja': 'メーカー', 'ko': '제조사', 'es': 'Fabricante', 'en': 'Manufacturer'},
  'level': {'ja': '階層', 'ko': '레벨', 'es': 'Nivel', 'en': 'Level'},
};

const _makers = ['Murata', 'Yageo', 'Vishay', 'TDK', 'Kemet', 'ROHM', 'Bourns', 'Molex', 'Littelfuse', 'Taiyo Yuden'];

HoldBom holdoutBom(int seed) {
  final r = Random(seed * 104729 + 3);
  final language = _p(r, ['ja', 'ko', 'es', 'en']);
  final structure = _p(r, ['pcba', 'purchase', 'product']);
  final parts = <HoldPart>[];
  final counters = <String, int>{};
  final kinds = structure == 'product' ? _items.keys.toList() : _items.keys.where((k) => k != 'packaging').toList();
  final n = 8 + r.nextInt(30);
  for (var i = 0; i < n; i++) {
    final kind = _p(r, kinds);
    final (names, spec, prefix) = _items[kind]!;
    final placed = structure != 'purchase' && prefix.isNotEmpty;
    final count = placed ? 1 + r.nextInt(5) : 1 + r.nextInt(4);
    final refs = placed ? [for (var k = 0; k < count; k++) '$prefix${counters[prefix] = (counters[prefix] ?? 0) + 1}'] : <String>[];
    final pn = '${_p(r, ['A', 'B', 'E', 'M'])}${(100000 + r.nextInt(899999))}${structure == 'product' ? '-${r.nextInt(9)}' : ''}';
    parts.add(HoldPart(
      pn: pn,
      kind: kind,
      desc: '${names[language]} ${spec(r)}',
      qty: count,
      refs: refs,
      mpn: structure == 'pcba' && prefix.isNotEmpty ? 'MP${r.nextInt(999999)}${_p(r, ['TR', 'KR', '-T1'])}' : '',
      maker: structure == 'pcba' ? _p(r, _makers) : '',
      level: structure == 'product' ? (kind == 'packaging' || kind == 'mechanical' ? 1 : 2) : null,
    ));
  }
  // Each layout lists its own fields.
  final fields = switch (structure) {
    'purchase' => ['pn', 'desc', 'qty'],
    'product' => ['level', 'pn', 'desc', 'qty', 'refs'],
    _ => ['pn', 'desc', 'mpn', 'maker', 'qty', 'refs'],
  };
  if (structure != 'product') fields.shuffle(r);
  final headerless = r.nextDouble() < 0.15;
  final rows = <List<String>>[
    if (!headerless) [for (final f in fields) _heads[f]![language]!],
    for (final p in parts)
      [
        for (final f in fields)
          switch (f) {
            'pn' => p.pn,
            'desc' => p.desc,
            'qty' => '${p.qty}',
            'refs' => p.refs.join(language == 'ja' ? '、' : ', '),
            'mpn' => p.mpn,
            'maker' => p.maker,
            _ => '${p.level ?? ''}',
          },
      ],
  ];
  return HoldBom(Grid('BOM', rows), parts, structure, language, {for (var i = 0; i < fields.length; i++) fields[i]: i});
}

/// The same parts in another layout with one change per part, and the
/// result each change calls for: `none` PASS, `value` / `qty` NG,
/// `deleted` / `added` UNMATCHED.
(Grid, Map<String, String>) holdoutRevision(HoldBom b, int seed) {
  final r = Random(seed * 7 + 1);
  final changes = <String, String>{};
  final rows = <List<String>>[];
  final cols = ['desc', 'refs', 'qty', 'pn']..shuffle(r);
  rows.add([for (final c in cols) {'pn': 'Part', 'desc': 'Spec', 'qty': 'Q', 'refs': 'Pos'}[c]!]);
  for (final p in b.parts) {
    final roll = r.nextDouble();
    var desc = p.desc, qty = p.qty;
    var change = 'none';
    if (roll < 0.08) {
      change = 'deleted';
    } else if (roll < 0.16) {
      // Another value of the first number in the description.
      final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(desc);
      if (m != null) {
        final v = double.parse(m.group(1)!);
        final nv = v * 3;
        desc = desc.replaceRange(m.start, m.end, nv == nv.roundToDouble() ? '${nv.toInt()}' : '$nv');
        change = 'value';
      }
    } else if (roll < 0.22) {
      qty = qty + 2;
      change = 'qty';
    }
    changes[p.pn] = change;
    if (change == 'deleted') continue;
    rows.add([
      for (final c in cols)
        switch (c) {
          'pn' => p.pn,
          'desc' => desc,
          'qty' => '$qty',
          _ => p.refs.join(','),
        },
    ]);
  }
  rows.add([for (final c in cols) {'pn': 'Z${seed}NEW', 'desc': 'Extra part 999R 0402', 'qty': '1', 'refs': b.structure == 'purchase' ? '' : 'RZ9'}[c]!]);
  changes['Z${seed}NEW'] = 'added';
  return (Grid('Rev', rows), changes);
}
