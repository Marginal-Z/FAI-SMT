/// Every inconsistency found across the BOM, station lists A/B and the
/// coordinate file, each with a localisable problem statement and an
/// explanation of the likely cause and its effect.
library;

import 'models.dart';
import 'refdes.dart';
import 'settings.dart';

enum Severity { error, warning, info }

enum Source { bom, stationA, stationB, stations, coords, cross }

class Discrepancy {
  const Discrepancy({
    required this.severity,
    required this.source,
    required this.code,
    required this.subject,
    this.args = const {},
    this.refs = const [],
  });

  final Severity severity;
  final Source source;

  /// Localisation key; `<code>` is the problem, `why_<code>` the explanation.
  final String code;

  /// Part number, designator or file the issue is about.
  final String subject;
  final Map<String, String> args;
  final List<String> refs;
}

String _norm(String s) => s.toUpperCase().replaceAll(RegExp(r'[\s_\-,，;；/()（）]+'), '');

List<Discrepancy> findDiscrepancies({
  required List<BomItem> bom,
  required List<StationItem> stations,
  required CheckReport report,
  required CheckRules rules,
  List<Placement>? placements,
  List<ParseIssue> bomIssues = const [],
  List<ParseIssue> stationAIssues = const [],
  List<ParseIssue> stationBIssues = const [],
  List<ParseIssue> coordIssues = const [],
}) {
  final out = <Discrepancy>[];

  // 1. BOM ↔ station results (everything that is not a plain PASS).
  for (final row in report.rows) {
    for (final r in row.reasons) {
      final excluded = row.category == CheckCategory.excluded;
      out.add(Discrepancy(
        severity: r.info ? Severity.info : Severity.error,
        source: excluded ? Source.bom : Source.cross,
        code: r.code,
        subject: row.partNo,
        args: r.args,
        refs: r.args['refs']?.split(', ').where((e) => e.isNotEmpty).toList() ?? const [],
      ));
    }
  }

  // 2. Description on the station list differs from the BOM.
  final bomByPn = {for (final b in bom) b.partNo: b};
  final seenDesc = <String>{};
  for (final s in stations) {
    final b = bomByPn[s.partNo];
    if (b == null || s.desc.isEmpty || !seenDesc.add(s.partNo)) continue;
    final sd = _norm(s.desc), bd = _norm(b.description);
    // One may abbreviate the other, but neither may add or change details.
    final match = sd == bd || bd.contains(sd) || sd.contains(bd);
    if (!match) {
      out.add(Discrepancy(
        severity: Severity.warning,
        source: s.side == StationSide.a ? Source.stationA : Source.stationB,
        code: 'd_desc_mismatch',
        subject: s.partNo,
        args: {'station': s.desc, 'bom': b.description, 'slot': s.slot},
      ));
    }
  }

  // 3. Same designator listed twice for one part number on one side.
  for (final side in StationSide.values) {
    final seen = <String, String>{};
    for (final s in stations.where((e) => e.side == side)) {
      for (final r in s.refs) {
        final key = '${s.partNo}|$r';
        final first = seen[key];
        if (first != null && first != s.slot) {
          out.add(Discrepancy(
            severity: Severity.warning,
            source: side == StationSide.a ? Source.stationA : Source.stationB,
            code: 'd_station_dup',
            subject: r,
            args: {'pn': s.partNo, 'slots': '$first, ${s.slot}'},
            refs: [r],
          ));
        }
        seen.putIfAbsent(key, () => s.slot);
      }
    }
  }

  // 4. File-level parse findings.
  void parsed(List<ParseIssue> issues, Source source) {
    for (final i in issues) {
      out.add(Discrepancy(
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

  // 5. Coordinates against the merged list.
  if (placements != null) {
    final byRef = {for (final p in placements) p.ref: p};
    final merged = {for (final m in report.merged) m.ref: m};
    for (final m in report.merged) {
      if (rules.isIgnoredRef(m.ref)) continue;
      final p = byRef[m.ref];
      if (p == null) {
        out.add(Discrepancy(
          severity: Severity.error,
          source: Source.coords,
          code: 'd_coord_missing',
          subject: m.ref,
          args: {'pn': m.smtPartNo.isNotEmpty ? m.smtPartNo : m.bomPartNo},
          refs: [m.ref],
        ));
        continue;
      }
      if (p.side != BoardSide.unknown && m.side != null && (p.side == BoardSide.top) != (m.side == StationSide.a)) {
        out.add(Discrepancy(
          severity: Severity.error,
          source: Source.cross,
          code: 'd_side_mismatch',
          subject: m.ref,
          args: {
            'station': m.side == StationSide.a ? 'A' : 'B',
            'layer': p.side == BoardSide.top ? 'TOP' : 'BOT',
          },
          refs: [m.ref],
        ));
      }
    }
    final extra = sortedRefs(placements.map((p) => p.ref).where((r) => !merged.containsKey(r) && !rules.isIgnoredRef(r)));
    if (extra.isNotEmpty) {
      out.add(Discrepancy(
        severity: Severity.info,
        source: Source.coords,
        code: 'd_coord_extra',
        subject: '',
        args: {'n': '${extra.length}'},
        refs: extra,
      ));
    }
  }

  const order = {Severity.error: 0, Severity.warning: 1, Severity.info: 2};
  out.sort((a, b) {
    final s = order[a.severity]!.compareTo(order[b.severity]!);
    return s != 0 ? s : compareRefs(a.subject, b.subject);
  });
  return out;
}
