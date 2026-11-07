// A generated BOM against a second one with a new layout, another language
// and one injected change per part: the check must give the result each
// change calls for. Meaning-preserving changes must PASS; no real change
// may ever PASS.
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';

import 'support/mutate.dart';

void main() {
  test('injected changes give the expected results', () {
    final total = <String, int>{}, right = <String, int>{};
    var falsePass = 0, realChanges = 0, falseNg = 0, kept = 0;
    final wrong = <String>[];
    for (var seed = 0; seed < 300; seed++) {
      final m = mutateBom(seed);
      final left = readBom([m.left.grid], file: 'left.xlsx', id: 'S');
      final rightDoc = readBom([m.right], file: 'right.xlsx', id: 'A');
      final r = compareBoms(left, rightDoc, null);
      expect(r.complete, isTrue, reason: 'seed $seed');
      final byLeft = {for (final row in r.rows) for (final p in row.singleParts) p.partNo: row};
      final byRight = {for (final row in r.rows) for (final p in row.mergedParts) p.partNo: row};
      for (final e in m.changes.entries) {
        final want = expectedFor[e.value]!;
        final row = byLeft[e.key];
        final got = row?.status;
        total[e.value] = (total[e.value] ?? 0) + 1;
        if (got == want) {
          right[e.value] = (right[e.value] ?? 0) + 1;
        } else if (wrong.length < 12) {
          wrong.add('seed $seed ${e.key} ${e.value}: ${got?.name} ${row?.reasons} ${row?.differences.map((f) => '${f.key}[${f.single}|${f.merged}]')}');
        }
        if (want != CheckStatus.pass) {
          realChanges++;
          if (got == CheckStatus.pass) falsePass++;
        } else {
          // Meaning kept: PASS, or REVIEW where wording cannot be
          // confirmed; never NG.
          kept++;
          if (got == CheckStatus.ng || got == CheckStatus.unmatched) falseNg++;
        }
      }
      for (final pn in m.addedPartNos) {
        total['added'] = (total['added'] ?? 0) + 1;
        if (byRight[pn]?.status == CheckStatus.unmatched) right['added'] = (right['added'] ?? 0) + 1;
      }
    }
    final rates = {for (final k in total.keys) k: (right[k] ?? 0) / total[k]!};
    // ignore: avoid_print
    print('injected-change results: ${[for (final e in rates.entries) '${e.key} ${(e.value * 100).toStringAsFixed(1)}% of ${total[e.key]}'].join(', ')}; false PASS $falsePass of $realChanges; NG/unmatched on unchanged meaning $falseNg of $kept');
    for (final w in wrong) {
      // ignore: avoid_print
      print(w);
    }
    // No real change may pass unnoticed, and a change that keeps the
    // meaning is never called a difference.
    expect(falsePass, 0);
    expect(falseNg, 0);
    // Exact results, per kind of change (REVIEW counts against the PASS
    // kinds here); floors measured in phase 4.
    const floors = {'qty': 0.99, 'param': 0.99, 'drop_ref': 0.99, 'maker': 0.99, 'deleted': 0.99, 'added': 0.99, 'none': 0.9, 'units': 0.9, 'split_line': 0.9, 'renumbered': 0.9, 'renumbered_alt': 0.9};
    for (final e in rates.entries) {
      expect(e.value, greaterThanOrEqualTo(floors[e.key]!), reason: e.key);
    }
  });
}
