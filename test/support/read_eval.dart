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

/// Attribute columns: generator name → role.
const attrRoles = {'maker': BomRole.maker, 'mpn': BomRole.mpn, 'alt': BomRole.alternate, 'dnp': BomRole.dnp, 'level': BomRole.level};

const attrMetrics = ['col_maker', 'col_mpn', 'col_alt', 'col_dnp', 'col_level', 'attr_no_false', 'remark_not_desc', 'part_dnp', 'part_level', 'part_alt', 'kind'];

/// Generator kind → item kind.
const kindOf = {
  'resistor': ItemKind.resistor, 'capacitor': ItemKind.capacitor, 'inductor': ItemKind.inductor, 'ic': ItemKind.ic, 'diode': ItemKind.diode,
  'led': ItemKind.led, 'transistor': ItemKind.transistor, 'connector': ItemKind.connector, 'crystal': ItemKind.crystal,
  'mechanical': ItemKind.mechanical, 'packaging': ItemKind.packaging, 'pcb': ItemKind.pcb,
};

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
  // Attribute columns found where they are, and nowhere else.
  final attrCols = <int>{};
  for (final e in attrRoles.entries) {
    final c = g.columnOf[e.key];
    // An empty column says nothing and is not scored.
    if (c == null || !g.grid.rows.skip(g.layout.titleRows + (g.layout.headerless ? 0 : 1)).any((r) => r.length > c && r[c].isNotEmpty)) continue;
    attrCols.add(c);
    add('col_${e.key}', doc.columns.any((x) => x.index == c && x.role == e.value));
  }
  add('attr_no_false', !doc.columns.any((x) => x.role.attribute && x.role != BomRole.other && !attrCols.contains(x.index)));
  final remark = g.columnOf['remark'];
  if (remark != null) add('remark_not_desc', !descGot.contains(remark));
  final byPn = {for (final p in doc.parts) p.partNo: p};
  final recByPn = {for (final r in doc.records) r.partNo: r};
  for (final t in g.parts) {
    final p = byPn[t.partNo];
    add('part_found', p != null);
    add('part_qty', p != null && p.quantity == t.qty);
    add('part_refs', p != null && sortedRefs(p.refs).join(',') == sortedRefs(t.refs).join(','));
    add('part_row', p != null && p.rows.isNotEmpty && p.rows.first == t.row);
    final rec = recByPn[t.partNo];
    if (g.columnOf.containsKey('dnp')) add('part_dnp', rec != null && rec.dnp == t.dnp);
    if (g.columnOf.containsKey('level')) add('part_level', rec != null && rec.level == t.level);
    if (g.columnOf.containsKey('alt')) add('part_alt', rec != null && rec.alternates.join(',') == t.alternates.join(','));
    final want = kindOf[t.kind];
    if (want != null) {
      add('kind', rec != null && rec.kind == want);
      add('kind:${t.kind}', rec != null && rec.kind == want);
    }
  }
}
