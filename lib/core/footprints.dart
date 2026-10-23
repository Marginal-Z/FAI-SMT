/// Part type and body size estimation for the PCB assembly drawing.
///
/// The coordinate file rarely carries body sizes, so the type comes from the
/// designator prefix and the size from package codes found in the footprint
/// name or the BOM specification (RT0201, CC0402, SOT-23, QFN24, 2520 ...).
library;

import 'dart:math' as math;

import 'part_library.dart';

/// Colour groups of the navigator legend and palette.
enum PartKind { resistor, capacitor, inductor, diode, led, transistor, ic, crystal, connector, electromech, mechanical, testPoint, fiducial, other }

class PartShape {
  const PartShape(this.kind, this.width, this.height, {this.pins = 0, this.bga = false, this.exact = false, this.model = 'generic'});

  final PartKind kind;

  /// Body length along the part's X axis and width along its Y axis, in mm.
  final double width;
  final double height;

  /// Pins per long side for ICs (0 = leadless / not drawn).
  final int pins;
  final bool bga;

  /// Size read from a package code or explicit dimensions rather than a
  /// per-type default; such bodies are the last to be shrunk when they collide.
  final bool exact;

  /// Id of the library model it is drawn as (see part_library.dart).
  final String model;

  PartShape scaled(double fw, double fh) =>
      fw >= 1 && fh >= 1 ? this : PartShape(kind, width * fw, height * fh, pins: pins, bga: bga, exact: exact, model: model);

  /// Typical body height above the board in mm, for the 3D view (0 = flat):
  /// the model's height, scaled with the body for smaller or larger sizes.
  double get bodyHeight {
    final m = partModel(model);
    if (m.bodyHeight == 0) return 0;
    final ratio = math.min(width, height) / math.min(m.width, m.height);
    return m.bodyHeight * ratio.clamp(0.5, 1.6);
  }
}

final _prefix = RegExp(r'^\d*([A-Z]+)');

/// Strong hints in a footprint / package name that override the designator.
PartKind? _footprintKind(String f) {
  if (f.isEmpty) return null;
  if (f.contains('MARK') || f.contains('FIDUCIAL')) return PartKind.fiducial;
  if (f.contains('SHIELD') || f.contains('HEATSINK')) return PartKind.mechanical;
  if (f.contains('TACT') || f.contains('BUZZER') || f.contains('RELAY')) return PartKind.electromech;
  if (f.contains('POINT') || RegExp(r'(^|[_\-])PAD').hasMatch(f) || RegExp(r'^TP[_\-\d]').hasMatch(f)) return PartKind.testPoint;
  if (f.contains('MOSFET') || f.contains('TRANSISTOR')) return PartKind.transistor;
  if (f.contains('BGA') || f.contains('DDR') || f.contains('EMMC')) return PartKind.ic;
  if (f.contains('CRYSTAL') || f.contains('OSC')) return PartKind.crystal;
  if (f.contains('INDUCTOR') || f.startsWith('L-')) return PartKind.inductor;
  if (f.contains('LED')) return PartKind.led;
  if (f.contains('DIODE') || f.startsWith('SOD')) return PartKind.diode;
  if (RegExp(r'CON|FPC|BTB|USB|HDMI|HEADER|\dPIN|-\d+PIN').hasMatch(f)) return PartKind.connector;
  return null;
}

PartKind kindOf(String ref, [String hint = '', String footprint = '']) {
  final m = _prefix.firstMatch(ref.toUpperCase());
  final p = m?.group(1) ?? '';
  final h = hint.toUpperCase();
  final strong = _footprintKind(footprint.toUpperCase());
  if (strong != null) return strong;
  // Words in the description that no designator prefix overrides.
  if (h.contains('屏蔽') || h.contains('散热片')) return PartKind.mechanical;
  if (h.contains('蜂鸣') || h.contains('继电器') || h.contains('轻触') || h.contains('麦克')) return PartKind.electromech;
  if (p.startsWith('MARK') || p.startsWith('FID') || p == 'FM') return PartKind.fiducial;
  if (p.startsWith('TP')) return PartKind.testPoint;
  if (p.startsWith('LED')) return PartKind.led;
  if (p == 'R' || p == 'RN' || p == 'RP' || p == 'VR' || p == 'RV' || p == 'RT' || p == 'NTC' || p == 'PTC') return PartKind.resistor;
  if (p == 'C' || p == 'EC' || p == 'CE' || p == 'TC') return PartKind.capacitor;
  if (p == 'L' || p == 'FB' || p == 'T') return PartKind.inductor;
  if (p == 'P' || p == 'PAD') return PartKind.testPoint;
  if (p == 'D' || p == 'ZD' || p == 'TVS') return h.contains('LED') ? PartKind.led : PartKind.diode;
  if (p == 'Q' || p == 'VT' || p == 'MOS') return PartKind.transistor;
  if (p == 'U' || p == 'IC' || p == 'N') return PartKind.ic;
  if (p == 'Y' || p == 'X' || p == 'OSC' || p == 'XTAL') return PartKind.crystal;
  if (p == 'J' || p == 'CON' || p == 'CN' || p == 'USB') return PartKind.connector;
  if (p == 'SW' || p == 'KEY' || p == 'S' || p == 'K' || p == 'RLY' || p == 'BZ' || p == 'BUZ' || p == 'MIC' || p == 'MK' || p == 'BAT' || p == 'BT') {
    return PartKind.electromech;
  }
  if (p == 'MH' || p == 'HOLE' || p == 'SH' || p == 'HS') return PartKind.mechanical;
  // Fall back to the package / description text.
  if (h.contains('电阻') || h.startsWith('RES')) return PartKind.resistor;
  if (h.contains('电容') || h.startsWith('CAP')) return PartKind.capacitor;
  if (h.contains('电感') || h.contains('磁珠')) return PartKind.inductor;
  if (h.contains('晶振')) return PartKind.crystal;
  if (h.contains('按键') || h.contains('开关') || h.contains('电池')) return PartKind.electromech;
  return PartKind.other;
}

/// Imperial chip codes → body length × width in mm.
const _chips = {
  '01005': (0.4, 0.2),
  '0201': (0.6, 0.3),
  '0402': (1.0, 0.5),
  '0603': (1.6, 0.8),
  '0805': (2.0, 1.25),
  '1206': (3.2, 1.6),
  '1210': (3.2, 2.5),
  '1812': (4.5, 3.2),
  '2010': (5.0, 2.5),
  '2512': (6.4, 3.2),
};

/// Metric two-dimension codes used for inductors / crystals (2520 = 2.5 × 2.0).
final _metric = RegExp(r'(?<!\d)(1608|2012|2016|2520|3215|3225|4020|4030|5032|6060|7050)(?!\d)');

/// Explicit body size in a footprint name: `QFN24_4X4`, `PAD_1X4MM`, `TP_1.4X2.9`.
final _dims = RegExp(r'(?<![\d.])(\d{1,2}(?:\.\d+)?)\s*X\s*(\d{1,2}(?:\.\d+)?)(?![\d.])');

/// Body of a placement: colour group, size and library model. [model]
/// forces a library model (a user rule); otherwise it is recognised from the
/// designator, footprint and description.
PartShape shapeOf(String ref, {String footprint = '', String description = '', String? model}) {
  final (base, defaulted) = _baseShape(ref, footprint, description);
  final text = '${footprint.toUpperCase()} ${description.toUpperCase()}';
  final prefix = _prefix.firstMatch(ref.toUpperCase())?.group(1) ?? '';
  final auto = modelIdFor(base.kind, prefix, text, width: base.width, height: base.height, exact: base.exact);
  final forced = model != null && isPartModel(model) && model != auto;
  final id = forced ? model : auto;
  final m = partModel(id);
  // A size guessed per type gives way to the model's typical size, and so
  // does the footprint's size when the user picked a different kind of part.
  final useModelSize = forced || (!base.exact && defaulted);
  return PartShape(
    forced ? m.kind : base.kind,
    useModelSize ? m.width : base.width,
    useModelSize ? m.height : base.height,
    pins: base.pins,
    bga: id == 'bga',
    exact: base.exact,
    model: id,
  );
}

/// Kind and size before the model is chosen; the flag is true when the size
/// is only the per-type default.
(PartShape, bool) _baseShape(String ref, String footprint, String description) {
  final fp = footprint.toUpperCase();
  final text = '$fp $description'.toUpperCase();
  final kind = kindOf(ref, text, fp);

  final dims = _dims.firstMatch(fp);
  if (dims != null) {
    final a = double.parse(dims.group(1)!), b = double.parse(dims.group(2)!);
    if (a >= 0.3 && b >= 0.3 && a <= 40 && b <= 40) {
      final pins = RegExp(r'(QFN|DFN|SON|SOP|SOIC)[_\- ]?(\d{1,3})(?!\d)').firstMatch(fp);
      final n = int.tryParse(pins?.group(2) ?? '') ?? 0;
      final square = (a - b).abs() < 0.01;
      return (
        PartShape(kind == PartKind.other ? PartKind.ic : kind, math.max(a, b), math.min(a, b),
            pins: kind == PartKind.ic || kind == PartKind.other ? (square ? (n / 4).ceil() : (n / 2).ceil()).clamp(0, 16) : 0, exact: true),
        false,
      );
    }
  }
  // Metric size codes after a leadless package name: DFN1006 = 1.0 × 0.6 mm.
  final sizeCode = RegExp(r'(?:DFN|SOD|CSP)[_\- ]?(\d{2})(\d{2})(?!\d)').firstMatch(text);
  if (sizeCode != null && kind != PartKind.ic) {
    return (PartShape(kind, int.parse(sizeCode.group(1)!) / 10, int.parse(sizeCode.group(2)!) / 10, exact: true), false);
  }

  for (final e in _chips.entries) {
    if (RegExp('(?<!\\d)${e.key}(?!\\d)').hasMatch(text) &&
        (kind == PartKind.resistor || kind == PartKind.capacitor || kind == PartKind.inductor || kind == PartKind.diode || kind == PartKind.led)) {
      return (PartShape(kind, e.value.$1, e.value.$2, exact: true), false);
    }
  }
  final metric = _metric.firstMatch(text);
  if (metric != null && kind != PartKind.ic) {
    final code = metric.group(1)!;
    return (PartShape(kind, int.parse(code.substring(0, 2)) / 10, int.parse(code.substring(2)) / 10, exact: true), false);
  }
  if (RegExp(r'BGA').hasMatch(text)) {
    final n = int.tryParse(RegExp(r'BGA[_\- ]?(\d+)').firstMatch(text)?.group(1) ?? '') ?? 96;
    final side = n >= 300 ? 14.0 : n >= 150 ? 10.0 : n >= 100 ? 8.0 : 7.0;
    return (PartShape(PartKind.ic, side, n >= 90 && n <= 100 ? side * 1.4 : side, bga: true), false);
  }
  if (RegExp(r'SOT-?23-?[56]|SOT-?26|SC-?70|SC70').hasMatch(text)) return (PartShape(kind == PartKind.other ? PartKind.ic : kind, 2.9, 1.6, pins: 3, exact: true), false);
  if (RegExp(r'SOT-?563|SOT-?363').hasMatch(text)) return (PartShape(kind == PartKind.other ? PartKind.ic : kind, 1.6, 1.2, pins: 3, exact: true), false);
  if (RegExp(r'SOT-?23|SOT23').hasMatch(text)) return (PartShape(kind == PartKind.other ? PartKind.transistor : kind, 2.9, 1.3, pins: 0, exact: true), false);
  if (RegExp(r'SOD-?523').hasMatch(text)) return (PartShape(kind, 1.2, 0.8, exact: true), false);
  if (RegExp(r'SOD-?323').hasMatch(text)) return (PartShape(kind, 1.7, 1.25, exact: true), false);
  if (RegExp(r'SOD-?123').hasMatch(text)) return (PartShape(kind, 2.7, 1.6, exact: true), false);
  if (RegExp(r'DO-?214|SMA\b|SMB\b').hasMatch(text)) return (PartShape(kind, 4.3, 2.6, exact: true), false);
  final qfn = RegExp(r'(QFN|DFN|WSON|SON|LGA)[_\- ]?(\d{1,3})?(?!\d)').firstMatch(text);
  if (qfn != null) {
    final n = int.tryParse(qfn.group(2) ?? '') ?? 16;
    final side = n <= 8 ? 3.0 : n <= 16 ? 3.0 : n <= 24 ? 4.0 : n <= 32 ? 5.0 : n <= 48 ? 7.0 : 9.0;
    return (PartShape(PartKind.ic, side, side, pins: (n / 4).ceil().clamp(2, 16)), false);
  }
  final so = RegExp(r'(MSOP|TSSOP|SSOP|SOIC|SOP|ESOP)[_\- ]?(\d{1,3})?(?!\d)').firstMatch(text);
  if (so != null) {
    final n = int.tryParse(so.group(2) ?? '') ?? 8;
    final narrow = so.group(1)!.contains('SSOP') || so.group(1) == 'MSOP';
    return (PartShape(PartKind.ic, narrow ? 3.0 + (n - 8) * 0.33 : 4.9 + (n - 8) * 0.64, narrow ? 3.0 : 3.9, pins: (n / 2).ceil()), false);
  }
  final pin = RegExp(r'(\d+)\s*\*\s*(\d+)\s*PIN|(\d+)\s*PIN').firstMatch(text);

  if (kind == PartKind.connector && pin != null) {
    final rows = int.tryParse(pin.group(1) ?? '') ?? 1;
    final n = int.tryParse(pin.group(2) ?? pin.group(3) ?? '') ?? 4;
    return (PartShape(PartKind.connector, (n * 0.8).clamp(3.0, 30.0), rows > 1 ? 3.5 : 2.5), false);
  }
  final shape = switch (kind) {
    PartKind.resistor => const PartShape(PartKind.resistor, 1.0, 0.5),
    PartKind.capacitor => const PartShape(PartKind.capacitor, 1.0, 0.5),
    PartKind.inductor => const PartShape(PartKind.inductor, 2.5, 2.0),
    PartKind.diode => const PartShape(PartKind.diode, 1.6, 0.8),
    PartKind.led => const PartShape(PartKind.led, 1.6, 0.8),
    PartKind.transistor => const PartShape(PartKind.transistor, 2.9, 1.3),
    PartKind.ic => const PartShape(PartKind.ic, 4.0, 4.0, pins: 4),
    PartKind.crystal => const PartShape(PartKind.crystal, 3.2, 2.5),
    PartKind.connector => const PartShape(PartKind.connector, 3.2, 2.5),
    PartKind.electromech => const PartShape(PartKind.electromech, 6.0, 6.0),
    PartKind.mechanical => const PartShape(PartKind.mechanical, 3.0, 3.0),
    PartKind.testPoint => const PartShape(PartKind.testPoint, 1.2, 1.2),
    PartKind.fiducial => const PartShape(PartKind.fiducial, 1.0, 1.0),
    PartKind.other => const PartShape(PartKind.other, 2.0, 1.2),
  };
  return (shape, true);
}
