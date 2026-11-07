/// Compares A-BOM (+ B-BOM) merged against the single BOM, part number by
/// part number.
///
/// Rules: the description passes when its letters, digits and parameter
/// symbols are the same (Chinese wording may differ: a character more or
/// less, a longer or shorter name); every other column both files have must
/// be exactly the same, and so must the quantity and the designators.
library;

import 'bom.dart';
import 'refdes.dart';

enum DiffStatus { same, different, onlySingle, onlyMerged }

/// A highlighted range [start, end) in a displayed value.
typedef Span = (int, int);

class FieldCompare {
  FieldCompare({
    required this.key,
    required this.header,
    required this.single,
    required this.merged,
    required this.equal,
    this.singleSpans = const [],
    this.mergedSpans = const [],
  });

  /// `description`, `quantity`, `refs` or `col:<label>`.
  final String key;

  /// Column header of the single BOM (shown for other columns).
  final String header;
  final String single;
  final String merged;
  final bool equal;
  final List<Span> singleSpans;
  final List<Span> mergedSpans;
}

class CompareRow {
  CompareRow({
    required this.partNo,
    required this.status,
    required this.single,
    required this.merged,
    required this.sources,
    required this.fields,
    required this.missingRefs,
    required this.extraRefs,
    required this.movedRefs,
  });

  final String partNo;
  final DiffStatus status;
  final BomPart? single;
  final BomPart? merged;

  /// Which of A / B hold the part.
  final List<String> sources;
  final List<FieldCompare> fields;

  /// Designators the single BOM has and A+B lack, and the reverse.
  final List<String> missingRefs;
  final List<String> extraRefs;

  /// A designator listed under another part number on the other side.
  final Map<String, String> movedRefs;

  FieldCompare? field(String key) => fields.where((f) => f.key == key).firstOrNull;
  Iterable<FieldCompare> get differences => fields.where((f) => !f.equal);
  String get description => single?.description ?? merged?.description ?? '';
}

class CompareReport {
  CompareReport({
    required this.rows,
    required this.compared,
    required this.singleOnlyColumns,
    required this.mergedOnlyColumns,
    required this.at,
    this.uncovered = const [],
  });

  final List<CompareRow> rows;

  /// Other columns compared: label → header.
  final Map<String, String> compared;

  /// Other columns only one side has (not compared).
  final List<String> singleOnlyColumns;
  final List<String> mergedOnlyColumns;
  final DateTime at;

  /// Records of the input files that no result row accounts for. Must be
  /// empty; anything else is a fault and the check is not complete.
  final List<String> uncovered;

  bool get complete => uncovered.isEmpty;

  int count(DiffStatus s) => rows.where((r) => r.status == s).length;
}

// ----------------------------------------------------------- description rule

final _paramToken = RegExp(r'[A-Za-z0-9.±%Ω+\-/~]+');

/// Letters, digits and parameter symbols of a description, with their
/// positions; Chinese and separators are skipped.
List<(String, int, int)> paramTokens(String text) {
  final out = <(String, int, int)>[];
  for (final m in _paramToken.allMatches(text)) {
    var s = m.start, e = m.end;
    // Separating punctuation at either end is not part of a parameter.
    while (s < e && '/.-~'.contains(text[s])) {
      s++;
    }
    while (e > s && '/.~'.contains(text[e - 1])) {
      e--;
    }
    if (e > s) out.add((text.substring(s, e), s, e));
  }
  return out;
}

/// Tokens of [a] not matched by a token of [b] (as a multiset), as spans.
List<Span> _unmatched(List<(String, int, int)> a, List<(String, int, int)> b) {
  final pool = <String, int>{};
  for (final t in b) {
    pool[t.$1] = (pool[t.$1] ?? 0) + 1;
  }
  final out = <Span>[];
  for (final t in a) {
    final n = pool[t.$1] ?? 0;
    if (n > 0) {
      pool[t.$1] = n - 1;
    } else {
      out.add((t.$2, t.$3));
    }
  }
  return out;
}

FieldCompare compareDescription(String single, String merged, {String header = ''}) {
  final a = paramTokens(single), b = paramTokens(merged);
  final sa = _unmatched(a, b), sb = _unmatched(b, a);
  return FieldCompare(key: 'description', header: header, single: single, merged: merged, equal: sa.isEmpty && sb.isEmpty, singleSpans: sa, mergedSpans: sb);
}

/// Exact comparison with the differing characters marked (longest common
/// subsequence; whole values for long text).
FieldCompare compareExact(String key, String header, String single, String merged) {
  if (single == merged) return FieldCompare(key: key, header: header, single: single, merged: merged, equal: true);
  final (sa, sb) = charDiff(single, merged);
  return FieldCompare(key: key, header: header, single: single, merged: merged, equal: false, singleSpans: sa, mergedSpans: sb);
}

(List<Span>, List<Span>) charDiff(String a, String b) {
  if (a.length * b.length > 40000) return ([if (a.isNotEmpty) (0, a.length)], [if (b.isNotEmpty) (0, b.length)]);
  final n = a.length, m = b.length;
  final dp = List.generate(n + 1, (_) => List<int>.filled(m + 1, 0));
  for (var i = n - 1; i >= 0; i--) {
    for (var j = m - 1; j >= 0; j--) {
      dp[i][j] = a[i] == b[j] ? dp[i + 1][j + 1] + 1 : (dp[i + 1][j] >= dp[i][j + 1] ? dp[i + 1][j] : dp[i][j + 1]);
    }
  }
  final inA = List<bool>.filled(n, false), inB = List<bool>.filled(m, false);
  var i = 0, j = 0;
  while (i < n && j < m) {
    if (a[i] == b[j]) {
      inA[i] = inB[j] = true;
      i++;
      j++;
    } else if (dp[i + 1][j] >= dp[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  List<Span> spans(List<bool> kept) {
    final out = <Span>[];
    int? start;
    for (var k = 0; k <= kept.length; k++) {
      final diff = k < kept.length && !kept[k];
      if (diff && start == null) start = k;
      if (!diff && start != null) {
        out.add((start, k));
        start = null;
      }
    }
    return out;
  }

  return (spans(inA), spans(inB));
}

// ------------------------------------------------------------------- merging

/// A-BOM and B-BOM as one list: the same part number in both is one part
/// (quantities added, designators joined). [relabelA] / [relabelB] rename
/// other-column labels (see [matchColumns]).
(List<BomPart>, Map<String, List<String>>) mergeBoms(BomDocument a, BomDocument? b, {Map<String, String> relabelA = const {}, Map<String, String> relabelB = const {}}) {
  final byPn = <String, BomPart>{};
  final sources = <String, List<String>>{};
  final order = <BomPart>[];
  for (final (tag, file, relabel) in [('A', a, relabelA), if (b != null) ('B', b, relabelB)]) {
    for (final p in file.parts) {
      final extra = {for (final e in p.extra.entries) relabel[e.key] ?? e.key: e.value};
      final existing = byPn[p.partNo];
      if (existing == null) {
        final copy = BomPart(p.partNo, description: p.description, quantity: p.quantity, refs: [...p.refs], extra: extra, sources: [...p.sources], recordIds: [...p.recordIds], dnp: p.dnp, alternates: p.alternates, kind: p.kind);
        byPn[p.partNo] = copy;
        order.add(copy);
        sources[p.partNo] = [tag];
        continue;
      }
      existing.refs.addAll(p.refs);
      existing.sources.addAll(p.sources);
      existing.recordIds.addAll(p.recordIds);
      if (p.quantity != null) existing.quantity = (existing.quantity ?? 0) + p.quantity!;
      if (existing.description.isEmpty) existing.description = p.description;
      for (final e in extra.entries) {
        if ((existing.extra[e.key] ?? '').isEmpty) existing.extra[e.key] = e.value;
      }
      if (!sources[p.partNo]!.contains(tag)) sources[p.partNo]!.add(tag);
    }
  }
  return (order, sources);
}

/// Other columns of [f] whose header the single BOM does not have (another
/// name, or no header at all) matched to a single-BOM column by content:
/// most parts both files list carry the same value in both. Label of [f]
/// → label of the single BOM.
Map<String, String> matchColumns(BomDocument single, BomDocument f) {
  final singleLabels = {for (final c in single.others) c.label};
  final byPn = {for (final p in single.parts) p.partNo: p};
  final taken = {for (final c in f.others) if (singleLabels.contains(c.label)) c.label};
  final out = <String, String>{};
  for (final c in f.others) {
    if (singleLabels.contains(c.label)) continue;
    String? best;
    var bestShare = 0.0;
    for (final label in singleLabels.difference(taken)) {
      var shared = 0, same = 0;
      for (final p in f.parts) {
        final v = p.extra[c.label] ?? '', w = byPn[p.partNo]?.extra[label] ?? '';
        if (v.isEmpty || w.isEmpty) continue;
        shared++;
        if (v == w) same++;
      }
      final share = shared == 0 ? 0.0 : same / shared;
      if (shared >= 2 && share >= 0.6 && share > bestShare) {
        best = label;
        bestShare = share;
      }
    }
    if (best != null) {
      out[c.label] = best;
      taken.add(best);
    }
  }
  return out;
}

// ----------------------------------------------------------------- comparing

CompareReport compareBoms(BomDocument single, BomDocument a, BomDocument? b) {
  final relabelA = matchColumns(single, a);
  final relabelB = b == null ? const <String, String>{} : matchColumns(single, b);
  final (merged, sources) = mergeBoms(a, b, relabelA: relabelA, relabelB: relabelB);
  final mergedByPn = {for (final p in merged) p.partNo: p};
  final singleByPn = {for (final p in single.parts) p.partNo: p};
  Set<String> labels(BomDocument f, Map<String, String> relabel) => {for (final c in f.others) relabel[c.label] ?? c.label};
  final labelsA = labels(a, relabelA);
  final labelsB = b == null ? const <String>{} : labels(b, relabelB);

  // Other columns both sides have.
  final mergedLabels = {
    for (final c in a.others) relabelA[c.label] ?? c.label: c.header,
    if (b != null)
      for (final c in b.others) relabelB[c.label] ?? c.label: c.header,
  };
  final compared = <String, String>{
    for (final c in single.others)
      if (mergedLabels.containsKey(c.label)) c.label: c.header,
  };
  final singleOnly = [
    for (final c in single.others)
      if (!mergedLabels.containsKey(c.label)) c.header.isEmpty ? c.label : c.header,
  ];
  final singleLabels = {for (final c in single.others) c.label};
  final mergedOnly = [
    for (final e in mergedLabels.entries)
      if (!singleLabels.contains(e.key)) e.value.isEmpty ? e.key : e.value,
  ];
  final descHeader = single.column(BomRole.description)?.header ?? '';
  // A field of a merged part is compared only when every file it came from
  // has that column (B-BOM may lack a column A-BOM has).
  BomDocument src(String tag) => tag == 'A' ? a : b!;
  bool has(String pn, BomRole role) => single.column(role) != null && (sources[pn] ?? const ['A']).every((t) => src(t).column(role) != null);
  bool hasOther(String pn, String label) => (sources[pn] ?? const ['A']).every((t) => (t == 'A' ? labelsA : labelsB).contains(label));

  // Which part each designator belongs to, on each side.
  final singleRefOwner = {for (final p in single.parts) for (final r in p.refs) r: p.partNo};
  final mergedRefOwner = {for (final p in merged) for (final r in p.refs) r: p.partNo};

  CompareRow row(String pn, BomPart? s, BomPart? m) {
    if (s == null || m == null) {
      return CompareRow(
        partNo: pn,
        status: s == null ? DiffStatus.onlyMerged : DiffStatus.onlySingle,
        single: s,
        merged: m,
        sources: sources[pn] ?? const [],
        fields: const [],
        missingRefs: s == null ? const [] : sortedRefs(s.refs),
        extraRefs: m == null ? const [] : sortedRefs(m.refs),
        movedRefs: {
          if (s != null)
            for (final r in s.refs)
              if (mergedRefOwner[r] != null) r: mergedRefOwner[r]!,
          if (m != null)
            for (final r in m.refs)
              if (singleRefOwner[r] != null) r: singleRefOwner[r]!,
        },
      );
    }
    final fields = <FieldCompare>[compareDescription(s.description, m.description, header: descHeader)];
    if (has(pn, BomRole.quantity)) fields.add(compareExact('quantity', '', formatQuantity(s.quantity), formatQuantity(m.quantity)));
    final sRefs = s.refs.toSet(), mRefs = m.refs.toSet();
    final refsOk = has(pn, BomRole.refs);
    final missing = refsOk ? sortedRefs(sRefs.difference(mRefs)) : const <String>[];
    final extra = refsOk ? sortedRefs(mRefs.difference(sRefs)) : const <String>[];
    if (refsOk) {
      fields.add(
        FieldCompare(
          key: 'refs',
          header: '',
          single: sortedRefs(sRefs).join(','),
          merged: sortedRefs(mRefs).join(','),
          equal: missing.isEmpty && extra.isEmpty && s.refs.length == m.refs.length,
        ),
      );
    }
    for (final e in compared.entries) {
      if (!hasOther(pn, e.key)) continue;
      fields.add(compareExact('col:${e.key}', e.value, s.extra[e.key] ?? '', m.extra[e.key] ?? ''));
    }
    final moved = <String, String>{
      for (final r in missing)
        if (mergedRefOwner[r] != null && mergedRefOwner[r] != pn) r: mergedRefOwner[r]!,
      for (final r in extra)
        if (singleRefOwner[r] != null && singleRefOwner[r] != pn) r: singleRefOwner[r]!,
    };
    return CompareRow(
      partNo: pn,
      status: fields.every((f) => f.equal) ? DiffStatus.same : DiffStatus.different,
      single: s,
      merged: m,
      sources: sources[pn] ?? const [],
      fields: fields,
      missingRefs: missing,
      extraRefs: extra,
      movedRefs: moved,
    );
  }

  final rows = <CompareRow>[
    for (final s in single.parts) row(s.partNo, s, mergedByPn[s.partNo]),
    for (final m in merged)
      if (!singleByPn.containsKey(m.partNo)) row(m.partNo, null, m),
  ];
  // Every source record must be accounted for by a result row.
  final cited = {
    for (final r in rows) ...[...?r.single?.recordIds, ...?r.merged?.recordIds],
  };
  final uncovered = [
    for (final d in [single, a, ?b])
      for (final rec in d.records)
        if (!cited.contains(rec.id)) rec.id,
  ];
  return CompareReport(rows: rows, compared: compared, singleOnlyColumns: singleOnly, mergedOnlyColumns: mergedOnly, at: DateTime.now(), uncovered: uncovered);
}
