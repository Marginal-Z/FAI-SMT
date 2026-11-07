/// What an item is (resistor, connector, packaging …) and whether it is
/// marked not fitted, from its description, designators and units, using
/// the general knowledge in knowledge.dart.
library;

import 'knowledge.dart';

// Short Latin-script words match whole words ("led" is not in "shielded");
// longer ones also inside compounds ("Keramikkondensator"); other scripts
// anywhere.
final _phrases = <(RegExp, int, ItemKind)>[
  for (final e in kindWords.entries)
    for (final w in e.value)
      (
        RegExp(!w.codeUnits.every((u) => u < 0x250) || w.length >= 6 ? RegExp.escape(w) : '(?<![a-z0-9])${RegExp.escape(w)}(?![a-z])'),
        w.length,
        e.key,
      ),
];

final _prefix = RegExp(r'^\d*([A-Z]+)');
final _icPackage = RegExp(r'(?<![A-Za-z])(QFN|DFN|QFP|LQFP|TQFP|BGA|FBGA|LGA|SOIC|SOP|SSOP|TSSOP|MSOP|WLCSP)[-\s]?(\d{1,4})(?!\d)', caseSensitive: false);

/// The kind of an item and what decided it: `words`, `designator` or
/// `unit`; unknown when nothing does.
(ItemKind, String) classifyItem(String description, List<String> refs) {
  final text = description.toLowerCase();
  // Words: the longest phrase found wins ("esd bag" over "esd").
  ItemKind? byWords;
  var longest = 0;
  for (final (re, len, kind) in _phrases) {
    if (len > longest && re.hasMatch(text)) {
      longest = len;
      byWords = kind;
    }
  }
  if (byWords != null) return (byWords, 'words');
  // Designators: the prefix most of them share.
  if (refs.isNotEmpty) {
    final votes = <ItemKind, int>{};
    for (final r in refs) {
      final m = _prefix.firstMatch(r.toUpperCase());
      if (m == null) continue;
      final p = m.group(1)!;
      for (final e in designatorKinds.entries) {
        if (p == e.key || (p.startsWith(e.key) && e.key.length >= 2)) {
          votes[e.value] = (votes[e.value] ?? 0) + 1;
          break;
        }
      }
    }
    if (votes.isNotEmpty) {
      final best = votes.entries.reduce((a, b) => a.value >= b.value ? a : b);
      if (best.value * 2 > refs.length) return (best.key, 'designator');
    }
  }
  for (final e in unitKinds.entries) {
    if (e.key.hasMatch(description)) return (e.value, 'unit');
  }
  // An IC package with six or more pins (QFN16, LQFP48, SOIC8, BGA128).
  final pkg = _icPackage.firstMatch(description);
  if (pkg != null && int.parse(pkg.group(2)!) >= 6) return (ItemKind.ic, 'package');
  return (ItemKind.unknown, '');
}

final _dnpPhrases = [
  for (final w in dnpWords)
    RegExp(w.codeUnits.every((u) => u < 0x250) ? '(?<![a-z0-9])${RegExp.escape(w)}(?![a-z0-9])' : RegExp.escape(w)),
];

/// Text marking a line as not fitted ("DNP", "NC", "不贴" …).
bool isDnpText(String text) {
  final t = text.toLowerCase().trim();
  if (t.isEmpty) return false;
  return _dnpPhrases.any((re) => re.hasMatch(t));
}
