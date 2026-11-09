/// Assembly reminders inferred from BOM evidence, never an angle verdict.
library;

import 'bom_model.dart';
import 'classify.dart';
import 'refdes.dart';

class OrientationHint {
  const OrientationHint(this.code, this.evidence, this.refs);
  final String code;
  final String evidence;
  final List<String> refs;
}

/// Include every source description on both sides after grouping by PN.
List<OrientationHint> orientationHints(Iterable<BomPart> parts) {
  final hints = <String, (Set<String>, Set<String>)>{};
  void add(String code, BomPart p) {
    final v = hints.putIfAbsent(code, () => (<String>{}, <String>{}));
    v.$1.add('${p.partNo}: ${p.description.isEmpty ? p.refs.join(', ') : p.description}');
    v.$2.addAll(p.refs);
  }
  final originals = parts.expand((p) => p.sourceDescriptions.length < 2 ? [p] : [
    for (final desc in p.sourceDescriptions) BomPart(p.partNo, description: desc, quantity: p.quantity, refs: p.refs, extra: p.extra, sources: p.sources, dnp: p.dnp),
  ]);
  for (final p in originals) {
    if (p.dnp || p.quantity == 0) continue;
    final text = '${p.description} ${p.extra.values.join(' ')}';
    final kind = p.kind == ItemKind.unknown ? classifyItem(text, p.refs).$1 : p.kind;
    final nonPolar = RegExp(r'无极性|非极性|双极性|双向|\b(?:non[- ]?polar(?:ized)?|bipolar|bi[- ]?directional)\b', caseSensitive: false).hasMatch(text);
    final polarCap = RegExp(r'钽|电解|有极性|\b(?:tantalum|electrolytic|polarized)\b', caseSensitive: false).hasMatch(text);
    if (kind == ItemKind.capacitor) {
      if (!nonPolar && polarCap) { add('polar_cap', p); }
      if (!nonPolar && !polarCap && !RegExp(r'陶瓷|瓷片|薄膜|\b(?:mlcc|ceramic|film)\b|\b(?:X[5678][RST]|C0G|NP0|NPO)\b', caseSensitive: false).hasMatch(text)) { add('cap_unknown', p); }
    } else if (kind == ItemKind.diode || kind == ItemKind.led) {
      add(nonPolar && kind == ItemKind.diode ? 'bidirectional' : 'diode', p);
    } else if (kind == ItemKind.ic || kind == ItemKind.transistor) {
      add('pin1', p);
    } else if (const [ItemKind.connector, ItemKind.switchKind, ItemKind.relay, ItemKind.sensor, ItemKind.module, ItemKind.transformer].contains(kind)) {
      add('mechanical', p);
    } else if (kind == ItemKind.battery || kind == ItemKind.speaker) {
      add('supply', p);
    } else if (kind == ItemKind.crystal) {
      add('crystal', p);
    } else if (kind == ItemKind.unknown) {
      add('unknown', p);
    }
    if (RegExp(r'排阻|排容|电阻网络|\b(?:resistor\s+(?:array|network)|capacitor\s+array)\b', caseSensitive: false).hasMatch(text)) { add('pin1', p); }
  }
  return [for (final e in hints.entries) OrientationHint(e.key, e.value.$1.join('\n'), sortedRefs(e.value.$2))];
}
