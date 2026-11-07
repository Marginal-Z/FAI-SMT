/// Minimal .xlsx writer: text and number cells, bold, solid fills and
/// column widths, which is all the reports need.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Look of a cell. [fill] is RGB hex without `#` (e.g. `FFE3A3`).
class XlsxStyle {
  const XlsxStyle({this.bold = false, this.fill, this.center = false});

  final bool bold;
  final String? fill;
  final bool center;

  String get _key => '$bold|$fill|$center';
}

class XlsxSheetWriter {
  XlsxSheetWriter._(this.name);

  final String name;
  final _rows = <List<Object?>>[];
  final _styles = <int, Map<int, XlsxStyle>>{};
  final _widths = <int, double>{};

  /// 0-based index of the next row.
  int get rowCount => _rows.length;

  /// Adds a row of values: strings, numbers or null for an empty cell.
  void appendRow(List<Object?> values) => _rows.add(values);

  void style(int row, int column, XlsxStyle style) => (_styles[row] ??= {})[column] = style;

  /// Width in characters.
  void setWidth(int column, double width) => _widths[column] = width;

  /// Cell value as written, for tests.
  Object? value(int row, int column) => row < _rows.length && column < _rows[row].length ? _rows[row][column] : null;

  XlsxStyle? styleAt(int row, int column) => _styles[row]?[column];
}

class XlsxWriter {
  final _sheets = <XlsxSheetWriter>[];

  List<XlsxSheetWriter> get sheets => List.unmodifiable(_sheets);

  XlsxSheetWriter addSheet(String name) {
    final s = XlsxSheetWriter._(_sheetName(name, _sheets.length));
    _sheets.add(s);
    return s;
  }

  Uint8List encode() {
    if (_sheets.isEmpty) addSheet('Sheet1');
    // Styles: index 0 is the default; one entry per distinct look.
    final looks = <String, int>{};
    final lookList = <XlsxStyle>[const XlsxStyle()];
    looks[lookList.first._key] = 0;
    for (final s in _sheets) {
      for (final row in s._styles.values) {
        for (final st in row.values) {
          looks.putIfAbsent(st._key, () {
            lookList.add(st);
            return lookList.length - 1;
          });
        }
      }
    }

    final archive = Archive();
    void add(String path, String text) {
      final bytes = utf8.encode(text);
      archive.addFile(ArchiveFile(path, bytes.length, bytes));
    }

    add('[Content_Types].xml', _contentTypes(_sheets.length));
    add('_rels/.rels', _rootRels);
    add('xl/workbook.xml', _workbook(_sheets));
    add('xl/_rels/workbook.xml.rels', _workbookRels(_sheets.length));
    add('xl/styles.xml', _stylesXml(lookList));
    for (var i = 0; i < _sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(_sheets[i], looks));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }
}

// Excel sheet names: at most 31 characters, none of []:*?/\ , unique.
String _sheetName(String name, int index) {
  final clean = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
  final n = clean.isEmpty ? 'Sheet${index + 1}' : clean;
  return n.length > 31 ? n.substring(0, 31) : n;
}

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    // Control characters other than tab and line breaks are not allowed.
    .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

String _col(int i) {
  var n = i + 1, out = '';
  while (n > 0) {
    final r = (n - 1) % 26;
    out = String.fromCharCode(65 + r) + out;
    n = (n - 1) ~/ 26;
  }
  return out;
}

const _header = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';
const _ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _rel = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

String _contentTypes(int sheets) =>
    '$_header<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '${[for (var i = 1; i <= sheets; i++) '<Override PartName="/xl/worksheets/sheet$i.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'].join()}'
    '</Types>';

const _rootRels =
    '$_header<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="$_rel/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

String _workbook(List<XlsxSheetWriter> sheets) =>
    '$_header<workbook xmlns="$_ns" xmlns:r="$_rel"><sheets>'
    '${[for (var i = 0; i < sheets.length; i++) '<sheet name="${_esc(sheets[i].name)}" sheetId="${i + 1}" r:id="rId${i + 1}"/>'].join()}'
    '</sheets></workbook>';

String _workbookRels(int sheets) =>
    '$_header<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '${[for (var i = 1; i <= sheets; i++) '<Relationship Id="rId$i" Type="$_rel/worksheet" Target="worksheets/sheet$i.xml"/>'].join()}'
    '<Relationship Id="rId${sheets + 1}" Type="$_rel/styles" Target="styles.xml"/>'
    '</Relationships>';

String _stylesXml(List<XlsxStyle> looks) {
  final fills = <String>[];
  for (final l in looks) {
    if (l.fill != null && !fills.contains(l.fill)) fills.add(l.fill!);
  }
  final xfs = [
    for (final l in looks)
      '<xf numFmtId="0" fontId="${l.bold ? 1 : 0}" fillId="${l.fill == null ? 0 : 2 + fills.indexOf(l.fill!)}" borderId="0" xfId="0"'
          '${l.bold ? ' applyFont="1"' : ''}${l.fill != null ? ' applyFill="1"' : ''}'
          '${l.center ? ' applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf>' : '><alignment vertical="top" wrapText="1"/></xf>'}',
  ];
  return '$_header<styleSheet xmlns="$_ns">'
      '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
      '<fills count="${2 + fills.length}"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>'
      '${[for (final f in fills) '<fill><patternFill patternType="solid"><fgColor rgb="FF$f"/><bgColor indexed="64"/></patternFill></fill>'].join()}</fills>'
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
      '<cellXfs count="${xfs.length}">${xfs.join()}</cellXfs>'
      '</styleSheet>';
}

String _sheetXml(XlsxSheetWriter s, Map<String, int> looks) {
  final b = StringBuffer('$_header<worksheet xmlns="$_ns">');
  if (s._widths.isNotEmpty) {
    b.write('<cols>');
    for (final e in (s._widths.entries.toList()..sort((a, b) => a.key - b.key))) {
      b.write('<col min="${e.key + 1}" max="${e.key + 1}" width="${e.value}" customWidth="1"/>');
    }
    b.write('</cols>');
  }
  b.write('<sheetData>');
  for (var r = 0; r < s._rows.length; r++) {
    final row = s._rows[r];
    final styled = s._styles[r] ?? const {};
    final last = [row.length - 1, ...styled.keys].fold<int>(-1, (m, c) => c > m ? c : m);
    if (last < 0) continue;
    b.write('<row r="${r + 1}">');
    for (var c = 0; c <= last; c++) {
      final v = c < row.length ? row[c] : null;
      final st = styled[c];
      if (v == null && st == null) continue;
      final ref = '${_col(c)}${r + 1}';
      final sAttr = st == null ? '' : ' s="${looks[st._key]}"';
      if (v == null || (v is String && v.isEmpty)) {
        b.write('<c r="$ref"$sAttr/>');
      } else if (v is num) {
        b.write('<c r="$ref"$sAttr><v>${v is int || v == v.roundToDouble() && v.abs() < 1e15 ? v.toInt() : v}</v></c>');
      } else {
        b.write('<c r="$ref"$sAttr t="inlineStr"><is><t xml:space="preserve">${_esc('$v')}</t></is></c>');
      }
    }
    b.write('</row>');
  }
  b.write('</sheetData></worksheet>');
  return b.toString();
}
