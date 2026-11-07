// Reader accuracy on generated BOMs, per layout category and language.
//
//   dart run tool/eval_read.dart [samples]
import 'dart:io';

import '../test/support/bom_gen.dart';
import '../test/support/read_eval.dart';

void main(List<String> args) {
  final n = args.isEmpty ? 1000 : int.parse(args.first);
  final all = Tally();
  final groups = <String, Tally>{};
  for (var seed = 0; seed < n; seed++) {
    final g = generateBom(seed);
    scoreSample(g, [
      all,
      groups.putIfAbsent('layout ${g.layout.category}', Tally.new),
      groups.putIfAbsent('lang ${g.layout.language}', Tally.new),
      groups.putIfAbsent('desc ${g.layout.splitDescription ? 'split' : 'single'}', Tally.new),
      groups.putIfAbsent('pn style ${g.layout.partNoStyle}', Tally.new),
    ]);
  }
  String pct(double v) => '${(v * 100).toStringAsFixed(1)}%'.padLeft(7);
  stdout.writeln('| group | ${metrics.join(' | ')} |');
  stdout.writeln('|---|${metrics.map((_) => '---:').join('|')}|');
  for (final e in [MapEntry('all ($n)', all), ...(groups.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))]) {
    stdout.writeln('| ${e.key} | ${metrics.map((m) => pct(e.value.rate(m))).join(' | ')} |');
  }
}
