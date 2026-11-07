// Scores the BOM reader against generated sheets with known answers.
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/refdes.dart';

import 'bom_gen.dart';

/// Hits and totals per metric, for one group of samples.
class Tally {
  final hit = <String, int>{};
  final total = <String, int>{};

  void add(String metric, bool ok) {
    total[metric] = (total[metric] ?? 0) + 1;
    if (ok) hit[metric] = (hit[metric] ?? 0) + 1;
  }

  double rate(String metric) => (total[metric] ?? 0) == 0 ? 1 : (hit[metric] ?? 0) / total[metric]!;
}

const metrics = ['col_partNo', 'col_qty', 'col_refs', 'col_desc', 'part_found', 'part_qty', 'part_refs', 'part_row', 'read_ok'];

/// Scores one sample into the given tallies.
void scoreSample(GeneratedBom g, List<Tally> into) {
  void add(String m, bool ok) {
    for (final t in into) {
      t.add(m, ok);
    }
  }

  final BomDocument doc;
  try {
    doc = readBom([g.grid], file: 'gen.xlsx', id: 'G');
  } on BomReadException {
    add('read_ok', false);
    for (final m in metrics.where((m) => m != 'read_ok')) {
      add(m, false);
    }
    return;
  }
  add('read_ok', true);
  int? colOf(BomRole role) => doc.column(role)?.index;
  add('col_partNo', colOf(BomRole.partNo) == g.columnOf['partNo']);
  add('col_qty', colOf(BomRole.quantity) == g.columnOf['qty']);
  add('col_refs', colOf(BomRole.refs) == g.columnOf['refs']);
  final descWant = {for (final f in ['desc', 'name', 'spec']) ?g.columnOf[f]};
  final descGot = {for (final c in doc.columns) if (c.role == BomRole.description) c.index};
  add('col_desc', descGot.length == descWant.length && descGot.containsAll(descWant));
  final byPn = {for (final p in doc.parts) p.partNo: p};
  for (final t in g.parts) {
    final p = byPn[t.partNo];
    add('part_found', p != null);
    add('part_qty', p != null && p.quantity == t.qty);
    add('part_refs', p != null && sortedRefs(p.refs).join(',') == sortedRefs(t.refs).join(','));
    add('part_row', p != null && p.rows.isNotEmpty && p.rows.first == t.row);
  }
}
