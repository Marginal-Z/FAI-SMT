/// Reads spreadsheet-like files (xlsx / csv / txt) into a plain string grid.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';

import 'xlsx_reader.dart';

class TableReadException implements Exception {
  TableReadException(this.code, [this.detail = '']);

  /// Stable code used for localisation: `xls_unsupported`, `empty`, `read_failed`.
  final String code;
  final String detail;

  @override
  String toString() => 'TableReadException($code) $detail';
}

/// One sheet as rows of trimmed strings, with its merged cell ranges.
class Grid {
  Grid(this.name, this.rows, {this.merges = const []});

  final String name;
  final List<List<String>> rows;

  /// Merged ranges as 0-based (first row, first column, last row, last
  /// column); only the first cell of a range holds the value.
  final List<(int, int, int, int)> merges;

  late final Map<int, (int, int, int, int)> _mergeAt = {
    for (final m in merges)
      for (var r = m.$1; r <= m.$3 && r - m.$1 < 2000; r++)
        for (var c = m.$2; c <= m.$4 && c - m.$2 < 200; c++) r * 65536 + c: m,
  };

  String cell(int r, int c) =>
      (r < rows.length && c < rows[r].length) ? rows[r][c] : '';

  /// The merged range (r, c) lies in, if any.
  (int, int, int, int)? mergeAt(int r, int c) => merges.isEmpty ? null : _mergeAt[r * 65536 + c];

  /// What is shown at (r, c): a merged cell shows its range's value.
  String shown(int r, int c) {
    final m = mergeAt(r, c);
    return m == null ? cell(r, c) : cell(m.$1, m.$2);
  }
}

Future<List<Grid>> readTableFile(String path) async {
  final bytes = await File(path).readAsBytes();
  return readTableBytes(bytes, path);
}

List<Grid> readTableBytes(Uint8List bytes, String nameHint) {
  final lower = nameHint.toLowerCase();
  if (lower.endsWith('.xlsx') || lower.endsWith('.xlsm') || _isZip(bytes)) {
    return _readXlsx(bytes);
  }
  if (lower.endsWith('.xls') || _isOle(bytes)) {
    throw TableReadException('xls_unsupported');
  }
  final text = decodeText(bytes);
  return [Grid('text', parseDelimited(text))];
}

bool _isZip(Uint8List b) => b.length > 4 && b[0] == 0x50 && b[1] == 0x4B;
bool _isOle(Uint8List b) =>
    b.length > 8 && b[0] == 0xD0 && b[1] == 0xCF && b[2] == 0x11 && b[3] == 0xE0;

List<Grid> _readXlsx(Uint8List bytes) {
  final List<XlsxSheet> sheets;
  try {
    sheets = readXlsx(bytes);
  } catch (e) {
    throw TableReadException('read_failed', '$e');
  }
  final grids = <Grid>[];
  for (final sh in sheets) {
    final rows = sh.rows;
    while (rows.isNotEmpty && rows.last.every((s) => s.isEmpty)) {
      rows.removeLast();
    }
    if (rows.isNotEmpty) grids.add(Grid(sh.name, rows, merges: sh.merges));
  }
  if (grids.isEmpty) throw TableReadException('empty');
  return grids;
}

/// Decodes text as UTF-8 (with or without BOM), UTF-16 (BOM), or GBK.
String decodeText(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3), allowMalformed: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _utf16(bytes.sublist(2), little: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _utf16(bytes.sublist(2), little: false);
  }
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return gbk.decode(bytes);
  }
}

String _utf16(Uint8List b, {required bool little}) {
  final units = <int>[];
  for (var i = 0; i + 1 < b.length; i += 2) {
    units.add(little ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]);
  }
  return String.fromCharCodes(units);
}

/// Splits delimited text. The delimiter is guessed per file from
/// tab / comma / semicolon, falling back to runs of whitespace.
List<List<String>> parseDelimited(String text) {
  final lines = const LineSplitter().convert(text);
  final sample = lines.where((l) => l.trim().isNotEmpty).take(30).toList();
  final quotedBreak = RegExp(r'"[^"]*\n').hasMatch(text.replaceAll('\r\n', '\n'));
  String? delim;
  var best = 0;
  for (final d in ['\t', ',', ';']) {
    final n = sample.where((l) => l.contains(d)).length;
    if (n > best) {
      best = n;
      delim = d;
    }
  }
  if (best < sample.length ~/ 2) delim = null;
  // A quoted field holding a line break: parse the text as a whole.
  if (delim != null && quotedBreak) return _parseCsv(text.replaceAll('\r\n', '\n'), delim);
  final rows = <List<String>>[];
  for (final line in lines) {
    if (line.trim().isEmpty) {
      rows.add(const []);
      continue;
    }
    rows.add(delim == null
        ? _splitWhitespace(line)
        : _splitQuoted(line, delim).map((s) => s.trim()).toList());
  }
  return rows;
}

/// RFC 4180 style: quotes may hold delimiters, doubled quotes and line
/// breaks; one row per record.
List<List<String>> _parseCsv(String text, String delim) {
  final rows = <List<String>>[];
  var row = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  void endField() {
    row.add(buf.toString().trim());
    buf.clear();
  }

  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (quoted) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          quoted = false;
        }
      } else {
        buf.write(ch);
      }
    } else if (ch == '"') {
      quoted = true;
    } else if (ch == delim) {
      endField();
    } else if (ch == '\n') {
      endField();
      rows.add(row.every((s) => s.isEmpty) ? const [] : row);
      row = <String>[];
    } else {
      buf.write(ch);
    }
  }
  if (buf.isNotEmpty || row.isNotEmpty) {
    endField();
    rows.add(row);
  }
  return rows;
}

final RegExp _wsToken = RegExp(r'"([^"]*)"|(\S+)');

List<String> _splitWhitespace(String line) => [
      for (final m in _wsToken.allMatches(line)) (m.group(1) ?? m.group(2)!).trim()
    ];

List<String> _splitQuoted(String line, String delim) {
  final out = <String>[];
  final buf = StringBuffer();
  var quoted = false;
  for (var i = 0; i < line.length; i++) {
    final ch = line[i];
    if (ch == '"') {
      if (quoted && i + 1 < line.length && line[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        quoted = !quoted;
      }
    } else if (ch == delim && !quoted) {
      out.add(buf.toString());
      buf.clear();
    } else {
      buf.write(ch);
    }
  }
  out.add(buf.toString());
  return out;
}
