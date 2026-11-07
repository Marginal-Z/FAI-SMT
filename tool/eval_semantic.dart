// Measures matching without part numbers or designators (purchase BOMs
// renumbered in another system): rules alone, and with the local embedding
// model's suggestions. Pairs found must be the true ones.
//
//   dart run tool/eval_semantic.dart [sheets]
import 'dart:io';
import 'dart:math';

import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/local_ai/local_ai.dart';
import 'package:smt_fai/core/local_ai/semantic_match.dart';
import 'package:smt_fai/core/table_reader.dart';

import '../test/support/bom_gen.dart';
import '../test/support/mutate.dart';

Future<void> main(List<String> args) async {
  final n = args.isEmpty ? 40 : int.parse(args.first);
  final dir = '${Platform.environment['HOME']}/.cache/smt-fai-dev/models';
  final ai = LlamaLocalModels(embeddingPath: '$dir/Qwen3-Embedding-0.6B-Q8_0.gguf', languagePath: '');
  var parts = 0, ruleRight = 0, ruleWrong = 0, semRight = 0, semWrong = 0, unpaired = 0;
  try {
    for (var seed = 0; seed < n; seed++) {
      final g = generateBom(seed);
      final r = Random(seed);
      // The same parts renumbered, without designators, in another language.
      final lang = ['zh', 'en', 'de', 'th'][r.nextInt(4)];
      final truth = <String, String>{};
      final rows = <List<String>>[['Part Number', 'Description', 'Qty']];
      for (final p in g.parts) {
        final pn = 'P${seed}_${r.nextInt(1 << 30)}';
        truth[p.partNo] = pn;
        final name = generatorKinds.contains(p.kind) ? nameOf(p.kind, lang) : p.name;
        rows.add([pn, '$name ${r.nextBool() ? rewriteUnits(p.spec) : p.spec}', '${p.qty}']);
      }
      final left = readBom([g.grid], id: 'S');
      final right = readBom([Grid('R', rows)], id: 'A');
      final first = compareBoms(left, right, null);
      final sug = await semanticSuggestions(first, ai);
      final report = compareBoms(left, right, null, semantic: sug);
      for (final row in report.rows) {
        if (row.single == null) continue;
        parts++;
        final want = truth[row.single!.partNo];
        final got = row.mergedParts.length == 1 ? row.mergedParts.single.partNo : null;
        final bySem = row.basis.kinds.contains('semantic');
        if (got == null) {
          unpaired++;
        } else if (got == want) {
          bySem ? semRight++ : ruleRight++;
        } else {
          bySem ? semWrong++ : ruleWrong++;
        }
        // Without a firm pairing nothing may pass.
        if (row.status == CheckStatus.pass) stderr.writeln('PASS without part number or designators: ${row.partNo}');
      }
    }
  } finally {
    await ai.dispose();
  }
  String pct(int x) => '${(x / parts * 100).toStringAsFixed(1)}%';
  stdout.writeln('$parts lines: paired by parameters ${pct(ruleRight)} right / ${pct(ruleWrong)} wrong; '
      'by the embedding model ${pct(semRight)} right / ${pct(semWrong)} wrong; unpaired ${pct(unpaired)}');
}
