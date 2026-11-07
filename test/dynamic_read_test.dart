// The unified model on generated BOMs with unknown layouts: properties that
// must hold for every sample, and accuracy floors that may only go up.
import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';

import 'support/bom_gen.dart';
import 'support/read_eval.dart';

void main() {
  const samples = 400;

  test('every record cites the row it was read from', () {
    for (var seed = 0; seed < samples; seed++) {
      final g = generateBom(seed);
      final doc = readBom([g.grid], file: 'gen.xlsx', id: 'G');
      final ids = <String>{};
      for (final rec in doc.records) {
        expect(ids.add(rec.id), isTrue, reason: 'seed $seed: duplicate id ${rec.id}');
        expect(rec.source.file, 'gen.xlsx');
        expect(rec.source.sheet, 'Sheet1');
        final row = g.grid.rows[rec.source.row - 1];
        // The raw cells are the row as read, every column kept.
        expect(rec.cells.take(row.length), row, reason: 'seed $seed row ${rec.source.row}');
        if (rec.partNo.isNotEmpty) expect(row, contains(rec.partNo), reason: 'seed $seed row ${rec.source.row}');
        for (final s in rec.sources) {
          expect(g.grid.rows[s.row - 1].any((c) => c.trim().isNotEmpty), isTrue, reason: 'seed $seed: empty source row ${s.row}');
        }
      }
    }
  });

  test('a BOM checked against itself: complete, every part the same', () {
    for (var seed = 0; seed < samples; seed++) {
      final g = generateBom(seed);
      final a = readBom([g.grid], file: 'x.xlsx', id: 'S');
      final b = readBom([g.grid], file: 'x.xlsx', id: 'A');
      final r = compareBoms(a, b, null);
      expect(r.complete, isTrue, reason: 'seed $seed: ${r.uncovered.take(3)}');
      expect(r.rows.every((x) => x.status == DiffStatus.same), isTrue, reason: 'seed $seed');
      expect(r.rows.length, a.parts.length);
    }
  });

  test('records are never lost between the file and the result', () {
    for (var seed = 0; seed < samples; seed += 2) {
      final a = readBom([generateBom(seed).grid], id: 'S');
      final b = readBom([generateBom(seed + 1).grid], id: 'A');
      final c = readBom([generateBom(seed + 7919).grid], id: 'B');
      final r = compareBoms(a, b, c);
      expect(r.complete, isTrue, reason: 'seed $seed: ${r.uncovered.take(3)}');
      final cited = [for (final x in r.rows) ...?x.single?.recordIds, for (final x in r.rows) ...?x.merged?.recordIds];
      expect(cited.length, a.records.length + b.records.length + c.records.length, reason: 'seed $seed: a record cited twice or missing');
    }
  });

  // Measured on 2026-11-07 (phase 1); see docs/architecture/phase-1.md.
  // Raise these as recognition improves; never lower them.
  test('recognition accuracy floors', () {
    final t = Tally();
    for (var seed = 0; seed < samples; seed++) {
      scoreSample(generateBom(seed), [t]);
    }
    const floors = {'read_ok': 1.0, 'col_qty': 0.98, 'col_refs': 0.98, 'col_partNo': 0.82, 'part_found': 0.82, 'part_row': 0.82, 'col_desc': 0.55};
    for (final e in floors.entries) {
      expect(t.rate(e.key), greaterThanOrEqualTo(e.value), reason: '${e.key}: ${t.rate(e.key)}');
    }
  });
}
