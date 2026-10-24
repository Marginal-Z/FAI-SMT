/// Part type and body size estimation for the PCB assembly drawing.
///
/// The coordinate file rarely carries body sizes, so the type comes from the
/// designator prefix and the size from package codes found in the footprint
/// name or the BOM specification (RT0201, CC0402, SOT-23, QFN24, 2520 ...).
library;

import 'dart:math' as math;

import 'package_parser.dart';
import 'part_library.dart';

/// Colour groups of the navigator legend and palette.
enum PartKind { resistor, capacitor, inductor, diode, led, transistor, ic, crystal, connector, electromech, mechanical, testPoint, fiducial, other }

class PartShape {
  const PartShape(this.kind, this.width, this.height, {this.pins = 0, this.rows = 0, this.bga = false, this.exact = false, this.model = 'generic'});

  final PartKind kind;

  /// Body length along the part's X axis and width along its Y axis, in mm.
  final double width;
  final double height;

  /// Total pin / contact count read from the package (0 = not known; the
  /// model then draws its usual number).
  final int pins;

  /// Contact rows of a connector (0 = the model's usual).
  final int rows;
  final bool bga;

  /// Size read from a package code or explicit dimensions rather than a
  /// per-type default; such bodies are the last to be shrunk when they collide.
  final bool exact;

  /// Id of the library model it is drawn as (see part_library.dart).
  final String model;

  /// The same part drawn [fw] × [fh] times its size; pins stay.
  PartShape scaled(double fw, double fh) =>
      fw >= 1 && fh >= 1 ? this : PartShape(kind, width * fw, height * fh, pins: pins, rows: rows, bga: bga, exact: exact, model: model);

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
  // Words in the description that neither footprint nor prefix overrides.
  if (RegExp(r'屏蔽[框罩盖]|散热片|螺柱|铜柱|螺母|STANDOFF').hasMatch(h)) return PartKind.mechanical;
  var strong = _footprintKind(footprint.toUpperCase());
  // MARK in a footprint name means a fiducial only when nothing names a part.
  if (strong == PartKind.fiducial && (RegExp(r'电阻|电容|电感|二极管|晶振|芯片|IC').hasMatch(h) || const {'R', 'C', 'L', 'D', 'Q', 'U'}.contains(p))) {
    strong = null;
  }
  if (strong != null) return strong;
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

/// Power inductor size-and-height codes (4020 = 4.0 × 4.0 mm, 2.0 mm high).
final _powerInductor = RegExp(r'(?<!\d)(30(?:12|15|20)|40(?:12|18|20|25|30)|50(?:20|40)|60(?:20|28|45)|80(?:40|50))(?!\d)');

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
    rows: base.rows,
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
  var kind = kindOf(ref, text, fp);
  final info = parsePackage(footprint, description);
  final isIcFamily = const {'SOIC', 'TSSOP', 'MSOP', 'SSOP', 'QFN', 'DFN', 'QFP', 'BGA', 'CSP', 'LGA'}.contains(info.family);
  if (kind == PartKind.other && isIcFamily) kind = PartKind.ic;
  if (kind == PartKind.other && info.family.startsWith('SOT') || kind == PartKind.other && info.family == 'SC70') kind = PartKind.transistor;
  final pins = info.pins;
  PartShape sized(double a, double b, {bool exact = true, bool bga = false}) =>
      PartShape(kind, math.max(a, b), math.min(a, b), pins: pins, rows: info.rows, exact: exact, bga: bga);

  // A written-out body size wins.
  if (info.hasBody && !RegExp(r'螺柱|铜柱|螺母|STANDOFF').hasMatch(text)) return (sized(info.length, info.width, bga: info.family == 'BGA'), false);

  // Metric size codes after a leadless package name: DFN1006 = 1.0 × 0.6 mm.
  final sizeCode = RegExp(r'(?:DFN|SOD|CSP)[_\- ]?(\d{2})(\d{2})(?!\d)').firstMatch(text);
  if (sizeCode != null && kind != PartKind.ic) {
    return (PartShape(kind, int.parse(sizeCode.group(1)!) / 10, int.parse(sizeCode.group(2)!) / 10, pins: pins, exact: true), false);
  }

  for (final e in _chips.entries) {
    if (RegExp('(?<!\\d)${e.key}(?!\\d)').hasMatch(text) &&
        (kind == PartKind.resistor || kind == PartKind.capacitor || kind == PartKind.inductor || kind == PartKind.diode || kind == PartKind.led)) {
      return (PartShape(kind, e.value.$1, e.value.$2, pins: pins, exact: true), false);
    }
  }
  // Power inductor codes give the square side and the height: 4020 is
  // 4.0 × 4.0 mm, 2.0 mm high.
  if (kind == PartKind.inductor) {
    final power = _powerInductor.firstMatch(text);
    if (power != null) {
      final side = int.parse(power.group(1)!.substring(0, 2)) / 10;
      return (PartShape(kind, side, side, exact: true), false);
    }
    // Length, width and height codes: 252012 = 2.5 × 2.0 × 1.2 mm.
    final lwh = RegExp(r'(?<!\d)(\d{2})(\d{2})(\d{2})(?!\d)').firstMatch(text);
    if (lwh != null) {
      final a = int.parse(lwh.group(1)!) / 10, b = int.parse(lwh.group(2)!) / 10;
      if (a >= 1 && b >= 0.5 && a <= 15 && b <= 15) return (PartShape(kind, math.max(a, b), math.min(a, b), exact: true), false);
    }
    // Molded power inductors written 0420, 0530: 4.0 / 5.0 mm square.
    final molded = RegExp(r'(?<!\d)0([3-9])([1-6]\d)(?!\d)').firstMatch(text);
    if (molded != null) {
      final side = int.parse(molded.group(1)!).toDouble();
      return (PartShape(kind, side, side, exact: true), false);
    }
  }
  final metric = _metric.firstMatch(text);
  if (metric != null && kind != PartKind.ic && kind != PartKind.connector) {
    final code = metric.group(1)!;
    return (PartShape(kind, int.parse(code.substring(0, 2)) / 10, int.parse(code.substring(2)) / 10, pins: pins, exact: true), false);
  }

  // Package families sized from their pin count and standard pitch.
  final semiconductor = const {PartKind.ic, PartKind.transistor, PartKind.diode, PartKind.led, PartKind.other}.contains(kind);
  final family = semiconductor ? _familySize(info) : null;
  if (family != null) return (sized(family.$1, family.$2, bga: info.family == 'BGA'), false);

  // Standoffs and nuts: M2 is about 3.5 mm across.
  if (kind == PartKind.mechanical) {
    final thread = RegExp(r'(?<![A-Z])M(\d(?:\.\d)?)(?![\d.])').firstMatch(text);
    if (thread != null && RegExp(r'螺柱|铜柱|螺母|STANDOFF').hasMatch(text)) {
      final d = double.parse(thread.group(1)!) * 1.75;
      return (PartShape(kind, d, d, exact: true), false);
    }
  }

  if (RegExp(r'SOD-?523').hasMatch(text)) return (PartShape(kind, 1.2, 0.8, exact: true), false);
  if (RegExp(r'SOD-?323').hasMatch(text)) return (PartShape(kind, 1.7, 1.25, exact: true), false);
  if (RegExp(r'SOD-?123').hasMatch(text)) return (PartShape(kind, 2.7, 1.6, exact: true), false);
  if (RegExp(r'DO-?214|SMA\b|SMB\b').hasMatch(text)) return (PartShape(kind, 4.3, 2.6, exact: true), false);

  // RF coaxial sockets have a fixed small body whatever their pin count.
  if (kind == PartKind.connector && RegExp(r'IPEX|U\.FL|UFL|MHF|射频|同轴').hasMatch(text)) return (const PartShape(PartKind.connector, 3.0, 3.0), true);
  // Connectors: contacts × pitch set the length, the family the depth.
  if (kind == PartKind.connector && pins > 0) return (_connector(text, info), false);

  final shape = switch (kind) {
    PartKind.resistor => const PartShape(PartKind.resistor, 1.0, 0.5),
    PartKind.capacitor => const PartShape(PartKind.capacitor, 1.0, 0.5),
    PartKind.inductor => const PartShape(PartKind.inductor, 2.5, 2.0),
    PartKind.diode => const PartShape(PartKind.diode, 1.6, 0.8),
    PartKind.led => const PartShape(PartKind.led, 1.6, 0.8),
    PartKind.transistor => const PartShape(PartKind.transistor, 2.9, 1.3),
    PartKind.ic => const PartShape(PartKind.ic, 4.0, 4.0),
    PartKind.crystal => const PartShape(PartKind.crystal, 3.2, 2.5),
    PartKind.connector => const PartShape(PartKind.connector, 3.2, 2.5),
    PartKind.electromech => const PartShape(PartKind.electromech, 6.0, 6.0),
    PartKind.mechanical => const PartShape(PartKind.mechanical, 3.0, 3.0),
    PartKind.testPoint => const PartShape(PartKind.testPoint, 1.2, 1.2),
    PartKind.fiducial => const PartShape(PartKind.fiducial, 1.0, 1.0),
    PartKind.other => const PartShape(PartKind.other, 2.0, 1.2),
  };
  return (PartShape(shape.kind, shape.width, shape.height, pins: pins, rows: info.rows), true);
}

/// Common LQFP / TQFP body sides by pin count.
const _qfpSide = {32: 7.0, 44: 10.0, 48: 7.0, 52: 10.0, 64: 10.0, 80: 12.0, 100: 14.0, 128: 14.0, 144: 20.0, 176: 24.0, 208: 28.0};

/// Body length × width of a package family from its pin count, standard
/// pitch and standard body widths; null when the family is not known.
(double, double)? _familySize(PackageInfo info) {
  // A stray "5MM" is not an IC pitch.
  final p = info.pitch > 1.27 ? PackageInfo(family: info.family, pins: info.pins) : info;
  final n = p.pins;
  double run(int perSide, double pitch, double ends) => math.max(perSide - 1, 0) * pitch + ends;
  switch (p.family) {
    case 'SOT23':
      return n <= 3 ? (2.9, 1.3) : (2.9, 1.6);
    case 'SOT523':
      return (1.6, 0.8);
    case 'SC70':
      return n <= 3 ? (2.0, 1.25) : (2.0, 1.25);
    case 'SOT363':
      return (1.6, 1.2);
    case 'SOT89':
      return (4.5, 2.5);
    case 'SOT223':
      return (6.5, 3.5);
    case 'SOIC':
      if (n == 0) return (4.9, 3.9);
      final pitch = p.pitch > 0 ? p.pitch : 1.27;
      return (run(n ~/ 2, pitch, 1.1), n > 16 ? 7.5 : 3.9);
    case 'TSSOP':
      if (n == 0) return (5.0, 4.4);
      return (math.max(3.0, run(n ~/ 2, p.pitch > 0 ? p.pitch : 0.65, 0.65)), n > 28 ? 6.1 : 4.4);
    case 'MSOP':
      if (n <= 10) return (3.0, 3.0);
      return (run(n ~/ 2, p.pitch > 0 ? p.pitch : 0.5, 0.5), 3.0);
    case 'SSOP':
      return (run(math.max(n, 8) ~/ 2, p.pitch > 0 ? p.pitch : 0.65, 1.3), 5.3);
    case 'QFN' || 'LGA':
      if (n == 0) return null;
      final side = (n / 4).ceil() * (p.pitch > 0 ? p.pitch : (n > 48 ? 0.4 : 0.5)) + 1.0;
      return (side, side);
    case 'DFN':
      if (n == 0) return null;
      final len = math.max(2.0, (n / 2).ceil() * (p.pitch > 0 ? p.pitch : 0.5) + 1.0);
      return (len, math.max(2.0, len * 0.66));
    case 'QFP':
      if (_qfpSide[n] case final side?) return (side, side);
      if (n == 0) return null;
      final side = (n / 4).ceil() * (p.pitch > 0 ? p.pitch : 0.5) + 1.5;
      return (side, side);
    case 'BGA':
      final side = n >= 300 ? 14.0 : n >= 150 ? 11.5 : n >= 100 ? 8.0 : 7.0;
      return (side, n >= 90 && n <= 100 ? side * 1.4 : side);
    case 'CSP':
      if (n == 0) return null;
      // Balls on a 0.4 mm grid.
      final side = math.sqrt(n) * 0.4 + 0.4;
      return (side, side);
  }
  return null;
}

/// Connector body from its contacts, rows and pitch.
PartShape _connector(String text, PackageInfo info) {
  final btb = RegExp(r'BTB|板对板|BOARD TO BOARD').hasMatch(text);
  final fpc = RegExp(r'FPC|FFC|翻盖|抽屉').hasMatch(text);
  final header = RegExp(r'HEADER|排针|排母|PINHEADER|PIN_HEADER').hasMatch(text);
  final rows = info.rows > 0 ? info.rows : (btb ? 2 : 1);
  final pitch = info.pitch > 0 ? info.pitch : (btb ? 0.4 : fpc ? 0.5 : header ? 2.54 : 1.25);
  final perRow = (info.pins / rows).ceil();
  final contacts = math.max(perRow - 1, 0) * pitch;
  final (extra, depth) = btb
      ? (1.8, 1.2 + rows * 0.7)
      : fpc
      ? (3.6, 4.2)
      : header
      ? (pitch, rows * pitch)
      : (math.max(3.0, pitch * 2.4), math.max(3.5, pitch * 3.4));
  return PartShape(
    PartKind.connector,
    (contacts + extra).clamp(1.5, 80.0),
    depth.clamp(1.2, 15.0),
    pins: info.pins,
    rows: rows,
    exact: info.pitch > 0,
  );
}
