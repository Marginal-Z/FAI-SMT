// Time to read and check large BOMs.
//
//   dart run tool/bench_perf.dart
import 'dart:io';
import 'dart:math';

import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/table_reader.dart';

Grid _bom(int n, int seed, {bool renumber = false, bool refs = true}) {
  final r = Random(seed);
  final rows = <List<String>>[
    ['Part Number', 'Description', 'Qty', 'Designator', 'Manufacturer'],
  ];
  var ref = 0;
  for (var i = 0; i < n; i++) {
    final k = i % 4;
    final spec = switch (k) {
      0 => '贴片电阻 ${1 + i % 97}K ±1% 0402',
      1 => '贴片电容 ${1 + i % 89}nF 16V X7R 0402',
      2 => 'IC TPS${60000 + i} QFN16',
      _ => 'Connector ${2 + i % 30}P 2.54mm',
    };
    final count = 1 + r.nextInt(4);
    final rs = [for (var c = 0; c < count; c++) '${['R', 'C', 'U', 'J'][k]}${++ref}'];
    rows.add([renumber ? 'N${100000 + i}' : 'K${100000 + i}', spec, refs ? '$count' : '${count + (i % 50 == 0 ? 1 : 0)}', refs ? rs.join(',') : '', ['Murata', 'Yageo', 'TI', 'Molex'][k]]);
  }
  return Grid('BOM', rows);
}

void main() {
  for (final n in [500, 2000, 5000]) {
    final sw = Stopwatch()..start();
    final a = readBom([_bom(n, 1)], id: 'S');
    final tRead = sw.elapsedMilliseconds;
    final b = readBom([_bom(n, 1)], id: 'A');
    sw.reset();
    final r1 = compareBoms(a, b, null);
    final tSame = sw.elapsedMilliseconds;
    // Renumbered: matching by designators.
    final c = readBom([_bom(n, 1, renumber: true)], id: 'A');
    sw.reset();
    final r2 = compareBoms(a, c, null);
    final tRefs = sw.elapsedMilliseconds;
    // Renumbered without designators: matching by parameters.
    final d0 = readBom([_bom(n, 1, refs: false)], id: 'S');
    final d1 = readBom([_bom(n, 1, renumber: true, refs: false)], id: 'A');
    sw.reset();
    final r3 = compareBoms(d0, d1, null);
    final tParams = sw.elapsedMilliseconds;
    stdout.writeln('$n lines: read $tRead ms; same numbers $tSame ms (${r1.count(CheckStatus.pass)} pass); '
        'renumbered by designators $tRefs ms (${r2.count(CheckStatus.review)} review); '
        'no designators $tParams ms (${r3.count(CheckStatus.unmatched)} unmatched)');
  }
}
