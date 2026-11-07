/// Unified intermediate BOM model shared by every check mode: a document
/// read from one sheet of one file, its recognised fields, and one record per
/// logical source row with every raw cell kept and a stable ID, so each
/// result can cite the original file, sheet and Excel row.
library;

import 'knowledge.dart';

export 'knowledge.dart' show ItemKind;

/// What a column holds.
enum BomRole {
  partNo,
  description,
  quantity,
  refs,
  serial,

  /// Manufacturer part number.
  mpn,

  /// Component maker.
  maker,

  /// Alternate (substitute) part numbers.
  alternate,

  /// Level in a multi-level BOM.
  level,

  /// Fitted / not fitted flag.
  dnp,
  other;

  /// Columns compared value by value between two BOMs (paired by role,
  /// or by header for [other]).
  bool get attribute => index >= BomRole.mpn.index;
}

/// A row of the original file: file name, sheet and the row number as Excel
/// shows it (1-based).
class SourceRef {
  const SourceRef(this.file, this.sheet, this.row);

  final String file;
  final String sheet;
  final int row;

  /// `sheet!row`, the short form shown next to a value.
  String get label => '$sheet!$row';

  @override
  bool operator ==(Object other) => other is SourceRef && other.file == file && other.sheet == sheet && other.row == row;

  @override
  int get hashCode => Object.hash(file, sheet, row);

  @override
  String toString() => '$file:$sheet!$row';

  Map<String, dynamic> toJson() => {'file': file, 'sheet': sheet, 'row': row};
}

/// A recognised column.
class BomColumn {
  BomColumn(this.index, this.header, this.role, {this.label = '', this.confidence = 1, this.evidence = ''});

  /// 0-based column index (A = 0).
  final int index;

  /// Header text as written (empty when the sheet has none).
  final String header;
  final BomRole role;

  /// For [BomRole.other]: the column name used to pair it with the column of
  /// the other BOM (header text without spaces and case).
  final String label;

  /// How sure the recognition is (0–1), and what it was based on.
  final double confidence;
  final String evidence;

  String get key => role.attribute ? 'col:$label' : role.name;

  /// Excel-style column letter.
  String get letter {
    var n = index + 1, out = '';
    while (n > 0) {
      final r = (n - 1) % 26;
      out = String.fromCharCode(65 + r) + out;
      n = (n - 1) ~/ 26;
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
    'column': letter,
    'header': header,
    'role': role.name,
    if (label.isNotEmpty) 'label': label,
    'confidence': double.parse(confidence.toStringAsFixed(2)),
    if (evidence.isNotEmpty) 'evidence': evidence,
  };
}

/// One logical row of a BOM: a part line plus any continuation rows that
/// only carry more designators.
class BomRecord {
  BomRecord({
    required this.id,
    required this.sources,
    required this.cells,
    required this.partNo,
    required this.description,
    required this.quantity,
    required this.refs,
    required this.extra,
    this.dnp = false,
    this.level,
    this.parentId,
    this.alternates = const [],
    this.kind = ItemKind.unknown,
    this.kindEvidence = '',
  });

  /// Stable within its document: `<document id>:<sheet>!<first row>`.
  final String id;

  /// Its own row first, then continuation rows.
  final List<SourceRef> sources;

  /// Every cell of its own row as read, recognised or not.
  final List<String> cells;

  /// Empty when the row has no part number.
  final String partNo;
  final String description;
  final double? quantity;
  final List<String> refs;

  /// Other columns by [BomColumn.label] → value.
  final Map<String, String> extra;

  /// Marked as not fitted (DNP / NC / 不贴 …).
  final bool dnp;

  /// Level in a multi-level BOM (top items 1), and the record of the
  /// assembly it belongs to.
  final int? level;
  final String? parentId;

  /// Alternate part numbers named on this line.
  final List<String> alternates;

  /// What the item is, and what that was decided from.
  final ItemKind kind;
  final String kindEvidence;

  SourceRef get source => sources.first;

  Map<String, dynamic> toJson() => {
    'id': id,
    'rows': [for (final s in sources) s.row],
    'partNo': partNo,
    'description': description,
    if (quantity != null) 'quantity': quantity,
    if (refs.isNotEmpty) 'refs': refs,
    if (extra.values.any((v) => v.isNotEmpty)) 'extra': {for (final e in extra.entries) if (e.value.isNotEmpty) e.key: e.value},
    if (dnp) 'dnp': true,
    if (level != null) 'level': level,
    if (parentId != null) 'parent': parentId,
    if (alternates.isNotEmpty) 'alternates': alternates,
    'kind': kind.name,
  };
}

/// The records of one part number (a part listed twice in a file is one
/// part): what the comparison works on.
class BomPart {
  BomPart(this.partNo, {required this.description, required this.quantity, required this.refs, required this.extra, required this.sources, List<String>? recordIds, this.dnp = false, this.alternates = const [], this.kind = ItemKind.unknown})
    : recordIds = recordIds ?? [];

  /// [records] of one part number, in file order.
  factory BomPart.of(String partNo, Iterable<BomRecord> records) {
    final list = records.toList();
    double? qty;
    for (final r in list) {
      if (r.quantity != null) qty = (qty ?? 0) + r.quantity!;
    }
    final extra = <String, String>{};
    for (final r in list) {
      for (final e in r.extra.entries) {
        if ((extra[e.key] ?? '').isEmpty) extra[e.key] = e.value;
      }
    }
    return BomPart(
      partNo,
      description: list.map((r) => r.description).firstWhere((d) => d.isNotEmpty, orElse: () => ''),
      quantity: qty,
      refs: [for (final r in list) ...r.refs],
      extra: extra,
      sources: [for (final r in list) ...r.sources],
      recordIds: [for (final r in list) r.id],
      dnp: list.every((r) => r.dnp),
      alternates: {for (final r in list) ...r.alternates}.toList(),
      kind: list.map((r) => r.kind).firstWhere((k) => k != ItemKind.unknown, orElse: () => ItemKind.unknown),
    );
  }

  final String partNo;
  String description;
  double? quantity;
  final List<String> refs;

  /// Other columns by [BomColumn.label] → value.
  final Map<String, String> extra;

  /// Every source row of its records.
  final List<SourceRef> sources;
  final List<String> recordIds;

  /// Every record of the part is marked not fitted.
  final bool dnp;
  final List<String> alternates;
  final ItemKind kind;

  /// Excel row numbers, for short display.
  List<int> get rows => [for (final s in sources) s.row];

  BomPart copy() => BomPart(partNo, description: description, quantity: quantity, refs: [...refs], extra: {...extra}, sources: [...sources], recordIds: [...recordIds], dnp: dnp, alternates: alternates, kind: kind);
}

/// Something worth telling the user about a file.
class BomWarning {
  const BomWarning(this.code, {this.row = 0, this.detail = ''});

  /// Localisation key: `w_qty_refs`, `w_dup_ref`, `w_no_part_no`.
  final String code;

  /// Excel row number (1-based).
  final int row;
  final String detail;
}

/// One BOM as read: the sheet chosen, its header row and fields, and the
/// records.
class BomDocument {
  BomDocument({
    required this.id,
    required this.file,
    required this.sheet,
    required this.headerRow,
    required this.columns,
    required this.records,
    required this.warnings,
    this.sheets = const [],
  }) : parts = _group(records);

  /// Short tag of this document in a check (`S`, `A`, `B`, …).
  final String id;
  final String file;
  final String sheet;

  /// Every sheet in the file.
  final List<String> sheets;

  /// 0-based row of the header, -1 when the sheet has no header row.
  final int headerRow;
  final List<BomColumn> columns;
  final List<BomRecord> records;
  final List<BomWarning> warnings;

  /// [records] grouped by part number, in file order; records without a
  /// part number stay on their own.
  final List<BomPart> parts;

  static List<BomPart> _group(List<BomRecord> records) {
    final byKey = <String, List<BomRecord>>{};
    for (final r in records) {
      byKey.putIfAbsent(r.partNo.isEmpty ? '#${r.id}' : r.partNo, () => []).add(r);
    }
    return [for (final e in byKey.entries) BomPart.of(e.value.first.partNo.isEmpty ? '#${e.value.first.source.row}' : e.key, e.value)];
  }

  BomColumn? column(BomRole role) => columns.where((c) => c.role == role).firstOrNull;

  /// Columns compared value by value, by label.
  Iterable<BomColumn> get others => columns.where((c) => c.role.attribute);

  BomRecord? record(String id) => records.where((r) => r.id == id).firstOrNull;

  Map<String, dynamic> toJson() => {
    'id': id,
    'file': file,
    'sheet': sheet,
    if (sheets.length > 1) 'sheets': sheets,
    'headerRow': headerRow < 0 ? null : headerRow + 1,
    'columns': [for (final c in columns) c.toJson()],
    'records': [for (final r in records) r.toJson()],
  };
}
