/// Safety-relevant wording that must not disappear with generic nouns.
library;

const _traits = <String, Map<String, String>>{
  'colour': {
    'red': r'红(?!外)|\bred\b',
    'green': r'绿|\bgreen\b',
    'blue': r'蓝|\bblue\b',
    'yellow': r'黄|\byellow\b',
    'white': r'白|\bwhite\b',
    'black': r'黑|\bblack\b',
    'orange': r'橙|\borange\b',
    'violet': r'紫|\b(?:violet|purple)\b',
  },
  'polarity': {
    'nonpolar': r'无极性|非极性|双极性|\b(?:non[- ]?polar(?:ized)?|bipolar)\b',
    'polar': r'有极性|(?<!non-)(?<!non )\bpolarized\b',
  },
  'capacitorType': {
    'ceramic': r'陶瓷|瓷片|\b(?:ceramic|mlcc)\b',
    'tantalum': r'钽|\btantalum\b',
    'electrolytic': r'电解|\belectrolytic\b',
    'film': r'薄膜电容|\bfilm\s+capacitor\b',
  },
};
final _patterns = [
  for (final group in _traits.entries)
    for (final e in group.value.entries)
      (group.key, e.key, RegExp(e.value, caseSensitive: false)),
];

bool sameDescriptionTraits(String a, String b) {
  final x = descriptionTraits(a).values, y = descriptionTraits(b).values;
  return x.length == y.length && x.entries.every((e) => y[e.key] != null && e.value.length == y[e.key]!.length && e.value.containsAll(y[e.key]!));
}

({Map<String, Set<String>> values, List<(int, int)> spans}) descriptionTraits(
  String text,
) {
  final values = <String, Set<String>>{};
  final spans = <(int, int)>[];
  for (final (group, value, re) in _patterns) {
    for (final m in re.allMatches(text)) {
      (values[group] ??= {}).add(value);
      spans.add((m.start, m.end));
    }
  }
  // Tantalum electrolytic is one technology, not two conflicting types.
  if (!values.containsKey('capacitorType') && RegExp(r'\b(?:X[5678][RST]|C0G|COG|NP0|NPO)\b', caseSensitive: false).hasMatch(text)) {
    values['capacitorType'] = {'ceramic'};
  }
  if (values['capacitorType']?.contains('tantalum') ?? false) {
    values['capacitorType']!.remove('electrolytic');
  }
  return (values: values, spans: spans);
}
