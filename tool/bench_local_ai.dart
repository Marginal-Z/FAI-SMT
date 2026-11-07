// Benchmarks a local language model on two tasks against known answers:
// item kinds of hand-written BOM lines, and column roles of generated
// BOMs (program alone, model alone, program checked by the model).
//
//   dart run tool/bench_local_ai.dart <model.gguf> [think] [columns-samples]
import 'dart:io';

import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/classify.dart';
import 'package:smt_fai/core/local_ai/column_assist.dart';
import 'package:smt_fai/core/local_ai/local_ai.dart';

import '../test/support/bom_gen.dart';
import 'bench_items.dart';

const kinds = ['resistor', 'capacitor', 'inductor', 'ferrite', 'diode', 'led', 'transistor', 'ic', 'crystal', 'connector', 'switch', 'relay', 'fuse', 'mechanical', 'packaging', 'consumable', 'other'];

Future<void> main(List<String> args) async {
  final path = args.first;
  final think = args.length > 1 && args[1] == 'think';
  final samples = args.length > 2 ? int.parse(args[2]) : 60;
  final ai = LlamaLocalModels(embeddingPath: '', languagePath: path, thinking: think, languageName: path.split('/').last);
  try {
    // Item kinds: model and rules side by side.
    var model = 0, rules = 0;
    final sw = Stopwatch()..start();
    final wrong = <String>[];
    for (final (text, want) in benchItems) {
      final r = await ai.structured(
        system: 'You are an electronics engineer. Read the BOM line, name the part, then give its kind. MLCC is a ceramic capacitor; nF/uF/pF are capacitance; ohm, K and R values are resistance; uH is inductance; a part number alone may be a transistor, IC or diode.',
        user: 'BOM line: $text',
        schema: {
          'type': 'object',
          'properties': {
            'part': {'type': 'string'},
            'kind': {'type': 'string', 'enum': kinds},
          },
          'required': ['part', 'kind'],
          'additionalProperties': false,
        },
        maxTokens: 80,
      );
      if (r['kind'] == want) {
        model++;
      } else {
        wrong.add('$text → ${r['kind']}');
      }
      final k = classifyItem(text, const []).$1.name.replaceAll('switchKind', 'switch');
      if (k == want) rules++;
    }
    final n = benchItems.length;
    stdout.writeln('items: model ${(model / n * 100).toStringAsFixed(1)}%  rules ${(rules / n * 100).toStringAsFixed(1)}%  ($n lines, ${(sw.elapsedMilliseconds / n).round()} ms/line)');
    stdout.writeln('  model wrong: ${wrong.join('; ')}');

    // Column roles on generated BOMs.
    var cols = 0, progOk = 0, modelOk = 0, bothOk = 0, failed = 0;
    sw.reset();
    for (var seed = 50000; seed < 50000 + samples; seed++) {
      final g = generateBom(seed);
      final doc = readBom([g.grid]);
      final truth = <int, BomRole>{
        for (final e in g.columnOf.entries)
          e.value: switch (e.key) {
            'partNo' => BomRole.partNo,
            'qty' => BomRole.quantity,
            'refs' => BomRole.refs,
            'desc' || 'name' || 'spec' => BomRole.description,
            'serial' => BomRole.serial,
            'maker' => BomRole.maker,
            'mpn' => BomRole.mpn,
            'alt' => BomRole.alternate,
            'level' => BomRole.level,
            'dnp' => BomRole.dnp,
            _ => BomRole.other,
          },
      };
      Map<int, BomRole> answer;
      try {
        answer = await askColumnRoles(g.grid, doc, ai);
      } on LocalAiException {
        // A failed answer leaves the program's reading alone.
        failed++;
        answer = const {};
      }
      final checked = reconcileColumns(g.grid, doc, answer);
      final checkedDoc = readBom([g.grid], overrides: {doc.sheet: checked.overrides});
      for (final e in truth.entries) {
        // Empty columns carry no answer.
        final hasValues = g.grid.rows.any((r) => r.length > e.key && r[e.key].isNotEmpty);
        if (!hasValues) continue;
        cols++;
        BomRole roleIn(BomDocument d) => d.columns.where((c) => c.index == e.key).map((c) => c.role).firstOrNull ?? BomRole.other;
        if (roleIn(doc) == e.value) progOk++;
        if (answer[e.key] == e.value) modelOk++;
        if (roleIn(checkedDoc) == e.value) bothOk++;
      }
    }
    stdout.writeln('columns: program ${(progOk / cols * 100).toStringAsFixed(1)}%  model ${(modelOk / cols * 100).toStringAsFixed(1)}%  program+model ${(bothOk / cols * 100).toStringAsFixed(1)}%  ($cols columns, $samples sheets, $failed failed answers, ${(sw.elapsedMilliseconds / samples).round()} ms/sheet)');
  } finally {
    await ai.dispose();
  }
}
