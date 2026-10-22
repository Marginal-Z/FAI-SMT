/// Domain models shared by parsers, the check engine and exporters.
library;

/// One BOM line after merging continuation rows.
class BomItem {
  BomItem({
    required this.partNo,
    this.name = '',
    this.spec = '',
    this.qty,
    List<String>? refs,
    List<String>? alternates,
    this.sourceRow = 0,
  })  : refs = refs ?? [],
        alternates = alternates ?? [];

  final String partNo;
  String name;
  String spec;
  double? qty;
  final List<String> refs;
  final List<String> alternates;
  final int sourceRow;

  String get description => [name, spec].where((s) => s.isNotEmpty).join(' ');
}

enum StationSide { a, b }

/// One row of a station list (站位表).
class StationItem {
  StationItem({
    required this.partNo,
    required this.side,
    this.slot = '',
    this.desc = '',
    this.qty,
    List<String>? refs,
    List<String>? alternates,
    this.relatedTo = '',
    this.sourceRow = 0,
  })  : refs = refs ?? [],
        alternates = alternates ?? [];

  final String partNo;

  /// Alternates listed under this row (rows with no slot and no designators).
  final List<String> alternates;

  /// 关联料号 when it differs from [partNo]: this row loads an alternate of it.
  final String relatedTo;
  final StationSide side;
  final String slot;
  final String desc;
  final double? qty;
  final List<String> refs;
  final int sourceRow;
}

enum BoardSide { top, bottom, unknown }

/// One placement from the original coordinate (pick & place) file, in mm.
class Placement {
  Placement({
    required this.ref,
    required this.x,
    required this.y,
    this.rotation = 0,
    this.side = BoardSide.unknown,
    this.value = '',
    this.footprint = '',
  });

  final String ref;
  final double x;
  final double y;
  final double rotation;
  final BoardSide side;
  final String value;
  final String footprint;
}

class ParseIssue {
  ParseIssue(this.code, {this.row, this.detail = ''});

  /// Localisation key, e.g. `parse_bad_number`.
  final String code;
  final int? row;
  final String detail;
}

class ParseResult<T> {
  ParseResult(this.items, {this.issues = const [], this.columns = const {}});

  final List<T> items;
  final List<ParseIssue> issues;

  /// Detected field -> header text, shown to the user for transparency.
  final Map<String, String> columns;
}

/// Category of a check row. Every row belongs to exactly one category, so the
/// tab counts add up to the total, as in the reference screenshot.
enum CheckCategory { pass, ng, excluded, substitute }

enum RefState {
  /// Present on both sides.
  ok,

  /// In the BOM, absent from the station list.
  missing,

  /// In the station list, absent from the BOM line.
  extra,

  /// Placed by an alternate part number.
  alternate,

  /// Used by more than one part number.
  conflict,
}

class RefMark {
  const RefMark(this.ref, this.state);

  final String ref;
  final RefState state;
}

/// A reason attached to a check row. [code] is a localisation key and [args]
/// are substituted into the translated template.
class Reason {
  const Reason(this.code, [this.args = const {}, this.info = false]);

  final String code;
  final Map<String, String> args;

  /// Informational notes (e.g. "alternate used") do not make a row NG.
  final bool info;
}

class CheckRow {
  CheckRow({
    required this.category,
    required this.partNo,
    required this.description,
    this.bomQty,
    this.smtQty,
    this.bomRefs = const [],
    this.smtRefs = const [],
    this.smtPartNos = const [],
    this.sides = const {},
    this.slots = const [],
    this.reasons = const [],
  });

  final CheckCategory category;

  /// BOM part number, or the station part number for rows not in the BOM.
  final String partNo;
  final String description;
  final double? bomQty;
  final int? smtQty;
  final List<RefMark> bomRefs;
  final List<RefMark> smtRefs;

  /// Part numbers actually loaded on the line (main and / or alternates).
  final List<String> smtPartNos;
  final Set<StationSide> sides;
  final List<String> slots;
  final List<Reason> reasons;
}

/// Per-designator merged record used to build the CAD file.
class MergedRef {
  MergedRef({
    required this.ref,
    required this.bomPartNo,
    required this.smtPartNo,
    required this.description,
    required this.category,
    this.side,
    this.slot = '',
  });

  final String ref;
  final String bomPartNo;
  final String smtPartNo;
  final String description;
  final CheckCategory category;
  final StationSide? side;
  final String slot;
}

class CheckReport {
  CheckReport(this.rows, this.merged);

  final List<CheckRow> rows;
  final List<MergedRef> merged;

  int count(CheckCategory c) => rows.where((r) => r.category == c).length;
}
