// Real BOM pairs with confirmed answers, kept outside git under
// samples/realworld/<case>/: two BOM files whose names start with "a" and
// "b" (.xlsx / .csv / .txt), and expected.json:
//
//   {"lines": {"<part number of a>": "pass|ng|review|unmatched|substitute", …},
//    "confirmedBy": "name, date"}
//
// Reports, per case and in total, how many lines got the confirmed result,
// how many real differences passed (must be 0), and how many confirmed
// matches were called NG.
//
//   dart run tool/eval_realworld.dart [folder]
import 'dart:convert';
import 'dart:io';

import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/table_reader.dart';

void main(List<String> args) {
  final root = Directory(args.isEmpty ? 'samples/realworld' : args.first);
  if (!root.existsSync()) {
    stdout.writeln('No cases in ${root.path}. See the comment at the top of this file for the layout.');
    return;
  }
  var total = 0, right = 0, falsePass = 0, falseNg = 0;
  for (final dir in root.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path))) {
    final files = dir.listSync().whereType<File>().toList();
    File? pick(String p) => files.where((f) => f.uri.pathSegments.last.toLowerCase().startsWith(p) && !f.path.endsWith('.json')).firstOrNull;
    final a = pick('a'), b = pick('b'), exp = File('${dir.path}/expected.json');
    if (a == null || b == null || !exp.existsSync()) {
      stdout.writeln('- ${dir.path}: skipped (needs a*, b* and expected.json)');
      continue;
    }
    BomDocument read(File f, String id) => readBom(readTableBytes(f.readAsBytesSync(), f.path), file: f.uri.pathSegments.last, id: id);
    final r = compareBoms(read(a, 'S'), read(b, 'A'), null);
    final want = ((jsonDecode(exp.readAsStringSync()) as Map)['lines'] as Map).cast<String, String>();
    final byPn = {for (final row in r.rows) for (final p in row.singleParts) p.partNo: row};
    var ok = 0;
    for (final e in want.entries) {
      final got = byPn[e.key]?.status.name;
      total++;
      if (got == e.value) {
        ok++;
        right++;
      }
      if (e.value != 'pass' && got == 'pass') falsePass++;
      if (e.value == 'pass' && got == 'ng') falseNg++;
    }
    stdout.writeln('- ${dir.uri.pathSegments.where((s) => s.isNotEmpty).last}: $ok / ${want.length} as confirmed, complete ${r.complete}');
  }
  if (total > 0) stdout.writeln('\nTotal: $right / $total as confirmed; real differences passed: $falsePass; confirmed matches called NG: $falseNg');
}
