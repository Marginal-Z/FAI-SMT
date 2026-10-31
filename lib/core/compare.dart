/// Compare module: BOM against BOM, and BOM against one station list or the
/// pair A + B. Every mode produces the same editable result table, an
/// analysis report (the findings) and, for BOM ↔ BOM, a designator map.
library;

import 'checker.dart';
import 'discrepancies.dart';
import 'models.dart';
import 'refdes.dart';
import 'settings.dart';

enum CompareMode { bomBom, bomStation, bomStationAB }

/// Result table columns per mode (besides result, reason and note).
const compareColumns = {
  CompareMode.bomBom: ['pnA', 'pnB', 'descA', 'descB', 'qtyA', 'qtyB', 'refsA', 'refsB'],
  CompareMode.bomStation: ['pn', 'desc', 'bomQty', 'smtQty', 'bomRefs', 'smtRefs', 'smtPn', 'side', 'slot'],
  CompareMode.bomStationAB: ['pn', 'desc', 'bomQty', 'smtQty', 'bomRefs', 'smtRefs', 'smtPn', 'side', 'slot'],
};

/// One line of the result. The operator may change any cell, the result and
/// the note; the original values stay available for the export and undo.
class ResultRow {
  ResultRow({required this.id, required CheckCategory category, required Map<String, String> cells, this.reasons = const []})
      : category = category,
        originalCategory = category,
        cells = Map.of(cells),
        originalCells = Map.unmodifiable(cells);

  final String id;
  CheckCategory category;
  final CheckCategory originalCategory;
  final Map<String, String> cells;
  final Map<String, String> originalCells;
  final List<Reason> reasons;
  String note = '';

  bool cellEdited(String key) => (cells[key] ?? '') != (originalCells[key] ?? '');
  bool get categoryEdited => category != originalCategory;
  bool get edited => categoryEdited || note.isNotEmpty || cells.keys.any(cellEdited);

  void reset() {
    category = originalCategory;
    note = '';
    cells
      ..clear()
      ..addAll(originalCells);
  }
}

enum RefPairState { same, changed, onlyA, onlyB }

/// One designator in two BOMs.
class RefPair {
  const RefPair(this.ref, this.pnA, this.pnB, this.descA, this.descB);

  final String ref;
  final String pnA;
  final String pnB;
  final String descA;
  final String descB;

  RefPairState get state => pnA.isEmpty
      ? RefPairState.onlyB
      : pnB.isEmpty
          ? RefPairState.onlyA
          : pnA == pnB
              ? RefPairState.same
              : RefPairState.changed;
}

class CompareResult {
  CompareResult({required this.mode, required this.rows, required this.findings, this.refPairs = const [], this.files = const {}, DateTime? at})
      : at = at ?? DateTime.now();

  final CompareMode mode;
  final List<ResultRow> rows;

  /// Every inconsistency, with severity and an explanation.
  final List<Discrepancy> findings;
  final List<RefPair> refPairs;

  /// Slot label -> file name, for the report header.
  final Map<String, String> files;
  final DateTime at;

  List<String> get columns => compareColumns[mode]!;
  int count(CheckCategory c) => rows.where((r) => r.category == c).length;
  int get edited => rows.where((r) => r.edited).length;
}

String _join(Iterable<String> refs) => sortedRefs(refs).join(', ');

String _qty(double? q) => q == null ? '' : (q == q.roundToDouble() ? q.toInt().toString() : '$q');

String _normText(String s) => s.toUpperCase().replaceAll(RegExp(r'[\s_\-,，;；/()（）:：]+'), '');

String _normHeader(String s) => s.toUpperCase().replaceAll(RegExp(r'[\s_\-.:：()（）]'), '');

Reason? _excluded(BomItem b, CheckRules rules) {
  final text = '${b.name} ${b.spec}'.toUpperCase();
  for (final k in rules.excludeKeywords) {
    if (k.trim().isNotEmpty && text.contains(k.trim().toUpperCase())) return Reason('excl_keyword', {'kw': k.trim()}, true);
  }
  for (final p in rules.excludePrefixes) {
    if (p.trim().isNotEmpty && b.partNo.startsWith(p.trim().toUpperCase())) return Reason('excl_prefix', {'prefix': p.trim()}, true);
  }
  return null;
}

/// Checks inside one BOM: quantity against designators, a designator twice
/// on one line, a designator on two lines.
Map<String, List<Reason>> _selfCheck(List<BomItem> bom, String side, CheckRules rules) {
  final out = <String, List<Reason>>{};
  final owners = <String, Set<String>>{};
  for (final b in bom) {
    for (final r in b.refs) {
      if (!rules.isIgnoredRef(r)) owners.putIfAbsent(r, () => {}).add(b.partNo);
    }
  }
  for (final b in bom) {
    final reasons = <Reason>[];
    final refs = b.refs.where((r) => !rules.isIgnoredRef(r)).toList();
    final set = refs.toSet();
    if (b.qty != null && set.isNotEmpty && (b.qty! - set.length).abs() > 1e-6) {
      reasons.add(Reason('cmp_qty_refs', {'side': side, 'qty': _qty(b.qty), 'n': '${set.length}'}));
    }
    if (set.length != refs.length) {
      final seen = <String>{};
      reasons.add(Reason('cmp_dup_refs', {'side': side, 'refs': _join(refs.where((r) => !seen.add(r)))}));
    }
    final shared = set.where((r) => owners[r]!.length > 1).toSet();
    if (shared.isNotEmpty) {
      final others = shared.expand((r) => owners[r]!).where((p) => p != b.partNo).toSet();
      reasons.add(Reason('cmp_ref_shared', {'side': side, 'refs': _join(shared), 'pn': others.join(', ')}));
    }
    if (reasons.isNotEmpty) out[b.partNo] = reasons;
  }
  return out;
}

/// Compares two BOMs line by line and designator by designator.
///
/// Lines pair up by part number; a part number found in only one BOM pairs
/// with one in the other BOM when the two are registered alternates (BOM
/// column or the user's table) or when they sit on mostly the same
/// designators (a part-number change). Everything that differs — presence,
/// quantity, designators, description, alternates and every other column
/// both files share — becomes a reason on the row and a finding.
/// Descriptions and alternates are compared only when both files have
/// such columns ([compareDescriptions], [compareAlternates]).
CompareResult compareBoms(
  List<BomItem> a,
  List<BomItem> b,
  CheckRules rules, {
  List<ParseIssue> issuesA = const [],
  List<ParseIssue> issuesB = const [],
  Map<String, String> files = const {},
  bool compareDescriptions = true,
  bool compareAlternates = true,
}) {
  final byA = {for (final x in a) x.partNo: x};
  final byB = {for (final x in b) x.partNo: x};
  List<String> refsOf(BomItem? x) => x == null ? const [] : x.refs.where((r) => !rules.isIgnoredRef(r)).toList();

  // ---- Designator ownership in each BOM.
  final ownerA = <String, String>{}, ownerB = <String, String>{};
  for (final x in a) {
    for (final r in refsOf(x)) {
      ownerA.putIfAbsent(r, () => x.partNo);
    }
  }
  for (final x in b) {
    for (final r in refsOf(x)) {
      ownerB.putIfAbsent(r, () => x.partNo);
    }
  }

  // ---- Pair lines.
  bool alternates(BomItem x, BomItem y) {
    final subs = rules.substitutes.map((k, v) => MapEntry(k.toUpperCase(), v.map((e) => e.toUpperCase()).toSet()));
    return x.alternates.contains(y.partNo) ||
        y.alternates.contains(x.partNo) ||
        (subs[x.partNo]?.contains(y.partNo) ?? false) ||
        (subs[y.partNo]?.contains(x.partNo) ?? false);
  }

  final pairs = <(BomItem?, BomItem?, bool)>[]; // (A, B, registered alternate)
  final onlyA = [for (final x in a) if (!byB.containsKey(x.partNo)) x];
  final onlyB = [for (final x in b) if (!byA.containsKey(x.partNo)) x];
  final usedB = <BomItem>{};
  final pairedA = <BomItem, (BomItem, bool)>{};
  for (final x in onlyA) {
    final sx = refsOf(x).toSet();
    BomItem? pick;
    var alt = false;
    var bestOverlap = 0.0;
    for (final y in onlyB) {
      if (usedB.contains(y)) continue;
      final sy = refsOf(y).toSet();
      final union = sx.union(sy).length;
      final overlap = union == 0 ? 0.0 : sx.intersection(sy).length / union;
      final isAlt = alternates(x, y);
      if (isAlt && (overlap > 0 || sx.isEmpty)) {
        pick = y;
        alt = true;
        break;
      }
      if (overlap >= 0.6 && overlap > bestOverlap) {
        bestOverlap = overlap;
        pick = y;
      }
    }
    if (pick != null) {
      usedB.add(pick);
      pairedA[x] = (pick, alt);
    }
  }
  for (final x in a) {
    final y = byB[x.partNo];
    if (y != null) {
      pairs.add((x, y, false));
    } else if (pairedA.containsKey(x)) {
      pairs.add((x, pairedA[x]!.$1, pairedA[x]!.$2));
    } else {
      pairs.add((x, null, false));
    }
  }
  for (final y in onlyB) {
    if (!usedB.contains(y)) pairs.add((null, y, false));
  }

  // ---- Columns both BOMs share beyond the recognised ones.
  final headersA = {for (final x in a) ...x.extras.keys};
  final headersB = {for (final x in b) ...x.extras.keys};
  final sharedFields = <(String, String)>[];
  for (final ha in headersA) {
    for (final hb in headersB) {
      if (_normHeader(ha) == _normHeader(hb)) {
        sharedFields.add((ha, hb));
        break;
      }
    }
  }

  final selfA = _selfCheck(a, 'A', rules);
  final selfB = _selfCheck(b, 'B', rules);

  final rows = <ResultRow>[];
  var n = 0;
  for (final (x, y, registeredAlt) in pairs) {
    final reasons = <Reason>[];
    final ra = refsOf(x).toSet(), rb = refsOf(y).toSet();
    if (x == null) {
      reasons.add(Reason('cmp_only_b', {'refs': _join(rb)}));
    } else if (y == null) {
      reasons.add(Reason('cmp_only_a', {'refs': _join(ra)}));
    } else {
      if (x.partNo != y.partNo) {
        reasons.add(registeredAlt
            ? Reason('cmp_alt_swap', {'a': x.partNo, 'pn': y.partNo, 'refs': _join(ra.intersection(rb))}, true)
            : Reason('cmp_pn_changed', {'a': x.partNo, 'pn': y.partNo, 'refs': _join(ra.intersection(rb))}));
      }
      if (x.qty != null && y.qty != null && (x.qty! - y.qty!).abs() > 1e-6) {
        reasons.add(Reason('cmp_qty', {'a': _qty(x.qty), 'b': _qty(y.qty)}));
      }
      final da = x.description, db = y.description;
      if (compareDescriptions && _normText(da) != _normText(db) && (da.isNotEmpty || db.isNotEmpty)) {
        reasons.add(Reason('cmp_desc', {'a': da, 'b': db}));
      }
      final altA = x.alternates.toSet(), altB = y.alternates.toSet();
      if (compareAlternates && (altA.length != altB.length || !altA.containsAll(altB))) {
        reasons.add(Reason('cmp_alt_diff', {'a': altA.join(', '), 'b': altB.join(', ')}));
      }
      for (final (ha, hb) in sharedFields) {
        final va = x.extras[ha] ?? '', vb = y.extras[hb] ?? '';
        if (_normText(va) != _normText(vb)) reasons.add(Reason('cmp_field', {'field': ha, 'a': va, 'b': vb}));
      }
    }
    // Designators: gone from B (or moved to another part), new in B.
    final pnB = y?.partNo, pnA = x?.partNo;
    final removed = ra.difference(rb), added = rb.difference(ra);
    final moved = <String, List<String>>{}, from = <String, List<String>>{};
    final gone = <String>[], fresh = <String>[];
    for (final r in removed) {
      final o = ownerB[r];
      if (o != null && o != pnB) {
        moved.putIfAbsent(o, () => []).add(r);
      } else {
        gone.add(r);
      }
    }
    for (final r in added) {
      final o = ownerA[r];
      if (o != null && o != pnA) {
        from.putIfAbsent(o, () => []).add(r);
      } else {
        fresh.add(r);
      }
    }
    if (x != null && y != null) {
      if (gone.isNotEmpty) reasons.add(Reason('cmp_refs_removed', {'refs': _join(gone)}));
      if (fresh.isNotEmpty) reasons.add(Reason('cmp_refs_added', {'refs': _join(fresh)}));
    }
    for (final e in moved.entries) {
      reasons.add(Reason('cmp_refs_moved', {'refs': _join(e.value), 'pn': e.key}));
    }
    for (final e in from.entries) {
      reasons.add(Reason('cmp_refs_from', {'refs': _join(e.value), 'pn': e.key}));
    }
    if (x != null) reasons.addAll(selfA[x.partNo] ?? const []);
    if (y != null) reasons.addAll(selfB[y.partNo] ?? const []);

    final excl = (x == null ? null : _excluded(x, rules)) ?? (y == null ? null : _excluded(y, rules));
    final CheckCategory category;
    final List<Reason> shown;
    if (excl != null) {
      category = CheckCategory.excluded;
      // Still listed, as notes, so nothing is hidden.
      shown = [excl, for (final r in reasons) Reason(r.code, r.args, true)];
    } else {
      shown = reasons;
      category = reasons.any((r) => !r.info)
          ? CheckCategory.ng
          : reasons.any((r) => r.code == 'cmp_alt_swap')
              ? CheckCategory.substitute
              : CheckCategory.pass;
    }
    rows.add(ResultRow(
      id: 'r${n++}',
      category: category,
      reasons: shown,
      cells: {
        'pnA': x?.partNo ?? '',
        'pnB': y?.partNo ?? '',
        'descA': x?.description ?? '',
        'descB': y?.description ?? '',
        'qtyA': _qty(x?.qty),
        'qtyB': _qty(y?.qty),
        'refsA': sortedRefs(ra).join(','),
        'refsB': sortedRefs(rb).join(','),
      },
    ));
  }

  // ---- Designator map.
  final allRefs = sortedRefs({...ownerA.keys, ...ownerB.keys});
  final refPairs = [
    for (final r in allRefs)
      RefPair(r, ownerA[r] ?? '', ownerB[r] ?? '', byA[ownerA[r]]?.description ?? '', byB[ownerB[r]]?.description ?? ''),
  ];

  final findings = <Discrepancy>[];
  for (final row in rows) {
    final subject = row.cells['pnA']!.isNotEmpty ? row.cells['pnA']! : row.cells['pnB']!;
    for (final r in row.reasons) {
      findings.add(Discrepancy(
        severity: severityOf(r),
        source: switch (r.code) {
          'cmp_only_a' => Source.bomA,
          'cmp_only_b' => Source.bomB,
          _ when r.args['side'] == 'A' => Source.bomA,
          _ when r.args['side'] == 'B' => Source.bomB,
          _ => Source.cross,
        },
        code: r.code,
        subject: subject,
        args: r.args,
        refs: r.args['refs']?.split(', ').where((e) => e.isNotEmpty).toList() ?? const [],
      ));
    }
  }
  findings.addAll(_parseFindings(issuesA, Source.bomA));
  findings.addAll(_parseFindings(issuesB, Source.bomB));
  _sort(findings);
  return CompareResult(mode: CompareMode.bomBom, rows: rows, findings: findings, refPairs: refPairs, files: files);
}

List<Discrepancy> _parseFindings(List<ParseIssue> issues, Source source) => [
      for (final i in issues)
        Discrepancy(
          severity: Severity.warning,
          source: source,
          code: 'd_${i.code}',
          subject: i.row == null ? '-' : '#${i.row}',
          args: {'row': '${i.row ?? ''}', 'detail': i.detail},
        ),
    ];

void _sort(List<Discrepancy> out) {
  const order = {Severity.error: 0, Severity.warning: 1, Severity.info: 2};
  out.sort((a, b) {
    final s = order[a.severity]!.compareTo(order[b.severity]!);
    return s != 0 ? s : compareRefs(a.subject, b.subject);
  });
}

/// BOM against one station list (sides taken from its side column, if any)
/// or against lists A and B, with the station engine ([runCheck]).
CompareResult compareBomStations(
  List<BomItem> bom,
  List<StationItem> stations,
  CheckRules rules, {
  required CompareMode mode,
  List<ParseIssue> bomIssues = const [],
  List<ParseIssue> stationAIssues = const [],
  List<ParseIssue> stationBIssues = const [],
  Map<String, String> files = const {},
}) {
  final outcome = runCheck(
    bom: bom,
    stations: stations,
    rules: rules,
    bomIssues: bomIssues,
    stationAIssues: stationAIssues,
    stationBIssues: stationBIssues,
  );
  final twoSides = mode == CompareMode.bomStationAB || stations.any((s) => s.side == StationSide.b);
  var n = 0;
  final rows = [
    for (final r in outcome.report.rows)
      ResultRow(
        id: 'r${n++}',
        category: r.category,
        reasons: r.reasons,
        cells: {
          'pn': r.partNo,
          'desc': r.description,
          'bomQty': r.bomQty == null ? '' : _qty(r.bomQty),
          'smtQty': r.smtQty?.toString() ?? '',
          'bomRefs': r.bomRefs.map((m) => m.ref).join(','),
          'smtRefs': r.smtRefs.map((m) => m.ref).join(','),
          'smtPn': r.smtPartNos.join(','),
          'side': twoSides ? (r.sides.toList()..sort((x, y) => x.index - y.index)).map((s) => s == StationSide.a ? 'A' : 'B').join('/') : '',
          'slot': r.slots.join(','),
        },
      ),
  ];
  return CompareResult(mode: mode, rows: rows, findings: outcome.findings, files: files);
}
