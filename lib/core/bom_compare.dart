/// Compares a BOM with another (optionally two merged: A + B) and gives every
/// line one of five results with the evidence behind it.
///
/// Matching, strongest evidence first: the same part number; shared
/// designators (groups, so one line split into two, or two merged into one,
/// stay together); the same maker part number; a listed alternate; the same
/// item kind with identical parameters (only when that counterpart is
/// unique); and suggestions from the local embedding model, which can only
/// ever lead to REVIEW. Within a match the description is compared by its
/// parameters (values normalised, so 10K = 10kΩ) and its other letters and
/// digits; quantity, designators and every shared column must be identical.
library;

import 'bom.dart';
import 'classify.dart';
import 'knowledge.dart';
import 'params.dart';
import 'refdes.dart';

/// Result of one line.
enum CheckStatus {
  /// Matched, and every compared field agrees.
  pass,

  /// Matched with certainty, and a field conflicts.
  ng,

  /// Needs a person: the match or a field could not be settled.
  review,

  /// No counterpart on the other side.
  unmatched,

  /// A different part number that one of the BOMs lists as an approved
  /// alternate of the other, with everything else agreeing.
  substitute,
}

/// How much a line matters to the person reviewing the check.
enum Risk {
  /// A confirmed difference that changes what is built: a parameter,
  /// quantity, designator or fitted flag, or a part only one side places.
  high,

  /// Needs a person: an unsettled match or field, another column differs.
  medium,

  /// An approved substitute, or only wording left to confirm.
  low,
  none,
}

const _highReasons = {'param_conflict', 'qty', 'refs', 'dnp_differs', 'level', 'desc_text'};

Risk riskOf(CompareRow r) {
  switch (r.status) {
    case CheckStatus.pass:
      return Risk.none;
    case CheckStatus.substitute:
      return Risk.low;
    case CheckStatus.ng:
      return r.reasons.any(_highReasons.contains) ? Risk.high : Risk.medium;
    case CheckStatus.unmatched:
      // A placed part with no counterpart is missing from the build.
      final p = r.single ?? r.merged;
      return p != null && p.refs.isNotEmpty && !p.dnp ? Risk.high : Risk.medium;
    case CheckStatus.review:
      return r.reasons.every((x) => x == 'wording_unsure' || x.startsWith('cloud_')) ? Risk.low : Risk.medium;
  }
}

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
    this.equivalent = false,
    this.incomplete = false,
  });

  /// `description`, `quantity`, `refs` or `col:<label>`.
  final String key;

  /// Column header of the first BOM (shown for other columns).
  final String header;
  final String single;
  final String merged;

  /// No conflict.
  final bool equal;

  /// Equal by value though written differently (10K and 10kΩ).
  final bool equivalent;

  /// No conflict, but one side names a parameter the other leaves out.
  final bool incomplete;
  final List<Span> singleSpans;
  final List<Span> mergedSpans;
}

/// What a match rests on.
class MatchBasis {
  const MatchBasis(this.kinds, this.confidence);

  /// `partNo`, `refs`, `mpn`, `alternate`, `params`, `semantic`, `cloud`.
  final List<String> kinds;
  final double confidence;

  /// Evidence strong enough to call a conflict NG.
  bool get firm => kinds.any((k) => k == 'partNo' || k == 'refs' || k == 'mpn' || k == 'alternate');
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
    this.singleParts = const [],
    this.mergedParts = const [],
    this.basis = const MatchBasis([], 0),
    this.reasons = const [],
    this.cloudNote = '',
  });

  /// Part number of the first BOM's side, else of the other.
  final String partNo;
  final CheckStatus status;

  /// Each side's parts of this line, combined (several when a line is split
  /// or merged between the BOMs).
  final BomPart? single;
  final BomPart? merged;
  final List<BomPart> singleParts;
  final List<BomPart> mergedParts;

  /// Which of A / B hold the merged side.
  final List<String> sources;
  final List<FieldCompare> fields;

  /// Designators the first BOM has and the other lacks, and the reverse.
  final List<String> missingRefs;
  final List<String> extraRefs;

  /// A designator listed under another part number on the other side.
  final Map<String, String> movedRefs;
  final MatchBasis basis;

  /// Why the line is not PASS: `param_conflict`, `qty`, `refs`, `col`,
  /// `desc_text`, `param_incomplete`, `pn_differs`, `weak_match`, `split`,
  /// `dnp_differs`, `dnp_unsure`, `only_single`, `only_merged`.
  final List<String> reasons;

  /// What the cloud model said about the line (HYBRID / CLOUD_FULL).
  final String cloudNote;

  /// The other side's part number(s) when they differ from [partNo].
  String get otherPartNo => mergedParts.map((p) => p.partNo).where((p) => p != partNo).join(' + ');

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
    this.mode = 'local',
    this.models = const [],
  });

  final List<CompareRow> rows;

  /// How the check ran (`local`, `hybrid`, `cloudFull`) and which models
  /// took part, for the report.
  String mode;
  List<String> models;

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

  int count(CheckStatus s) => rows.where((r) => r.status == s).length;

  int countRisk(Risk k) => rows.where((r) => riskOf(r) == k).length;

  /// Reasons present, with how many lines have each.
  Map<String, int> get reasonCounts {
    final out = <String, int>{};
    for (final r in rows) {
      for (final x in r.reasons) {
        out[x] = (out[x] ?? 0) + 1;
      }
    }
    return out;
  }
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
    if (e <= s) continue;
    final t = text.substring(s, e);
    // Hyphenated words ("SMD-Widerstand") count word by word; codes with
    // digits stay whole.
    if (t.contains('-') && !RegExp(r'\d').hasMatch(t)) {
      var at = s;
      for (final part in t.split('-')) {
        if (part.isNotEmpty) out.add((part, at, at + part.length));
        at += part.length + 1;
      }
    } else {
      out.add((t, s, e));
    }
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

/// Descriptions: parameters compared by value (normalised units), the other
/// letters and digits (model names, codes) exactly; Chinese and other
/// wording is free.
FieldCompare compareDescription(String single, String merged, {String header = ''}) {
  final pc = compareParams(single, merged);
  final pa = extractParams(single), pb = extractParams(merged);
  bool inParam(List<Param> ps, int s, int e) => ps.any((p) => s < p.end && e > p.start);
  // Tokens with digits (model names, codes) must match exactly; words that
  // only name the kind of item or are filler may be worded differently
  // ("Chip resistor" / "贴片电阻"); any other word (RED / GREEN) must match.
  (String, int, int) norm((String, int, int) t) => RegExp(r'\d').hasMatch(t.$1) ? t : (t.$1.toLowerCase(), t.$2, t.$3);
  bool counts((String, int, int) t) => RegExp(r'\d').hasMatch(t.$1) || !wordingWords.contains(t.$1.toLowerCase());
  final ta = [for (final t in paramTokens(single)) if (!inParam(pa, t.$2, t.$3) && counts(t)) norm(t)];
  final tb = [for (final t in paramTokens(merged)) if (!inParam(pb, t.$2, t.$3) && counts(t)) norm(t)];
  final sa = [..._unmatched(ta, tb), for (final (x, _) in pc.conflicts) (x.start, x.end)];
  final sb = [..._unmatched(tb, ta), for (final (_, y) in pc.conflicts) (y.start, y.end)];
  // Descriptions that name different kinds of item (LED / diode) differ.
  final ka = classifyItem(single, const []), kb = classifyItem(merged, const []);
  final kindsDiffer = ka.$2 == 'words' && kb.$2 == 'words' && ka.$1 != kb.$1;
  // Words only one side has, where the other side writes in another
  // script (Chinese, Thai …), may just be translated: unsure, not a
  // conflict. Words differing on both sides (RED / GREEN) conflict.
  bool wordsOnly(List<Span> spans, String text) => spans.every((x) => !RegExp(r'\d').hasMatch(text.substring(x.$1, x.$2)));
  final otherScript = RegExp(r'[^\x00-\u024F\s\d\p{P}\p{S}]', unicode: true);
  final translated = !kindsDiffer &&
      pc.verdict != ParamVerdict.conflict &&
      ((sb.isEmpty && sa.isNotEmpty && wordsOnly(sa, single) && otherScript.hasMatch(merged)) || (sa.isEmpty && sb.isNotEmpty && wordsOnly(sb, merged) && otherScript.hasMatch(single)));
  final textSame = (sa.isEmpty && sb.isEmpty || translated) && !kindsDiffer;
  final conflict = pc.verdict == ParamVerdict.conflict || !textSame;
  final incomplete = !conflict && (pc.verdict == ParamVerdict.incomplete || translated);
  return FieldCompare(
    key: 'description',
    header: header,
    single: single,
    merged: merged,
    equal: !conflict,
    incomplete: incomplete,
    // Same values written differently.
    equivalent: !conflict && pc.matched.any((m) => m.$1.text.replaceAll(' ', '') != m.$2.text.replaceAll(' ', '')),
    singleSpans: [...sa, if (incomplete) for (final p in pc.onlyA) (p.start, p.end)],
    mergedSpans: [...sb, if (incomplete) for (final p in pc.onlyB) (p.start, p.end)],
  );
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

/// Combines several parts of one side of a line into one view.
BomPart _combine(List<BomPart> parts) {
  if (parts.length == 1) return parts.first;
  double? qty;
  for (final p in parts) {
    if (p.quantity != null) qty = (qty ?? 0) + p.quantity!;
  }
  return BomPart(
    parts.map((p) => p.partNo).join(' + '),
    description: parts.map((p) => p.description).join(' | '),
    quantity: qty,
    refs: [for (final p in parts) ...p.refs],
    extra: parts.first.extra,
    sources: [for (final p in parts) ...p.sources],
    recordIds: [for (final p in parts) ...p.recordIds],
    dnp: parts.every((p) => p.dnp),
    level: parts.first.level,
    alternates: {for (final p in parts) ...p.alternates}.toList(),
    kind: parts.first.kind,
  );
}

/// Suggested counterparts from the local embedding model: part number of
/// the first BOM → (part number of the other, similarity). Only ever lead to
/// REVIEW.
typedef SemanticSuggestions = Map<String, (String, double)>;

/// [pairs], when given, replaces the program's matching (CLOUD_FULL): each
/// is a set of part numbers of the first BOM and of the other side that
/// form one line; everything else is unmatched. Fields are still compared
/// by the program, and a pairing without firm evidence stays REVIEW.
CompareReport compareBoms(BomDocument single, BomDocument a, BomDocument? b, {SemanticSuggestions semantic = const {}, List<(List<String>, List<String>)>? pairs}) {
  final relabelA = matchColumns(single, a);
  final relabelB = b == null ? const <String, String>{} : matchColumns(single, b);
  final (merged, sources) = mergeBoms(a, b, relabelA: relabelA, relabelB: relabelB);
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
  // Fitted flags settle a difference only when every file has a fitted
  // column read with confidence; otherwise one side may simply not say.
  final dnpSure = [single, a, ?b].every((d) => (d.column(BomRole.dnp)?.confidence ?? 0) >= 0.7);

  BomDocument src(String tag) => tag == 'A' ? a : b!;
  bool hasAll(List<String> srcs, BomRole role) => single.column(role) != null && srcs.every((t) => src(t).column(role) != null);
  bool hasOther(List<String> srcs, String label) => srcs.every((t) => (t == 'A' ? labelsA : labelsB).contains(label));

  // ------------------------------------------------------------- matching
  final left = [...single.parts];
  final right = [...merged];
  final usedL = <BomPart>{}, usedR = <BomPart>{};
  final groups = <(List<BomPart>, List<BomPart>, MatchBasis)>[];

  if (pairs != null) {
    final lByPn = {for (final p in left) p.partNo: p}, rByPn = {for (final q in right) q.partNo: q};
    for (final (lp, rp) in pairs) {
      final ls = [for (final x in lp) ?lByPn[x]].where((p) => !usedL.contains(p)).toList();
      final rs = [for (final x in rp) ?rByPn[x]].where((q) => !usedR.contains(q)).toList();
      if (ls.isEmpty || rs.isEmpty) continue;
      // Firm evidence the program can see for itself.
      final samePn = ls.length == 1 && rs.length == 1 && ls.single.partNo == rs.single.partNo;
      final sharedRefs = {for (final p in ls) ...p.refs}.intersection({for (final q in rs) ...q.refs}).isNotEmpty;
      final alt = ls.any((p) => rs.any((q) => p.alternates.contains(q.partNo) || q.alternates.contains(p.partNo)));
      groups.add((ls, rs, MatchBasis(['cloud', if (samePn) 'partNo', if (sharedRefs) 'refs', if (alt) 'alternate'], samePn || sharedRefs ? 1 : 0.5)));
      usedL.addAll(ls);
      usedR.addAll(rs);
    }
  }

  // 1. The same part number.
  final rightByPn = {for (final p in right) p.partNo: p};
  for (final p in left) {
    if (pairs != null) break;
    final q = rightByPn[p.partNo];
    if (q != null && !p.partNo.startsWith('#')) {
      groups.add(([p], [q], const MatchBasis(['partNo'], 1)));
      usedL.add(p);
      usedR.add(q);
    }
  }

  // 2. Shared designators: connected groups of the remaining parts.
  final refOwnerR = <String, BomPart>{for (final q in right) if (!usedR.contains(q)) for (final r in q.refs) r: q};
  final linked = <BomPart, Set<BomPart>>{};
  for (final p in left) {
    if (usedL.contains(p) || pairs != null) continue;
    for (final r in p.refs) {
      final q = refOwnerR[r];
      if (q != null) (linked[p] ??= {}).add(q);
    }
  }
  final seenL = <BomPart>{};
  for (final start in linked.keys) {
    if (seenL.contains(start)) continue;
    // Walk the component: left parts sharing any right part.
    final gl = <BomPart>{start}, gr = <BomPart>{};
    var grew = true;
    while (grew) {
      grew = false;
      for (final p in [...gl]) {
        for (final q in linked[p] ?? const <BomPart>{}) {
          if (gr.add(q)) grew = true;
        }
      }
      for (final p in linked.keys) {
        if (!gl.contains(p) && (linked[p]!.any(gr.contains))) {
          gl.add(p);
          grew = true;
        }
      }
    }
    seenL.addAll(gl);
    final lr = {for (final p in gl) ...p.refs}, rr = {for (final q in gr) ...q.refs};
    final overlap = lr.intersection(rr).length / lr.union(rr).length;
    final alt = gl.any((p) => gr.any((q) => p.alternates.contains(q.partNo) || q.alternates.contains(p.partNo)));
    groups.add((gl.toList(), gr.toList(), MatchBasis(['refs', if (alt) 'alternate'], overlap)));
    usedL.addAll(gl);
    usedR.addAll(gr);
  }

  // 3. The same maker part number; 4. a listed alternate.
  String mpnOf(BomPart p) => (p.extra['mpn'] ?? '').trim();
  for (final p in left) {
    if (usedL.contains(p) || pairs != null) continue;
    final m = mpnOf(p);
    BomPart? q;
    var basis = '';
    if (m.isNotEmpty) {
      final c = right.where((x) => !usedR.contains(x) && mpnOf(x) == m).toList();
      if (c.length == 1) (q, basis) = (c.single, 'mpn');
    }
    if (q == null) {
      final c = right.where((x) => !usedR.contains(x) && (p.alternates.contains(x.partNo) || x.alternates.contains(p.partNo))).toList();
      if (c.length == 1) (q, basis) = (c.single, 'alternate');
    }
    if (q != null) {
      groups.add(([p], [q], MatchBasis([basis], 0.9)));
      usedL.add(p);
      usedR.add(q);
    }
  }

  // 5. The same kind with identical parameters, when that counterpart is
  // the only one either way.
  String? signature(BomPart p) {
    final ps = extractParams(p.description);
    if (ps.length < 2 || p.kind == ItemKind.unknown) return null;
    final keys = [for (final x in ps) '${x.kind.name}=${x.value ?? x.key}']..sort();
    return '${p.kind.name}|${keys.join(',')}';
  }

  final sigL = <String, List<BomPart>>{}, sigR = <String, List<BomPart>>{};
  for (final p in left) {
    if (usedL.contains(p) || pairs != null) continue;
    final k = signature(p);
    if (k != null) (sigL[k] ??= []).add(p);
  }
  for (final q in right) {
    if (usedR.contains(q)) continue;
    final k = signature(q);
    if (k != null) (sigR[k] ??= []).add(q);
  }
  for (final e in sigL.entries) {
    final r = sigR[e.key];
    if (e.value.length == 1 && r != null && r.length == 1) {
      groups.add(([e.value.single], [r.single], const MatchBasis(['params'], 0.7)));
      usedL.add(e.value.single);
      usedR.add(r.single);
    }
  }

  // 6. Suggestions from the embedding model.
  for (final p in left) {
    if (usedL.contains(p)) continue;
    final sug = semantic[p.partNo];
    if (sug == null) continue;
    final q = right.where((x) => !usedR.contains(x) && x.partNo == sug.$1).firstOrNull;
    if (q == null) continue;
    groups.add(([p], [q], MatchBasis(['semantic'], sug.$2)));
    usedL.add(p);
    usedR.add(q);
  }

  // ------------------------------------------------------------ comparing
  final singleRefOwner = {for (final p in single.parts) for (final r in p.refs) r: p.partNo};
  final mergedRefOwner = {for (final p in merged) for (final r in p.refs) r: p.partNo};

  CompareRow groupRow(List<BomPart> ls, List<BomPart> rs, MatchBasis basis) {
    final s = _combine(ls), m = _combine(rs);
    final srcs = {for (final q in rs) ...?sources[q.partNo]}.toList();
    final reasons = <String>[];
    final fields = <FieldCompare>[compareDescription(s.description, m.description, header: descHeader)];
    if (hasAll(srcs, BomRole.quantity)) fields.add(compareExact('quantity', '', formatQuantity(s.quantity), formatQuantity(m.quantity)));
    final sRefs = s.refs.toSet(), mRefs = m.refs.toSet();
    final refsOk = hasAll(srcs, BomRole.refs);
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
    final pnDiffers = ls.map((p) => p.partNo).toSet().difference(rs.map((q) => q.partNo).toSet()).isNotEmpty || ls.length != rs.length;
    final approved = basis.kinds.contains('alternate') || ls.any((p) => rs.any((q) => p.alternates.contains(q.partNo) || q.alternates.contains(p.partNo)));
    for (final e in compared.entries) {
      if (!hasOther(srcs, e.key)) continue;
      // A substitute naturally lists other alternates than the part it
      // replaces.
      if (e.key == 'alternate' && pnDiffers && approved) continue;
      // Fitted flags and levels are compared by meaning below, not by how
      // they are written ("YES" and an empty cell can both mean fitted).
      if (e.key == 'dnp' || e.key == 'level') continue;
      fields.add(compareExact('col:${e.key}', e.value, s.extra[e.key] ?? '', m.extra[e.key] ?? ''));
    }
    final moved = <String, String>{
      for (final r in missing)
        if (mergedRefOwner[r] != null && !rs.any((q) => q.partNo == mergedRefOwner[r])) r: mergedRefOwner[r]!,
      for (final r in extra)
        if (singleRefOwner[r] != null && !ls.any((p) => p.partNo == singleRefOwner[r])) r: singleRefOwner[r]!,
    };
    for (final f in fields) {
      if (f.equal) continue;
      reasons.add(switch (f.key) {
        'description' => compareParams(s.description, m.description).verdict == ParamVerdict.conflict ? 'param_conflict' : 'desc_text',
        'quantity' => 'qty',
        'refs' => 'refs',
        _ => 'col',
      });
    }
    final desc = fields.first;
    if (s.dnp != m.dnp) reasons.add(dnpSure ? 'dnp_differs' : 'dnp_unsure');
    if (s.level != null && m.level != null && s.level != m.level) reasons.add('level');
    if (desc.incomplete && desc.equal && (desc.singleSpans.isNotEmpty || desc.mergedSpans.isNotEmpty) && compareParams(s.description, m.description).verdict != ParamVerdict.incomplete) reasons.add('wording_unsure');
    if (ls.length > 1 || rs.length > 1) reasons.add('split');
    if (!basis.firm) reasons.add('weak_match');
    final hard = reasons.any((r) => const ['param_conflict', 'desc_text', 'qty', 'refs', 'col', 'dnp_differs', 'level'].contains(r));
    final CheckStatus status;
    if (hard) {
      // A conflict is only NG when the pairing itself is certain.
      status = basis.firm ? CheckStatus.ng : CheckStatus.review;
    } else if (pnDiffers) {
      status = approved && basis.firm && ls.length == 1 && rs.length == 1 && !desc.incomplete ? CheckStatus.substitute : CheckStatus.review;
      if (status == CheckStatus.review && !approved) reasons.add('pn_differs');
    } else if (desc.incomplete || reasons.contains('dnp_unsure') || !basis.firm) {
      if (desc.incomplete && !reasons.contains('wording_unsure')) reasons.add('param_incomplete');
      status = CheckStatus.review;
    } else {
      status = CheckStatus.pass;
    }
    return CompareRow(
      partNo: s.partNo,
      status: status,
      single: s,
      merged: m,
      singleParts: ls,
      mergedParts: rs,
      sources: srcs,
      fields: fields,
      missingRefs: missing,
      extraRefs: extra,
      movedRefs: moved,
      basis: basis,
      reasons: reasons,
    );
  }

  // A line without designators or quantity is often a stocked alternate.
  List<String> unmatchedReasons(BomPart? s, BomPart? m) {
    final p = (s ?? m)!;
    return [s == null ? 'only_merged' : 'only_single', if (p.refs.isEmpty && p.quantity == null) 'no_placement'];
  }

  CompareRow unmatchedRow(BomPart? s, BomPart? m) => CompareRow(
    partNo: (s ?? m)!.partNo,
    status: CheckStatus.unmatched,
    single: s,
    merged: m,
    singleParts: [?s],
    mergedParts: [?m],
    sources: m == null ? const [] : sources[m.partNo] ?? const [],
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
    reasons: unmatchedReasons(s, m),
  );

  // Rows in the first BOM's order, then what only the other side has.
  final groupOf = <BomPart, (List<BomPart>, List<BomPart>, MatchBasis)>{for (final g in groups) for (final p in g.$1) p: g};
  final done = <Object>{};
  final rows = <CompareRow>[];
  for (final p in left) {
    final g = groupOf[p];
    if (g == null) {
      rows.add(unmatchedRow(p, null));
    } else if (done.add(g)) {
      rows.add(groupRow(g.$1, g.$2, g.$3));
    }
  }
  for (final q in right) {
    if (!usedR.contains(q)) rows.add(unmatchedRow(null, q));
  }

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
