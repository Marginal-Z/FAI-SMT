/// BOM vs station-list check engine.
library;

import 'models.dart';
import 'refdes.dart';
import 'settings.dart';

class _StationAgg {
  _StationAgg(this.partNo);

  final String partNo;
  final Set<String> refs = {};
  final Map<String, StationSide> sideOf = {};
  final Map<String, String> slotOf = {};
  final Set<StationSide> sides = {};
  final List<String> slots = [];

  /// Alternates the station list declares for this part, with their slot.
  final Map<String, String> listedAlts = {};
  String desc = '';
}

/// Compares the BOM with the merged station lists A and B.
///
/// Every BOM line yields one row; station part numbers that no BOM line
/// accounts for yield extra NG rows. Categories are disjoint.
CheckReport runCheck(List<BomItem> bom, List<StationItem> stations, CheckRules rules) {
  // ---- Aggregate station rows per part number.
  final agg = <String, _StationAgg>{};
  final refOwners = <String, Set<String>>{}; // ref -> station part numbers
  final refSides = <String, Set<StationSide>>{};
  final stationAlts = <String, Set<String>>{}; // main PN -> alternates
  for (final s in stations) {
    for (final alt in s.alternates) {
      stationAlts.putIfAbsent(s.partNo, () => {}).add(alt);
    }
    if (s.relatedTo.isNotEmpty) stationAlts.putIfAbsent(s.relatedTo, () => {}).add(s.partNo);
    final a = agg.putIfAbsent(s.partNo, () => _StationAgg(s.partNo));
    if (a.desc.isEmpty) a.desc = s.desc;
    a.sides.add(s.side);
    if (s.slot.isNotEmpty && !a.slots.contains(s.slot)) a.slots.add(s.slot);
    for (final alt in s.alternates) {
      a.listedAlts.putIfAbsent(alt, () => s.slot);
    }
    for (final r in s.refs) {
      if (rules.isIgnoredRef(r)) continue;
      a.refs.add(r);
      a.sideOf.putIfAbsent(r, () => s.side);
      if (s.slot.isNotEmpty) a.slotOf.putIfAbsent(r, () => s.slot);
      refOwners.putIfAbsent(r, () => {}).add(s.partNo);
      refSides.putIfAbsent(r, () => {}).add(s.side);
    }
  }

  // ---- Alternate relations: BOM column + user table.
  final altsOf = <String, Set<String>>{};
  for (final b in bom) {
    altsOf.putIfAbsent(b.partNo, () => {}).addAll(b.alternates);
    altsOf[b.partNo]!.addAll(rules.substitutes[b.partNo]?.map((e) => e.toUpperCase()) ?? const []);
    altsOf[b.partNo]!.addAll(stationAlts[b.partNo] ?? const {});
  }
  bool related(String a, String b) =>
      a == b || (altsOf[a]?.contains(b) ?? false) || (altsOf[b]?.contains(a) ?? false);

  // ---- Blank parts placed as a programmed part (烧录料) sharing their designators.
  final programmedBy = <String, String>{}; // blank PN -> programmed PN
  for (final p in bom) {
    if (agg[p.partNo] == null || !_matchesAny('${p.name} ${p.spec}', rules.programKeywords)) continue;
    final refs = p.refs.toSet();
    for (final b in bom) {
      if (b == p || b.refs.isEmpty || agg.containsKey(b.partNo) || _hasAltOnLine(b, altsOf, agg)) continue;
      if (refs.containsAll(b.refs)) programmedBy[b.partNo] = p.partNo;
    }
  }

  // ---- BOM-wide designator ownership, to catch a designator on two lines.
  final bomRefOwners = <String, Set<String>>{};
  for (final b in bom) {
    if (programmedBy.containsKey(b.partNo)) continue;
    for (final r in b.refs) {
      bomRefOwners.putIfAbsent(r, () => {}).add(b.partNo);
    }
  }

  final rows = <CheckRow>[];
  final merged = <MergedRef>[];
  final consumed = <String, Set<String>>{}; // station PN -> refs accounted for

  for (final b in bom) {
    final bomRefs = b.refs.where((r) => !rules.isIgnoredRef(r)).toList();
    final main = agg[b.partNo];

    final programmed = programmedBy[b.partNo];
    if (programmed != null) {
      rows.add(CheckRow(
        category: CheckCategory.excluded,
        partNo: b.partNo,
        description: b.description,
        bomQty: b.qty,
        smtQty: 0,
        bomRefs: [for (final r in sortedRefs(bomRefs)) RefMark(r, RefState.alternate)],
        smtPartNos: [programmed],
        reasons: [Reason('excl_programmed', {'pn': programmed}, true)],
      ));
      continue;
    }

    // Exclusion applies only to materials that are not loaded on the line.
    if (main == null && !_hasAltOnLine(b, altsOf, agg)) {
      final excl = _exclusionReason(b, bomRefs, rules);
      if (excl != null) {
        rows.add(CheckRow(
          category: CheckCategory.excluded,
          partNo: b.partNo,
          description: b.description,
          bomQty: b.qty,
          smtQty: 0,
          bomRefs: [for (final r in sortedRefs(bomRefs)) RefMark(r, RefState.missing)],
          reasons: [excl],
        ));
        continue;
      }
    }

    final reasons = <Reason>[];
    final bomSet = bomRefs.toSet();
    final mainRefs = main?.refs ?? <String>{};
    final altCover = <String, String>{}; // ref -> alternate PN
    final usedAlts = <String>[];
    for (final alt in altsOf[b.partNo] ?? const <String>{}) {
      final a = agg[alt];
      if (a == null || alt == b.partNo) continue;
      final covered = a.refs.intersection(bomSet).difference(mainRefs);
      if (covered.isEmpty) continue;
      usedAlts.add(alt);
      for (final r in covered) {
        altCover[r] = alt;
      }
      consumed.putIfAbsent(alt, () => {}).addAll(covered);
    }
    if (main != null) consumed.putIfAbsent(b.partNo, () => {}).addAll(mainRefs);

    final smtSet = {...mainRefs, ...altCover.keys};
    final missing = bomSet.difference(smtSet);
    final extra = mainRefs.difference(bomSet);
    final conflicts = smtSet
        .where((r) => (refOwners[r] ?? const {}).any((o) => !related(o, b.partNo)))
        .toSet();
    final bothSides = smtSet.where((r) => (refSides[r]?.length ?? 0) > 1).toSet();

    if (bomRefs.isEmpty) {
      reasons.add(const Reason('bom_no_refs'));
    }
    if (main == null && usedAlts.isEmpty) {
      reasons.add(const Reason('not_on_station'));
    } else {
      if (missing.isNotEmpty) {
        reasons.add(Reason('station_missing_refs', {'refs': _join(missing)}));
      }
      if (extra.isNotEmpty) {
        reasons.add(Reason('station_extra_refs', {'refs': _join(extra)}));
      }
    }
    final dupInLine = _duplicates(bomRefs);
    if (dupInLine.isNotEmpty) {
      reasons.add(Reason('bom_dup_refs', {'refs': _join(dupInLine)}));
    }
    final crossBom = bomSet.where((r) => (bomRefOwners[r]?.length ?? 0) > 1).toSet();
    if (crossBom.isNotEmpty) {
      final others = crossBom.expand((r) => bomRefOwners[r]!).where((p) => p != b.partNo).toSet();
      reasons.add(Reason('bom_ref_conflict', {'refs': _join(crossBom), 'pn': others.join(', ')}));
    }
    if (conflicts.isNotEmpty) {
      final others = conflicts
          .expand((r) => refOwners[r]!)
          .where((o) => !related(o, b.partNo))
          .toSet();
      reasons.add(Reason('station_ref_conflict', {'refs': _join(conflicts), 'pn': others.join(', ')}));
    }
    if (bothSides.isNotEmpty) {
      reasons.add(Reason('ref_both_sides', {'refs': _join(bothSides)}));
    }
    if (rules.checkQty && b.qty != null && bomRefs.isNotEmpty) {
      final q = b.qty!;
      if ((q - bomSet.length).abs() > 1e-6) {
        reasons.add(Reason('qty_mismatch', {'qty': _fmtQty(q), 'n': '${bomSet.length}'}));
      }
    }
    for (final alt in usedAlts) {
      final refs = altCover.entries.where((e) => e.value == alt).map((e) => e.key);
      reasons.add(Reason('alt_used', {'pn': alt, 'refs': _join(refs)}, true));
    }
    final listed = <String, String>{};
    for (final pn in [b.partNo, ...usedAlts]) {
      for (final e in agg[pn]?.listedAlts.entries ?? const <MapEntry<String, String>>[]) {
        if (e.key != b.partNo && !usedAlts.contains(e.key)) listed.putIfAbsent(e.key, () => e.value);
      }
    }
    for (final e in listed.entries) {
      reasons.add(Reason('alt_listed', {'pn': e.key, 'slot': e.value}, true));
    }

    final hasError = reasons.any((r) => !r.info);
    final category = hasError
        ? CheckCategory.ng
        : usedAlts.isNotEmpty || listed.isNotEmpty
            ? CheckCategory.substitute
            : CheckCategory.pass;

    RefState stateOf(String r) {
      if (conflicts.contains(r) || bothSides.contains(r)) return RefState.conflict;
      if (altCover.containsKey(r)) return RefState.alternate;
      if (mainRefs.contains(r)) return RefState.ok;
      return RefState.missing;
    }

    final sides = <StationSide>{...?main?.sides};
    final slots = <String>[...?main?.slots];
    for (final alt in usedAlts) {
      sides.addAll(agg[alt]!.sides);
      slots.addAll(agg[alt]!.slots);
    }

    rows.add(CheckRow(
      category: category,
      partNo: b.partNo,
      description: b.description,
      bomQty: b.qty,
      smtQty: smtSet.length,
      bomRefs: [for (final r in sortedRefs(bomSet)) RefMark(r, stateOf(r))],
      smtRefs: [
        for (final r in sortedRefs(smtSet))
          RefMark(r, extra.contains(r) ? RefState.extra : stateOf(r))
      ],
      smtPartNos: [if (main != null) b.partNo, ...usedAlts],
      sides: sides,
      slots: slots,
      reasons: reasons,
    ));

    for (final r in sortedRefs(bomSet)) {
      final alt = altCover[r];
      final src = alt != null ? agg[alt] : (mainRefs.contains(r) ? main : null);
      merged.add(MergedRef(
        ref: r,
        bomPartNo: b.partNo,
        smtPartNo: alt ?? (src != null ? b.partNo : ''),
        description: b.description,
        category: category,
        side: src?.sideOf[r],
        slot: src?.slotOf[r] ?? '',
      ));
    }
  }

  // ---- Station part numbers (or parts of them) no BOM line accounts for.
  final bomPns = {for (final b in bom) b.partNo};
  final bomAllRefs = bomRefOwners.keys.toSet();
  for (final a in agg.values) {
    final left = a.refs.difference(consumed[a.partNo] ?? const {});
    if (bomPns.contains(a.partNo)) continue; // extras already reported on its line
    final isAlt = altsOf.values.any((s) => s.contains(a.partNo));
    if (left.isEmpty && isAlt) continue;
    if (left.isEmpty && a.refs.isNotEmpty) continue;
    final reasons = <Reason>[
      Reason(isAlt ? 'alt_outside_main' : 'not_in_bom', {'refs': _join(left)}),
    ];
    final inBomElsewhere = left.where(bomAllRefs.contains).toSet();
    if (inBomElsewhere.isNotEmpty) {
      final owners = inBomElsewhere.expand((r) => bomRefOwners[r]!).toSet();
      reasons.add(Reason('ref_belongs_to', {'refs': _join(inBomElsewhere), 'pn': owners.join(', ')}));
    }
    rows.add(CheckRow(
      category: CheckCategory.ng,
      partNo: a.partNo,
      description: a.desc,
      bomQty: null,
      smtQty: left.length,
      smtRefs: [for (final r in sortedRefs(left)) RefMark(r, RefState.extra)],
      smtPartNos: [a.partNo],
      sides: a.sides,
      slots: a.slots,
      reasons: reasons,
    ));
    for (final r in sortedRefs(left)) {
      if (bomAllRefs.contains(r)) continue; // already merged under its BOM line
      merged.add(MergedRef(
        ref: r,
        bomPartNo: '',
        smtPartNo: a.partNo,
        description: a.desc,
        category: CheckCategory.ng,
        side: a.sideOf[r],
        slot: a.slotOf[r] ?? '',
      ));
    }
  }

  merged.sort((x, y) => compareRefs(x.ref, y.ref));
  return CheckReport(rows, merged);
}

bool _hasAltOnLine(BomItem b, Map<String, Set<String>> altsOf, Map<String, _StationAgg> agg) =>
    (altsOf[b.partNo] ?? const {}).any(agg.containsKey);

bool _matchesAny(String text, List<String> keywords) {
  final t = text.toUpperCase();
  return keywords.any((k) => k.trim().isNotEmpty && t.contains(k.trim().toUpperCase()));
}

Reason? _exclusionReason(BomItem b, List<String> refs, CheckRules rules) {
  if (refs.isEmpty && b.qty == 0) return const Reason('excl_parent', {}, true);
  final text = '${b.name} ${b.spec}'.toUpperCase();
  for (final k in rules.excludeKeywords) {
    if (k.trim().isNotEmpty && text.contains(k.trim().toUpperCase())) {
      return Reason('excl_keyword', {'kw': k.trim()}, true);
    }
  }
  for (final p in rules.excludePrefixes) {
    if (p.trim().isNotEmpty && b.partNo.startsWith(p.trim().toUpperCase())) {
      return Reason('excl_prefix', {'prefix': p.trim()}, true);
    }
  }
  if (refs.isEmpty && rules.excludeNoRefs) {
    return const Reason('excl_no_refs', {}, true);
  }
  return null;
}

List<String> _duplicates(List<String> refs) {
  final seen = <String>{};
  final dup = <String>{};
  for (final r in refs) {
    if (!seen.add(r)) dup.add(r);
  }
  return sortedRefs(dup);
}

String _join(Iterable<String> refs) => sortedRefs(refs).join(', ');

String _fmtQty(double q) => q == q.roundToDouble() ? q.toInt().toString() : q.toString();
