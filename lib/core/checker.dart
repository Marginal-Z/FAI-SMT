/// BOM ↔ station-list engine.
///
/// It has no built-in rules: what each file says is compared designator by
/// designator, and only rules the user typed in (exclusion keywords and
/// prefixes, alternates table, ignored designators — all empty by default)
/// change the outcome. Relations between part numbers come from the files
/// themselves (a BOM alternates column, a station related-part column) or
/// from the user's alternates table; never from where a row sits.
library;

import 'discrepancies.dart';
import 'models.dart';
import 'refdes.dart';
import 'settings.dart';

/// Rows (one per BOM line plus station part numbers the BOM lacks), the
/// designator list for the CAD file, and every finding.
class CheckOutcome {
  CheckOutcome(this.report, this.findings);

  final CheckReport report;
  final List<Discrepancy> findings;
}

/// Where a relation between two part numbers was read.
enum _Via { bom, station, rules }

String _join(Iterable<String> refs) => sortedRefs(refs).join(', ');

String _qty(double q) => q == q.roundToDouble() ? q.toInt().toString() : '$q';

String _norm(String s) => s.toUpperCase().replaceAll(RegExp(r'[\s_\-,，;；/()（）:：]+'), '');

/// One designator as the station lists place it.
class _Placed {
  _Placed(this.item);

  final StationItem item;
  String get pn => item.partNo;
}

CheckOutcome runCheck({
  required List<BomItem> bom,
  required List<StationItem> stations,
  required CheckRules rules,
  List<Placement>? placements,
  List<ParseIssue> bomIssues = const [],
  List<ParseIssue> stationAIssues = const [],
  List<ParseIssue> stationBIssues = const [],
  List<ParseIssue> coordIssues = const [],
}) {
  bool keep(String r) => !rules.isIgnoredRef(r);

  // ---- What each file says.
  final bomByPn = {for (final b in bom) b.partNo: b};
  final bomOwners = <String, List<String>>{}; // ref -> BOM part numbers
  for (final b in bom) {
    for (final r in b.refs.where(keep)) {
      final o = bomOwners.putIfAbsent(r, () => []);
      if (!o.contains(b.partNo)) o.add(b.partNo);
    }
  }
  final placed = <String, List<_Placed>>{}; // ref -> station rows placing it
  final stByPn = <String, List<StationItem>>{};
  for (final s in stations) {
    stByPn.putIfAbsent(s.partNo, () => []).add(s);
    for (final r in s.refs.where(keep)) {
      placed.putIfAbsent(r, () => []).add(_Placed(s));
    }
  }

  // ---- Relations found in the files or entered by the user.
  final subs = {for (final e in rules.substitutes.entries) e.key.toUpperCase(): e.value.map((v) => v.toUpperCase()).toSet()};
  _Via? relation(String bomPn, String stPn) {
    if ((bomByPn[bomPn]?.alternates ?? const []).contains(stPn)) return _Via.bom;
    if ((stByPn[stPn] ?? const []).any((s) => s.relatedTo == bomPn)) return _Via.station;
    if ((subs[bomPn]?.contains(stPn) ?? false) || (subs[stPn]?.contains(bomPn) ?? false)) return _Via.rules;
    return null;
  }

  final placeSet = {for (final p in placements ?? const <Placement>[]) p.ref: p};

  final rows = <CheckRow>[];
  final merged = <MergedRef>[];
  final explained = <String, Set<String>>{}; // station PN -> refs reported on a BOM line

  for (final b in bom) {
    final reasons = <Reason>[];
    final refs = b.refs.where(keep).toList();
    final refSet = refs.toSet();
    final own = stByPn[b.partNo] ?? const <StationItem>[];
    final ownRefs = {for (final s in own) ...s.refs.where(keep)};

    // User exclusions apply only to what the line does not load.
    final onLine = own.isNotEmpty || refSet.any((r) => placed.containsKey(r));
    final excl = onLine ? null : _excluded(b, rules);
    if (excl != null || (refSet.isEmpty && !onLine)) {
      rows.add(CheckRow(
        category: CheckCategory.excluded,
        partNo: b.partNo,
        description: b.description,
        bomQty: b.qty,
        smtQty: 0,
        bomRefs: [for (final r in sortedRefs(refSet)) RefMark(r, RefState.missing)],
        reasons: [excl ?? const Reason('e_nothing_to_compare', {}, true)],
      ));
      continue;
    }

    // ---- Designator by designator.
    final state = <String, RefState>{};
    final missing = <String>[], bothSides = <String>[];
    final wrong = <String, List<String>>{}; // station PN -> refs
    final multi = <String, List<String>>{};
    final alt = <String, (List<String>, _Via)>{};
    final loadedBy = <String, StationItem>{};
    for (final r in refSet) {
      final at = placed[r] ?? const <_Placed>[];
      if (at.isEmpty) {
        missing.add(r);
        state[r] = RefState.missing;
        continue;
      }
      final pns = {for (final p in at) p.pn};
      if ({for (final p in at) p.item.side}.length > 1) bothSides.add(r);
      if (pns.contains(b.partNo)) {
        loadedBy[r] = at.firstWhere((p) => p.pn == b.partNo).item;
        state[r] = RefState.ok;
        for (final other in pns.where((p) => p != b.partNo)) {
          multi.putIfAbsent(other, () => []).add(r);
          explained.putIfAbsent(other, () => {}).add(r);
        }
        continue;
      }
      final related = at.where((p) => relation(b.partNo, p.pn) != null).toList();
      if (related.isNotEmpty) {
        final p = related.first;
        final entry = alt.putIfAbsent(p.pn, () => (<String>[], relation(b.partNo, p.pn)!));
        entry.$1.add(r);
        loadedBy[r] = p.item;
        state[r] = RefState.alternate;
        explained.putIfAbsent(p.pn, () => {}).add(r);
        for (final o in pns.where((x) => x != p.pn)) {
          multi.putIfAbsent(o, () => []).add(r);
          explained.putIfAbsent(o, () => {}).add(r);
        }
        continue;
      }
      for (final p in pns) {
        wrong.putIfAbsent(p, () => []).add(r);
        explained.putIfAbsent(p, () => {}).add(r);
      }
      loadedBy[r] = at.first.item;
      state[r] = RefState.conflict;
    }
    for (final r in bothSides) {
      state[r] = RefState.conflict;
    }
    final extra = ownRefs.difference(refSet);

    if (refSet.isEmpty) reasons.add(const Reason('e_bom_no_refs'));
    if (own.isEmpty && alt.isEmpty && wrong.isEmpty && refSet.isNotEmpty && missing.length == refSet.length) {
      reasons.add(Reason('e_not_loaded', {'refs': _join(missing)}));
    } else if (missing.isNotEmpty) {
      reasons.add(Reason('e_missing', {'refs': _join(missing)}));
    }
    for (final e in wrong.entries) {
      reasons.add(Reason('e_wrong_part', {'refs': _join(e.value), 'pn': e.key}));
    }
    for (final e in multi.entries) {
      reasons.add(Reason('e_also_loaded', {'refs': _join(e.value), 'pn': e.key}));
    }
    if (bothSides.isNotEmpty) reasons.add(Reason('e_both_sides', {'refs': _join(bothSides)}));
    if (extra.isNotEmpty) {
      final elsewhere = extra.where(bomOwners.containsKey).toList();
      final unknown = extra.where((r) => !bomOwners.containsKey(r)).toList();
      if (unknown.isNotEmpty) reasons.add(Reason('e_extra', {'refs': _join(unknown)}));
      if (elsewhere.isNotEmpty) {
        reasons.add(Reason('e_extra_other_line', {'refs': _join(elsewhere), 'pn': elsewhere.expand((r) => bomOwners[r]!).toSet().join(', ')}));
      }
    }

    // ---- The BOM line itself.
    if (b.qty != null && refSet.isNotEmpty && (b.qty! - refSet.length).abs() > 1e-6) {
      reasons.add(Reason('e_bom_qty', {'qty': _qty(b.qty!), 'n': '${refSet.length}'}));
    }
    if (refs.length != refSet.length) {
      final seen = <String>{};
      reasons.add(Reason('e_bom_dup', {'refs': _join(refs.where((r) => !seen.add(r)))}));
    }
    final shared = refSet.where((r) => bomOwners[r]!.length > 1).toList();
    if (shared.isNotEmpty) {
      reasons.add(Reason('e_bom_shared', {'refs': _join(shared), 'pn': shared.expand((r) => bomOwners[r]!).where((p) => p != b.partNo).toSet().join(', ')}));
    }

    // ---- The station rows loading this part number.
    final descSeen = <String>{};
    final listed = <String, List<String>>{}; // ref -> slots
    for (final s in own) {
      final n = s.refs.where(keep).toSet().length;
      if (s.qty != null && n > 0 && (s.qty! - n).abs() > 1e-6) {
        reasons.add(Reason('e_station_qty', {'slot': s.slot, 'qty': _qty(s.qty!), 'n': '$n'}));
      }
      if (s.desc.isNotEmpty && b.description.isNotEmpty && descSeen.add(_norm(s.desc))) {
        final sd = _norm(s.desc), bd = _norm(b.description);
        if (!(sd == bd || bd.contains(sd) || sd.contains(bd))) {
          reasons.add(Reason('e_desc', {'station': s.desc, 'bom': b.description, 'slot': s.slot}));
        }
      }
      for (final r in s.refs.where(keep)) {
        listed.putIfAbsent(r, () => []).add(s.slot);
      }
    }
    final twice = listed.entries.where((e) => e.value.length > 1).toList();
    if (twice.isNotEmpty) {
      reasons.add(Reason('e_station_dup', {'refs': _join(twice.map((e) => e.key)), 'slots': twice.expand((e) => e.value).toSet().join(', ')}));
    }

    // ---- Coordinates.
    if (placements != null) {
      final noXy = refSet.where((r) => !placeSet.containsKey(r)).toList();
      if (noXy.isNotEmpty) reasons.add(Reason('e_coord_missing', {'refs': _join(noXy)}));
      final sideOff = [
        for (final r in refSet)
          if (placeSet[r] != null && placeSet[r]!.side != BoardSide.unknown && loadedBy[r] != null && (placeSet[r]!.side == BoardSide.top) != (loadedBy[r]!.side == StationSide.a)) r,
      ];
      if (sideOff.isNotEmpty) reasons.add(Reason('e_side_mismatch', {'refs': _join(sideOff)}));
    }

    for (final e in alt.entries) {
      // The code names where the relation was read (BOM, station list, user table).
      reasons.add(Reason('e_alt_${e.value.$2.name}', {'pn': e.key, 'refs': _join(e.value.$1)}, true));
    }

    final category = reasons.any((r) => !r.info)
        ? CheckCategory.ng
        : alt.isNotEmpty
            ? CheckCategory.substitute
            : CheckCategory.pass;
    final smtSet = {...ownRefs.intersection(refSet), ...extra, for (final e in alt.values) ...e.$1};
    final sources = [...own, for (final pn in alt.keys) ...?stByPn[pn]];
    rows.add(CheckRow(
      category: category,
      partNo: b.partNo,
      description: b.description,
      bomQty: b.qty,
      smtQty: smtSet.length,
      bomRefs: [for (final r in sortedRefs(refSet)) RefMark(r, state[r]!)],
      smtRefs: [for (final r in sortedRefs(smtSet)) RefMark(r, extra.contains(r) ? RefState.extra : state[r] ?? RefState.ok)],
      smtPartNos: [if (own.isNotEmpty) b.partNo, ...alt.keys],
      sides: {for (final s in sources) s.side},
      slots: {for (final s in sources) if (s.slot.isNotEmpty) s.slot}.toList(),
      reasons: reasons,
    ));
    for (final r in sortedRefs(refSet)) {
      final s = loadedBy[r];
      merged.add(MergedRef(
        ref: r,
        bomPartNo: b.partNo,
        smtPartNo: s?.partNo ?? '',
        description: b.description,
        category: category,
        side: s?.side,
        slot: s?.slot ?? '',
      ));
    }
  }

  // ---- Station part numbers the BOM does not have.
  for (final e in stByPn.entries) {
    final pn = e.key;
    if (bomByPn.containsKey(pn)) continue;
    final items = e.value;
    final allRefs = {for (final s in items) ...s.refs.where(keep)};
    final left = allRefs.difference(explained[pn] ?? const {});
    final relatedTo = bom.where((b) => relation(b.partNo, pn) != null).map((b) => b.partNo).toList();
    // A registered alternate whose designators are all accounted for.
    if (relatedTo.isNotEmpty && left.isEmpty) continue;
    final reasons = <Reason>[
      if (allRefs.isEmpty) const Reason('e_not_in_bom_no_refs') else Reason('e_not_in_bom', {'refs': _join(allRefs)}),
    ];
    final notInBom = left.where((r) => !bomOwners.containsKey(r)).toList();
    // Worth saying only when some of its designators do exist in the BOM.
    if (notInBom.isNotEmpty && notInBom.length < allRefs.length) reasons.add(Reason('e_refs_not_in_bom', {'refs': _join(notInBom)}));
    if (relatedTo.isNotEmpty) {
      reasons.add(Reason('e_alt_outside', {'pn': relatedTo.join(', '), 'refs': _join(left)}));
    } else {
      // A hint from the descriptions, never a decision.
      final desc = items.map((s) => s.desc).firstWhere((d) => d.isNotEmpty, orElse: () => '');
      final like = desc.isEmpty ? const <BomItem>[] : bom.where((b) => b.description.isNotEmpty && _norm(b.description) == _norm(desc)).toList();
      if (like.isNotEmpty) reasons.add(Reason('e_same_desc', {'pn': like.map((b) => b.partNo).join(', ')}, true));
    }
    rows.add(CheckRow(
      category: CheckCategory.ng,
      partNo: pn,
      description: items.map((s) => s.desc).firstWhere((d) => d.isNotEmpty, orElse: () => ''),
      smtQty: allRefs.length,
      smtRefs: [for (final r in sortedRefs(allRefs)) RefMark(r, RefState.extra)],
      smtPartNos: [pn],
      sides: {for (final s in items) s.side},
      slots: {for (final s in items) if (s.slot.isNotEmpty) s.slot}.toList(),
      reasons: reasons,
    ));
    for (final r in sortedRefs(notInBom)) {
      final s = items.firstWhere((s) => s.refs.contains(r));
      merged.add(MergedRef(ref: r, bomPartNo: '', smtPartNo: pn, description: s.desc, category: CheckCategory.ng, side: s.side, slot: s.slot));
    }
  }

  // ---- One slot loaded with two part numbers on the same side.
  final slotPns = <(StationSide, String), Set<String>>{};
  for (final s in stations) {
    if (s.slot.isNotEmpty) slotPns.putIfAbsent((s.side, s.slot), () => {}).add(s.partNo);
  }
  final slotIssue = <String, List<Reason>>{};
  for (final e in slotPns.entries.where((e) => e.value.length > 1)) {
    for (final pn in e.value) {
      slotIssue.putIfAbsent(pn, () => []).add(Reason('e_slot_shared', {'slot': e.key.$2, 'pn': e.value.where((p) => p != pn).join(', ')}));
    }
  }
  for (var i = 0; i < rows.length; i++) {
    final extra = slotIssue[rows[i].partNo];
    if (extra != null && rows[i].category != CheckCategory.excluded) rows[i] = rows[i].asNg(extra);
  }
  if (slotIssue.isNotEmpty) {
    final ng = {for (final r in rows) if (r.category == CheckCategory.ng) r.partNo};
    for (var i = 0; i < merged.length; i++) {
      if (ng.contains(merged[i].bomPartNo)) merged[i] = merged[i].withCategory(CheckCategory.ng);
    }
  }

  merged.sort((x, y) => compareRefs(x.ref, y.ref));
  final report = CheckReport(rows, merged);

  // ---- Findings: every reason, file problems, coordinates nobody places.
  final findings = <Discrepancy>[
    for (final row in rows)
      for (final r in row.reasons)
        Discrepancy(
          severity: severityOf(r),
          source: _sourceOf(r.code),
          code: r.code,
          subject: row.partNo,
          args: r.args,
          refs: r.args['refs']?.split(', ').where((e) => e.isNotEmpty).toList() ?? const [],
        ),
  ];
  void parsed(List<ParseIssue> issues, Source source) {
    for (final i in issues) {
      findings.add(Discrepancy(
        severity: Severity.warning,
        source: source,
        code: 'd_${i.code}',
        subject: i.row == null ? '-' : '#${i.row}',
        args: {'row': '${i.row ?? ''}', 'detail': i.detail},
      ));
    }
  }

  parsed(bomIssues, Source.bom);
  parsed(stationAIssues, Source.stationA);
  parsed(stationBIssues, Source.stationB);
  parsed(coordIssues, Source.coords);
  if (placements != null) {
    final known = {...bomOwners.keys, ...placed.keys};
    final extra = sortedRefs(placements.map((p) => p.ref).where((r) => !known.contains(r) && keep(r)));
    if (extra.isNotEmpty) {
      findings.add(Discrepancy(severity: Severity.info, source: Source.coords, code: 'd_coord_extra', subject: '', args: {'n': '${extra.length}'}, refs: extra));
    }
  }
  const order = {Severity.error: 0, Severity.warning: 1, Severity.info: 2};
  findings.sort((a, b) {
    final s = order[a.severity]!.compareTo(order[b.severity]!);
    return s != 0 ? s : compareRefs(a.subject, b.subject);
  });
  return CheckOutcome(report, findings);
}

Source _sourceOf(String code) => switch (code) {
      'e_bom_no_refs' || 'e_bom_qty' || 'e_bom_dup' || 'e_bom_shared' || 'excl_keyword' || 'excl_prefix' || 'e_nothing_to_compare' => Source.bom,
      'e_station_qty' || 'e_station_dup' || 'e_slot_shared' || 'e_not_in_bom' || 'e_not_in_bom_no_refs' || 'e_refs_not_in_bom' => Source.stations,
      'e_coord_missing' || 'e_side_mismatch' => Source.coords,
      _ => Source.cross,
    };

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
