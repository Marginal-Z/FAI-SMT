// Held-out measure: BOMs from test/support/holdout_gen.dart, which was not
// used while tuning. Reports field recognition and check results per
// structure and language.
//
//   dart run tool/eval_holdout.dart [samples]
import 'dart:io';

import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';

import '../test/support/holdout_gen.dart';
import '../test/support/read_eval.dart' show Tally;

const expected = {'none': CheckStatus.pass, 'value': CheckStatus.ng, 'qty': CheckStatus.ng, 'deleted': CheckStatus.unmatched, 'added': CheckStatus.unmatched};

void main(List<String> args) {
  final n = args.isEmpty ? 400 : int.parse(args.first);
  final groups = <String, Tally>{};
  final all = Tally();
  final wrong = <String>[];
  for (var seed = 0; seed < n; seed++) {
    final b = holdoutBom(seed);
    final ts = [all, groups.putIfAbsent('structure ${b.structure}', Tally.new), groups.putIfAbsent('lang ${b.language}', Tally.new)];
    void add(String m, bool ok) {
      for (final t in ts) {
        t.add(m, ok);
      }
    }

    BomDocument doc;
    try {
      doc = readBom([b.grid], id: 'S');
    } on BomReadException {
      add('read_ok', false);
      continue;
    }
    add('read_ok', true);
    for (final e in {'pn': BomRole.partNo, 'qty': BomRole.quantity, 'refs': BomRole.refs, 'desc': BomRole.description, 'mpn': BomRole.mpn, 'maker': BomRole.maker, 'level': BomRole.level}.entries) {
      final c = b.columns[e.key];
      if (c == null) continue;
      if (e.key == 'refs' && b.parts.every((p) => p.refs.isEmpty)) continue;
      add('col_${e.key}', doc.columns.any((x) => x.index == c && x.role == e.value));
    }
    final (rev, changes) = holdoutRevision(b, seed);
    final r = compareBoms(doc, readBom([rev], id: 'A'), null);
    add('complete', r.complete);
    final byL = {for (final row in r.rows) for (final p in row.singleParts) p.partNo: row};
    final byR = {for (final row in r.rows) for (final p in row.mergedParts) p.partNo: row};
    for (final e in changes.entries) {
      final row = e.value == 'added' ? byR[e.key] : byL[e.key];
      final got = row?.status;
      final want = expected[e.value]!;
      add('result_${e.value}', got == want);
      if (want != CheckStatus.pass) add('no_false_pass', got != CheckStatus.pass);
      if (want == CheckStatus.pass) add('no_false_ng', got != CheckStatus.ng && got != CheckStatus.unmatched);
      if (got != want && wrong.length < 15) wrong.add('seed $seed ${b.structure}/${b.language} ${e.key} ${e.value}: ${got?.name} ${row?.reasons}');
    }
  }
  String pct(Tally t, String m) => (t.total[m] ?? 0) == 0 ? '—' : '${(t.rate(m) * 100).toStringAsFixed(1)}% (${t.total[m]})';
  final metrics = {for (final t in [all, ...groups.values]) ...t.total.keys}.toList()..sort();
  stdout.writeln('| group | ${metrics.join(' | ')} |');
  stdout.writeln('|---|${metrics.map((_) => '---:').join('|')}|');
  for (final e in [MapEntry('all ($n)', all), ...(groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))]) {
    stdout.writeln('| ${e.key} | ${metrics.map((m) => pct(e.value, m)).join(' | ')} |');
  }
  stdout.writeln('\nFirst misses:');
  for (final w in wrong) {
    stdout.writeln('- $w');
  }
}
