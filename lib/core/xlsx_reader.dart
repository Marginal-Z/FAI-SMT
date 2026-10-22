/// Minimal, tolerant .xlsx value reader.
///
/// ERP / MES exports (T100, station-list tools) often carry styles that strict
/// workbook libraries reject, so only cell values are read here: shared
/// strings, inline strings, numbers and booleans. Formatting is ignored.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class XlsxSheet {
  XlsxSheet(this.name, this.rows);

  final String name;
  final List<List<String>> rows;
}

List<XlsxSheet> readXlsx(Uint8List bytes) {
  final zip = ZipDecoder().decodeBytes(bytes);
  String? text(String path) {
    final f = zip.findFile(path);
    if (f == null) return null;
    return utf8.decode(f.content as List<int>, allowMalformed: true);
  }

  final shared = <String>[];
  final sst = text('xl/sharedStrings.xml');
  if (sst != null) {
    for (final si in XmlDocument.parse(sst).findAllElements('si')) {
      shared.add(_textOf(si));
    }
  }

  // workbook.xml lists sheets in display order; rels map r:id -> part path.
  final rels = <String, String>{};
  final relsXml = text('xl/_rels/workbook.xml.rels');
  if (relsXml != null) {
    for (final r in XmlDocument.parse(relsXml).findAllElements('Relationship')) {
      final target = r.getAttribute('Target') ?? '';
      rels[r.getAttribute('Id') ?? ''] = target.startsWith('/') ? target.substring(1) : 'xl/$target';
    }
  }
  final sheets = <XlsxSheet>[];
  final wb = text('xl/workbook.xml');
  if (wb == null) throw const FormatException('xl/workbook.xml missing');
  for (final s in XmlDocument.parse(wb).findAllElements('sheet')) {
    final rid = s.attributes.firstWhere((a) => a.name.local == 'id', orElse: () => XmlAttribute(XmlName('id'), '')).value;
    final path = rels[rid];
    final xml = path == null ? null : text(path);
    if (xml == null) continue;
    sheets.add(XlsxSheet(s.getAttribute('name') ?? 'Sheet', _readSheet(xml, shared)));
  }
  return sheets;
}

String _textOf(XmlElement e) =>
    e.findAllElements('t').where((t) => t.parentElement?.name.local != 'rPh').map((t) => t.innerText).join();

List<List<String>> _readSheet(String xml, List<String> shared) {
  final rows = <List<String>>[];
  final data = XmlDocument.parse(xml).findAllElements('sheetData').firstOrNull;
  if (data == null) return rows;
  for (final row in data.findElements('row')) {
    final rAttr = int.tryParse(row.getAttribute('r') ?? '');
    final rowIndex = rAttr != null ? rAttr - 1 : rows.length;
    while (rows.length < rowIndex) {
      rows.add([]);
    }
    final cells = <String>[];
    var next = 0;
    for (final c in row.findElements('c')) {
      final ref = c.getAttribute('r');
      final col = ref == null ? next : _colIndex(ref);
      while (cells.length < col) {
        cells.add('');
      }
      cells.add(_cellValue(c, shared));
      next = col + 1;
    }
    while (cells.isNotEmpty && cells.last.isEmpty) {
      cells.removeLast();
    }
    rows.add(cells);
  }
  return rows;
}

int _colIndex(String ref) {
  var n = 0;
  for (final ch in ref.codeUnits) {
    if (ch >= 65 && ch <= 90) {
      n = n * 26 + (ch - 64);
    } else if (ch >= 97 && ch <= 122) {
      n = n * 26 + (ch - 96);
    } else {
      break;
    }
  }
  return n - 1;
}

String _cellValue(XmlElement c, List<String> shared) {
  final type = c.getAttribute('t');
  if (type == 'inlineStr') {
    final is_ = c.getElement('is');
    return is_ == null ? '' : _textOf(is_).trim();
  }
  final v = c.getElement('v')?.innerText ?? '';
  switch (type) {
    case 's':
      final i = int.tryParse(v);
      return (i != null && i >= 0 && i < shared.length) ? shared[i].trim() : '';
    case 'b':
      return v == '1' ? 'TRUE' : 'FALSE';
    case 'str':
    case 'e':
      return v.trim();
    default:
      return _number(v);
  }
}

/// Renders a stored number the way a user sees it: integers without `.0`,
/// and floating-point noise such as 0.30000000000000004 rounded off.
String _number(String raw) {
  final d = double.tryParse(raw);
  if (d == null) return raw.trim();
  if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
  var s = d.toStringAsPrecision(12);
  if (s.contains('e')) return d.toString();
  if (s.contains('.')) s = s.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  return s;
}
