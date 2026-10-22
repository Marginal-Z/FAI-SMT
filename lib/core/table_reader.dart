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

/// One sheet as rows of trimmed strings.
class Grid {
  Grid(this.name, this.rows);

  final String name;
  final List<List<String>> rows;

  String cell(int r, int c) =>
      (r < rows.length && c < rows[r].length) ? rows[r][c] : '';
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
    if (rows.isNotEmpty) grids.add(Grid(sh.name, rows));
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
