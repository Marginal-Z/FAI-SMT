// A second BOM made from a generated one: new layout and language, and one
// injected change per part with the result the check should give. Nothing
// here is used by the app.
import 'dart:math';

import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/table_reader.dart';

import 'bom_gen.dart';

/// Kinds of change, and the result each should lead to.
const expectedFor = {
  'none': CheckStatus.pass,
  'units': CheckStatus.pass,
  'split_line': CheckStatus.pass,
  'param': CheckStatus.ng,
  'qty': CheckStatus.ng,
  'drop_ref': CheckStatus.ng,
  'maker': CheckStatus.ng,
  'deleted': CheckStatus.unmatched,
  'added': CheckStatus.unmatched,
  'renumbered': CheckStatus.review,
  'renumbered_alt': CheckStatus.substitute,
};

class MutatedPair {
  MutatedPair(this.left, this.right, this.changes, this.addedPartNos);

  final GeneratedBom left;
  final Grid right;

  /// Part number in the left BOM → change applied to it.
  final Map<String, String> changes;

  /// Parts only the right BOM has.
  final List<String> addedPartNos;
}

/// Writes values differently without changing them.
String rewriteUnits(String spec) {
  const swaps = {
    '100nF': '0.1uF', '1uF': '1000nF', '10uF': '10µF', '22pF': '22 pF', '10K': '10kΩ', '4.7K': '4K7', '2.2K': '2K2',
    '100R': '100Ω', '1M': '1MΩ', '49.9R': '49.9Ω', '0R': '0Ω', '1uH': '1µH', '2.2uH': '2.2µH', '4.7uH': '4.7µH', '10uH': '10µH',
    '24MHz': '24 MHz', '8MHz': '8 MHz', '12MHz': '12 MHz', '32.768KHz': '32.768kHz', '±1%': '1%', '±5%': '5%', 'SOT-23': 'SOT23',
  };
  return spec.split(' ').map((t) => swaps[t] ?? t).join(' ');
}

/// Changes one value of [spec]; null when it has none to change.
String? changeValue(String spec, Random r) {
  final tokens = spec.split(' ');
  final idx = [for (var i = 0; i < tokens.length; i++) if (RegExp(r'^[±\d]').hasMatch(tokens[i])) i];
  if (idx.isEmpty) return null;
  final i = idx[r.nextInt(idx.length)];
  final t = tokens[i];
  const sizes = {'0201': '0402', '0402': '0603', '0603': '0805', '0805': '1206', '1206': '0805'};
  if (sizes.containsKey(t)) {
    tokens[i] = sizes[t]!;
  } else {
    final m = RegExp(r'^(±?)(\d+(?:\.\d+)?)(.*)$').firstMatch(t)!;
    final v = double.parse(m.group(2)!);
    final nv = v == 0 ? 1 : v * 2.2;
    final txt = nv == nv.roundToDouble() ? nv.toInt().toString() : nv.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    tokens[i] = '${m.group(1)}$txt${m.group(3)}';
  }
  return tokens.join(' ');
}

MutatedPair mutateBom(int seed) {
  final left = generateBom(seed);
  final r = Random(seed * 31 + 5);
  final language = r.nextBool() ? left.layout.language : _other(left.layout.language, r);
  final hasMaker = left.parts.any((p) => p.maker.isNotEmpty);
  final changes = <String, String>{};
  final rows = <({String pn, String name, String spec, num qty, List<String> refs, String maker, List<String> alts, bool dnp, int? level})>[];
  for (final p in left.parts) {
    final roll = r.nextDouble();
    var change = 'none';
    var pn = p.partNo, spec = p.spec, qty = p.qty, refs = [...p.refs], maker = p.maker, alts = [...p.alternates];
    if (roll < 0.10) {
      change = 'units';
      spec = rewriteUnits(spec);
      if (spec == p.spec) change = 'none';
    } else if (roll < 0.15 && refs.length >= 2) {
      change = 'split_line';
    } else if (roll < 0.20) {
      final c = changeValue(spec, r);
      if (c != null) {
        spec = c;
        change = 'param';
      }
    } else if (roll < 0.24) {
      qty = qty + 1;
      change = 'qty';
    } else if (roll < 0.28 && refs.length >= 2) {
      refs.removeLast();
      qty = qty - 1;
      change = 'drop_ref';
    } else if (roll < 0.31 && hasMaker && maker.isNotEmpty) {
      maker = maker == 'Murata' ? 'Yageo' : 'Murata';
      change = 'maker';
    } else if (roll < 0.35) {
      change = 'deleted';
    } else if (roll < 0.39 && refs.isNotEmpty) {
      pn = 'X${p.partNo}';
      change = 'renumbered';
    } else if (roll < 0.42 && refs.isNotEmpty) {
      pn = 'X${p.partNo}';
      alts = [p.partNo];
      change = 'renumbered_alt';
    }
    changes[p.partNo] = change;
    if (change == 'deleted') continue;
    final name = generatorKinds.contains(p.kind) ? nameOf(p.kind, language) : p.name;
    if (change == 'split_line') {
      final half = refs.length ~/ 2;
      rows.add((pn: pn, name: name, spec: spec, qty: half, refs: refs.sublist(0, half), maker: maker, alts: alts, dnp: p.dnp, level: p.level));
      rows.add((pn: pn, name: name, spec: spec, qty: refs.length - half, refs: refs.sublist(half), maker: maker, alts: alts, dnp: p.dnp, level: p.level));
    } else {
      rows.add((pn: pn, name: name, spec: spec, qty: qty, refs: refs, maker: maker, alts: alts, dnp: p.dnp, level: p.level));
    }
  }
  // Parts only the right BOM has.
  final added = <String>[];
  for (var i = 0; i < 1 + r.nextInt(2); i++) {
    final pn = 'NEW-$seed-$i';
    added.add(pn);
    rows.insert(r.nextInt(rows.length + 1), (pn: pn, name: nameOf('resistor', language), spec: '330K ±1% 0603', qty: 1, refs: ['RX${i + 1}'], maker: hasMaker ? 'Yageo' : '', alts: <String>[], dnp: false, level: left.parts.first.level == null ? null : 2));
  }

  // Layout: columns in random order, common headers or none.
  final withMaker = hasMaker, withAlt = rows.any((x) => x.alts.isNotEmpty), withDnp = left.parts.any((p) => p.dnp), withLevel = left.parts.any((p) => p.level != null);
  final cols = ['pn', 'desc', 'qty', 'refs', if (withMaker) 'maker', if (withAlt) 'alt', if (withDnp) 'dnp', if (withLevel) 'level']..shuffle(r);
  final headerless = r.nextDouble() < 0.25;
  const headers = {
    'pn': ['Part Number', '料号'], 'desc': ['Description', '物料描述'], 'qty': ['Qty', '用量'], 'refs': ['Designator', '位号'],
    'maker': ['Manufacturer', '厂商'], 'alt': ['Alternate', '替代料号'], 'dnp': ['DNP', 'DNP'], 'level': ['Level', '阶层'],
  };
  final zh = language == 'zh' ? 1 : 0;
  final grid = <List<String>>[
    if (!headerless) [for (final c in cols) headers[c]![zh]],
    for (final x in rows)
      [
        for (final c in cols)
          switch (c) {
            'pn' => x.pn,
            'desc' => '${x.name} ${x.spec}',
            'qty' => '${x.qty}',
            'refs' => x.refs.join(','),
            'maker' => x.maker,
            'alt' => x.alts.join(','),
            'dnp' => x.dnp ? 'DNP' : '',
            _ => '${x.level ?? ''}',
          },
      ],
  ];
  return MutatedPair(left, Grid('Right', grid), changes, added);
}

String _other(String language, Random r) {
  final others = ['zh', 'en', 'de', 'th']..remove(language);
  return others[r.nextInt(others.length)];
}
