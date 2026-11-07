/// A local model's reading of a sheet's columns, and the rules that decide
/// how much of it to take: the model may name columns the program left
/// unnamed or recognised weakly, only where the contents fit; it never
/// overrides a part number, quantity or designator column the program
/// found, and disagreements are kept as warnings.
library;

import '../bom.dart';
import '../table_reader.dart';
import 'local_ai.dart';

const _roleNames = {
  BomRole.partNo: 'partNo',
  BomRole.description: 'description',
  BomRole.quantity: 'quantity',
  BomRole.refs: 'refs',
  BomRole.serial: 'serial',
  BomRole.mpn: 'mpn',
  BomRole.maker: 'maker',
  BomRole.alternate: 'alternate',
  BomRole.level: 'level',
  BomRole.dnp: 'dnp',
  BomRole.other: 'other',
};

const _system = '''You read the columns of an electronics bill of materials (BOM). For every column, say what it holds:
partNo = the company's own part number of each line; description = name or specification text of the part; quantity = how many per board;
refs = PCB designators such as R1, C3, U2; serial = running line number; mpn = the manufacturer's part number;
maker = manufacturer name; alternate = alternative part numbers; level = depth in a multi-level BOM;
dnp = whether the part is fitted (DNP / not fitted / yes-no flags); other = anything else (remarks, prices, suppliers, compliance).
Judge from the header and the values together. Headers may be in any language or missing.''';

String _letter(int c) {
  var n = c + 1, out = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    out = String.fromCharCode(65 + r) + out;
    n = (n - 1) ~/ 26;
  }
  return out;
}

/// The data rows of [doc] in [g], 0-based.
List<int> _dataRows(BomDocument doc) => {for (final r in doc.records) for (final s in r.sources) if (s.sheet == doc.sheet) s.row - 1}.toList()..sort();

/// Sample values of column [c]: up to [n] distinct, shortened.
List<String> columnSamples(Grid g, BomDocument doc, int c, {int n = 8}) {
  final out = <String>[];
  for (final r in _dataRows(doc)) {
    final v = cleanCell(g.cell(r, c));
    if (v.isEmpty || out.contains(v)) continue;
    out.add(v.length > 48 ? '${v.substring(0, 48)}…' : v);
    if (out.length >= n) break;
  }
  return out;
}

/// Asks the model what each non-empty column of [doc]'s sheet holds.
Future<Map<int, BomRole>> askColumnRoles(Grid g, BomDocument doc, LocalModels ai) async {
  final width = g.rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
  final cols = <int>[];
  final lines = <String>[];
  for (var c = 0; c < width; c++) {
    final samples = columnSamples(g, doc, c);
    if (samples.isEmpty) continue;
    cols.add(c);
    final header = doc.columns.where((x) => x.index == c).map((x) => x.header).firstOrNull ?? '';
    lines.add('Column ${_letter(c)}, header ${header.isEmpty ? '(none)' : '"$header"'}: ${samples.join(' | ')}');
  }
  if (cols.isEmpty) return const {};
  final letters = [for (final c in cols) _letter(c)];
  final answer = await ai.structured(
    system: _system,
    user: lines.join('\n'),
    schema: {
      'type': 'object',
      'properties': {
        'columns': {
          'type': 'array',
          'items': {
            'type': 'object',
            'properties': {
              'column': {'type': 'string', 'enum': letters},
              'role': {'type': 'string', 'enum': _roleNames.values.toList()},
            },
            'required': ['column', 'role'],
            'additionalProperties': false,
          },
        },
      },
      'required': ['columns'],
      'additionalProperties': false,
    },
    maxTokens: 80 + 40 * cols.length,
  );
  final byName = {for (final e in _roleNames.entries) e.value: e.key};
  final out = <int, BomRole>{};
  for (final item in (answer['columns'] as List? ?? const [])) {
    if (item is! Map) continue;
    final c = letters.indexOf('${item['column']}');
    final role = byName['${item['role']}'];
    if (c >= 0 && role != null) out[cols[c]] = role;
  }
  return out;
}

/// What the program takes from a model answer.
class ColumnCheck {
  ColumnCheck(this.overrides, this.disagreements);

  /// Column → role the reader is told to use.
  final Map<int, BomRole> overrides;

  /// Column, program role, model role, where the program was kept.
  final List<(int, BomRole, BomRole)> disagreements;
}

/// Weighs [answer] against what the program read and the column contents.
ColumnCheck reconcileColumns(Grid g, BomDocument doc, Map<int, BomRole> answer) {
  const main = [BomRole.partNo, BomRole.quantity, BomRole.refs, BomRole.serial];
  final overrides = <int, BomRole>{};
  final disagreements = <(int, BomRole, BomRole)>[];
  final rows = _dataRows(doc);
  for (final e in answer.entries) {
    final c = e.key, said = e.value;
    final col = doc.columns.where((x) => x.index == c).firstOrNull;
    final have = col?.role ?? BomRole.other;
    if (said == have) continue;
    // Main fields the program found stay; a column the model wants as a
    // main field only fills a gap.
    if (main.contains(have)) {
      disagreements.add((c, have, said));
      continue;
    }
    if (main.contains(said) && doc.column(said) != null) {
      disagreements.add((c, have, said));
      continue;
    }
    // A header the program recognised outright is not overruled.
    final byHeader = col != null && col.evidence.contains('header') && col.confidence >= 0.7 && have != BomRole.other;
    if (byHeader) {
      disagreements.add((c, have, said));
      continue;
    }
    final values = [for (final r in rows) g.cell(r, c)];
    if (!contentFits(said, values)) {
      disagreements.add((c, have, said));
      continue;
    }
    overrides[c] = said;
  }
  return ColumnCheck(overrides, disagreements);
}
