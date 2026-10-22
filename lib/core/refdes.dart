/// Reference-designator (位号) helpers: splitting, range expansion, natural sort.
library;

final RegExp _separators = RegExp(r'[,，;；、/\s\|]+');
final RegExp _explicitSeparators = RegExp(r'[,，;；、]');
final RegExp _tailNumber = RegExp(r'^(.*?)(\d+)$');

/// Normalises one designator: trims, upper-cases, strips quotes.
String normalizeRef(String ref) =>
    ref.trim().replaceAll('"', '').replaceAll("'", '').toUpperCase();

/// Splits a 插件位置 / 位号 cell into individual designators.
///
/// Accepts mixed separators (`, ， ; ； 、 / space |`) and ranges written as
/// `R1-R5`, `R1~R5`, `R1-5`. A hyphenated token is expanded only when both
/// ends share the same prefix and the span is reasonable; otherwise it is kept
/// verbatim (some designators legitimately contain a hyphen).
List<String> splitRefs(String? cell) {
  if (cell == null) return const [];
  var text = cell.replaceAll('\r', '');
  // ERP exports (T100) hard-wrap long cells at a fixed width, which can split
  // a designator ("8R" / "23"). When the list already uses explicit
  // separators, a line break is such a soft wrap and is dropped; otherwise
  // it separates designators.
  if (text.contains('\n')) {
    text = _explicitSeparators.hasMatch(text) ? text.replaceAll('\n', '') : text.replaceAll('\n', ' ');
  }
  final out = <String>[];
  for (final raw in text.split(_separators)) {
    final token = normalizeRef(raw);
    if (token.isEmpty) continue;
    out.addAll(_expandRange(token));
  }
  return out;
}

List<String> _expandRange(String token) {
  final parts = token.split(RegExp(r'[-~～]'));
  if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
    return [token];
  }
  final a = _tailNumber.firstMatch(parts[0]);
  if (a == null) return [token];
  final prefix = a.group(1)!;
  final start = int.parse(a.group(2)!);
  int end;
  final b = _tailNumber.firstMatch(parts[1]);
  if (b == null) return [token];
  if (b.group(1)!.isEmpty) {
    end = int.parse(b.group(2)!);
  } else if (b.group(1) == prefix) {
    end = int.parse(b.group(2)!);
  } else {
    return [token];
  }
  if (prefix.isEmpty || end < start || end - start > 500) return [token];
  return [for (var i = start; i <= end; i++) '$prefix$i'];
}

/// Natural comparison so that R2 < R10 and 3U2 < 3U10.
int compareRefs(String a, String b) {
  final ra = RegExp(r'\d+|\D+').allMatches(a).map((m) => m.group(0)!).toList();
  final rb = RegExp(r'\d+|\D+').allMatches(b).map((m) => m.group(0)!).toList();
  for (var i = 0; i < ra.length && i < rb.length; i++) {
    final x = ra[i], y = rb[i];
    final nx = int.tryParse(x), ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return ra.length.compareTo(rb.length);
}

/// Joins text that an export wrapped across lines (Chinese descriptions are
/// wrapped mid-word, so no space is inserted).
String unwrapText(String s) => s.replaceAll(RegExp(r'\s*[\r\n]+\s*'), '').trim();

List<String> sortedRefs(Iterable<String> refs) =>
    refs.toSet().toList()..sort(compareRefs);
