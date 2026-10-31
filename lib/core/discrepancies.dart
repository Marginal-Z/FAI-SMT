/// A finding of a check or comparison: a localisable problem statement with
/// an explanation of the likely cause (`why_<code>`), its severity and where
/// it was found.
library;

import 'models.dart';

enum Severity { error, warning, info }

enum Source { bom, stationA, stationB, stations, coords, cross, bomA, bomB }

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

/// Reasons worth checking that are not outright errors.
const warningCodes = {
  'e_desc', 'e_station_qty', 'e_bom_qty', 'e_bom_dup', 'e_station_dup', 'e_not_in_bom_no_refs', 'e_coord_missing', //
  'cmp_desc', 'cmp_field', 'cmp_alt_diff', 'cmp_qty_refs', 'cmp_dup_refs',
};

Severity severityOf(Reason r) => r.info ? Severity.info : (warningCodes.contains(r.code) ? Severity.warning : Severity.error);
