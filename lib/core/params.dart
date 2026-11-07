/// Parameters read from part descriptions and normalised so the program
/// can decide for itself whether two values are the same: 10K = 10kΩ =
/// 10000R, 0.1uF = 100nF, 4K7 = 4.7kΩ, 1/16W = 62.5mW, SOT23 = SOT-23.
library;

import 'dart:math' as math;

enum ParamKind { resistance, capacitance, inductance, voltage, current, power, frequency, tolerance, tempco, dielectric, size, package, other }

/// One parameter: kind, value in base units (Ω, F, H, V, A, W, Hz, % or
/// ppm) or a normalised text form, and where it was written.
class Param {
  const Param(this.kind, this.text, {this.value, this.key = '', required this.start, required this.end});

  final ParamKind kind;

  /// As written.
  final String text;

  /// Numeric value in base units, when numeric.
  final double? value;

  /// Normalised form of a non-numeric parameter (`X7R`, `SOT-23`, `0402`).
  final String key;
  final int start;
  final int end;

  /// Same parameter, by value or normalised form.
  bool sameAs(Param o) {
    if (kind != o.kind) return false;
    if (value != null && o.value != null) return (value! - o.value!).abs() <= 1e-9 * math.max(value!.abs(), o.value!.abs()) + 1e-15;
    return key == o.key;
  }

  @override
  String toString() => '${kind.name}:${value == null ? key : double.parse(value!.toStringAsPrecision(6))}';
}

const _prefix = {'p': 1e-12, 'n': 1e-9, 'u': 1e-6, 'µ': 1e-6, 'μ': 1e-6, 'm': 1e-3, '': 1.0, 'k': 1e3, 'K': 1e3, 'M': 1e6, 'G': 1e9};

// Value with SI prefix and unit, e.g. 100nF, 0.1 uF, 2.2uH, 16V, 500mA,
// 24MHz, 10kΩ, 10Kohm.
// A value inside a hyphenated code (K1102-1020K0-001A) is not one.
final _withUnit = RegExp(r'(?<![A-Za-z0-9.\-])(\d+(?:[.,]\d+)?)\s?([pnuµμmkKMG]?)(Ω|ohms?|OHMS?|Ohms?|R|F|H|V|A|W|Hz|HZ|hz)(?![A-Za-z0-9\-])');
// Resistor code letters: 4K7, 4R7, 2M2, 10K, 0R, 10R.
final _rCode = RegExp(r'(?<![A-Za-z0-9.\-])(\d+)([RKM])(\d*)(?![A-Za-z0-9\-])');
// Fractional power: 1/16W, 1/10 W.
final _fracW = RegExp(r'(?<![\d.])(\d+)\s?/\s?(\d+)\s?W(?![A-Za-z])', caseSensitive: false);
final _tol = RegExp(r'±\s?(\d+(?:\.\d+)?)\s?%|(?<![\d.])(\d+(?:\.\d+)?)\s?%');
final _ppm = RegExp(r'(?<![\d.])(\d+(?:\.\d+)?)\s?ppm', caseSensitive: false);
final _dielectric = RegExp(r'(?<![A-Za-z0-9])(X5R|X7R|X7S|X6S|X8R|Y5V|Z5U|C0G|NP0|NPO|COG)(?![A-Za-z0-9])', caseSensitive: false);
final _size = RegExp(r'(?<![\d.xX])(01005|0201|0402|0603|0805|1206|1210|1812|2010|2512)(?![\d.])');
final _package = RegExp(r'(?<![A-Za-z0-9])(SOT|SOD|SOIC|SOP|SSOP|TSSOP|MSOP|QFN|DFN|QFP|LQFP|TQFP|BGA|FBGA|LGA|TO|DO|SMA|SMB|SMC|SC|WLCSP|CSP|DIP)[-\s]?(\d{1,4}[A-Z]?(?:-\d{1,2})?)?(?![A-Za-z0-9])', caseSensitive: false);

double _num(String s) => double.parse(s.replaceAll(',', '.'));

ParamKind _unitKind(String unit) => switch (unit.toLowerCase()) {
  'ω' || 'ohm' || 'ohms' || 'r' => ParamKind.resistance,
  'f' => ParamKind.capacitance,
  'h' => ParamKind.inductance,
  'v' => ParamKind.voltage,
  'a' => ParamKind.current,
  'w' => ParamKind.power,
  _ => ParamKind.frequency,
};

/// Parameters of a description, in order of appearance, without overlaps.
List<Param> extractParams(String text) {
  final out = <Param>[];
  bool free(int s, int e) => out.every((p) => e <= p.start || s >= p.end);
  void add(Param p) {
    if (free(p.start, p.end)) out.add(p);
  }

  for (final m in _fracW.allMatches(text)) {
    final d = int.parse(m.group(2)!);
    if (d == 0) continue;
    add(Param(ParamKind.power, m.group(0)!, value: int.parse(m.group(1)!) / d, start: m.start, end: m.end));
  }
  for (final m in _withUnit.allMatches(text)) {
    final unit = m.group(3)!;
    final prefix = m.group(2)!;
    // "16V" yes; "1R" is a resistor code handled below; "mR" is milliohm.
    if (unit == 'R' && prefix.isEmpty) continue;
    final kind = _unitKind(unit);
    // "M" before Hz/F/H is mega for Hz, but "MF" is not used for megafarad.
    final scale = _prefix[prefix] ?? 1;
    add(Param(kind, m.group(0)!, value: _num(m.group(1)!) * scale, start: m.start, end: m.end));
  }
  for (final m in _rCode.allMatches(text)) {
    final whole = m.group(1)!, letter = m.group(2)!, frac = m.group(3)!;
    final scale = switch (letter) { 'K' => 1e3, 'M' => 1e6, _ => 1.0 };
    final v = double.parse(frac.isEmpty ? whole : '$whole.$frac') * scale;
    add(Param(ParamKind.resistance, m.group(0)!, value: v, start: m.start, end: m.end));
  }
  for (final m in _tol.allMatches(text)) {
    add(Param(ParamKind.tolerance, m.group(0)!, value: _num(m.group(1) ?? m.group(2)!), start: m.start, end: m.end));
  }
  for (final m in _ppm.allMatches(text)) {
    add(Param(ParamKind.tempco, m.group(0)!, value: _num(m.group(1)!), start: m.start, end: m.end));
  }
  for (final m in _dielectric.allMatches(text)) {
    var k = m.group(1)!.toUpperCase();
    if (k == 'NPO' || k == 'NP0' || k == 'COG') k = 'C0G';
    add(Param(ParamKind.dielectric, m.group(0)!, key: k, start: m.start, end: m.end));
  }
  for (final m in _size.allMatches(text)) {
    add(Param(ParamKind.size, m.group(0)!, key: m.group(1)!, start: m.start, end: m.end));
  }
  for (final m in _package.allMatches(text)) {
    final fam = m.group(1)!.toUpperCase(), n = (m.group(2) ?? '').toUpperCase();
    add(Param(ParamKind.package, m.group(0)!, key: n.isEmpty ? fam : '$fam-$n', start: m.start, end: m.end));
  }
  out.sort((a, b) => a.start - b.start);
  return out;
}

enum ParamVerdict {
  /// Every parameter matches by value or form.
  same,

  /// One side names a parameter the other leaves out; nothing conflicts.
  incomplete,

  /// At least one parameter of the same kind has another value.
  conflict,
}

class ParamComparison {
  ParamComparison(this.verdict, this.matched, this.conflicts, this.onlyA, this.onlyB);

  final ParamVerdict verdict;
  final List<(Param, Param)> matched;
  final List<(Param, Param)> conflicts;
  final List<Param> onlyA;
  final List<Param> onlyB;
}

/// Compares the parameters of two descriptions kind by kind.
ParamComparison compareParams(String a, String b) {
  final pa = extractParams(a), pb = extractParams(b);
  final matched = <(Param, Param)>[], conflicts = <(Param, Param)>[];
  final restB = [...pb];
  final onlyA = <Param>[];
  for (final x in pa) {
    final same = restB.where((y) => x.sameAs(y)).firstOrNull;
    if (same != null) {
      matched.add((x, same));
      restB.remove(same);
      continue;
    }
    onlyA.add(x);
  }
  // A kind present on both sides with no match is a conflict.
  final onlyAFinal = <Param>[];
  for (final x in onlyA) {
    final other = restB.where((y) => y.kind == x.kind).firstOrNull;
    if (other != null) {
      conflicts.add((x, other));
      restB.remove(other);
    } else {
      onlyAFinal.add(x);
    }
  }
  final verdict = conflicts.isNotEmpty
      ? ParamVerdict.conflict
      : (onlyAFinal.isNotEmpty || restB.isNotEmpty ? ParamVerdict.incomplete : ParamVerdict.same);
  return ParamComparison(verdict, matched, conflicts, onlyAFinal, restB);
}
