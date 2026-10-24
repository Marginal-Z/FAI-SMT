/// Package facts read from footprint names and BOM descriptions.
///
/// Works on the common ways packages are written, so new products need no
/// configuration:
///   EDA libraries   SOIC-8_3.9x4.9mm_P1.27mm, QFN-32-1EP_5x5mm_P0.5mm,
///                   PinHeader_2x05_P2.54mm, JST_SH_SM04B_1x04_P1.00mm
///   Short names     SOT-23-5, TSSOP20, LQFP64, BGA153, DFN1006
///   BOM text        连接器 FPC 0.5MM 24P 翻盖, 板对板 40PIN 0.4mm, 2*20PIN 排针
library;

class PackageInfo {
  const PackageInfo({this.family = '', this.pins = 0, this.rows = 0, this.pitch = 0, this.length = 0, this.width = 0});

  /// Normalised package family: SOT23, SOT89, SOT223, SOIC, TSSOP, MSOP,
  /// SSOP, QFN, DFN, QFP, BGA, CSP ... or empty.
  final String family;

  /// Total pin (contact) count, 0 when not stated.
  final int pins;

  /// Contact rows of a connector, 0 when not stated.
  final int rows;

  /// Contact pitch in mm, 0 when not stated.
  final double pitch;

  /// Body length (long side) and width in mm when written out, else 0.
  final double length;
  final double width;

  bool get hasBody => length > 0 && width > 0;
}

final _sot = RegExp(r'(?<![A-Z])(TSOT|SOT|SC)-?(23|323|523|89|223|143|343|353|363|563|666|70|88|59)(?:[-_ ]?(\d{1,2}))?(?![\d.])');
final _so = RegExp(r'(?<![A-Z])(HTSSOP|TSSOP|VSSOP|MSOP|QSOP|SSOP|HSOP|ESOP|SOIC|TSOP|SOP|SO)[-_ ]?(\d{1,3})(?![\d.])');
final _qfp = RegExp(r'(?<![A-Z])(LQFP|TQFP|PQFP|QFP)[-_ ]?(\d{2,3})(?![\d.])');
final _qfn = RegExp(r'(?<![A-Z])(HVQFN|VQFN|WQFN|UQFN|QFN|VDFN|WDFN|UDFN|TDFN|XDFN|DFN|WSON|VSON|USON|SON|LGA|LCC)[-_ ]?(\d{1,4})?(?![\d.])');
final _bga = RegExp(r'(?<![A-Z])(TFBGA|VFBGA|LFBGA|UFBGA|FBGA|BGA|WLCSP|CSP)[-_ ]?(\d{1,4})?(?![\d.])');

/// Rows × contacts per row: 2X20, 1x04, 2*10, 2×5 (not 4X4MM body sizes).
final _rowsPins = RegExp(r'(?<![\d.])([1-4])\s*[X×*]\s*(\d{1,3})(?![\d.])(?!\s*MM)');

/// Contact count: 24P, 40PIN, 6 POS, 30位, 10针, 4芯, 8脚.
final _pins = RegExp(r'(?<![\d.])(\d{1,3})\s*(?:PINS?|POS|P(?![A-Z0-9.])|位|针|芯|脚)');

/// Pitch: P0.5, PITCH 1.25, 间距2.0, _P1.27MM, 0.4MM.
final _pitchMark = RegExp(r'(?:(?<![A-Z])P|PITCH|间距)\s*[:=]?\s*(\d{1,2}\.\d{1,3})');
final _pitchMm = RegExp(r'(?<![\d.])(\d(?:\.\d{1,3})?)\s*MM');

/// Pitch written without the point in footprint names: 125MM = 1.25 mm.
final _pitchCompact = RegExp(r'(?<![\d.])(\d)(\d{1,2})MM');

/// Contact count in connector footprint names: CONN4, CON_12, CONNECTOR-6.
final _conPins = RegExp(r'CON(?:N|NECT|NECTOR|NEC)?[_\- ]?(\d{1,3})(?![\d.])');
const _pitches = [0.3, 0.35, 0.4, 0.5, 0.635, 0.65, 0.8, 1.0, 1.25, 1.27, 1.5, 2.0, 2.5, 2.54, 3.0, 3.5, 3.81, 3.96, 5.0, 5.08];

/// Body size with a unit (3.9x4.9mm, 5*5MM, 4.4×6.5×1.2mm) or with
/// decimals (FPC_10.2X4.5).
final _bodyMm = RegExp(r'(?<![\d.])(\d{1,2}(?:\.\d{1,2})?)\s*[X×*]\s*(\d{1,2}(?:\.\d{1,2})?)(?:\s*[X×*]\s*\d{1,2}(?:\.\d{1,2})?)?\s*MM');
final _bodyDec = RegExp(r'(?<![\d.])(\d{1,2}(?:\.\d{1,2})?)\s*[X×]\s*(\d{1,2}(?:\.\d{1,2})?)(?![\d.])');

/// Wire-to-board series and their pitch.
const _series = {
  'SH': 1.0, 'GH': 1.25, 'PICOBLADE': 1.25, 'ZH': 1.5, 'PH': 2.0, 'XH': 2.5, 'VH': 3.96, 'EH': 2.5, //
  'A1251': 1.25, 'A1501': 1.5, 'A2001': 2.0, 'A2501': 2.5,
};

/// Family and pin count of the first package name in [s], or null.
(String, int)? _family(String s) {
  final sot = _sot.firstMatch(s);
  final bga = _bga.firstMatch(s);
  final qfp = _qfp.firstMatch(s);
  final qfn = _qfn.firstMatch(s);
  final so = _so.firstMatch(s);
  // The earliest name in the text wins (a footprint names one package).
  final found = <(int, (String, int))>[];
  if (sot != null) {
    final code = sot.group(2)!;
    final n = int.tryParse(sot.group(3) ?? '');
    final family = switch (code) {
      '89' => 'SOT89',
      '223' => 'SOT223',
      '363' || '563' || '666' || '88' => 'SOT363',
      '70' || '323' || '343' || '353' => 'SC70',
      '523' => 'SOT523',
      _ => 'SOT23',
    };
    final usual = switch (family) { 'SOT223' => 4, 'SOT363' => 6, _ => code == '143' || code == '343' ? 4 : 3 };
    found.add((sot.start, (family, n ?? usual)));
  }
  if (bga != null) {
    var n = int.tryParse(bga.group(2) ?? '') ?? 0;
    // Ball counts written after the name: WLCSP-1.47×2.21-15B, 43PIN CSP.
    if (n == 0) n = int.tryParse(RegExp(r'(?<![\d.])(\d{1,4})\s*PINS?(?![A-Z])').firstMatch(s)?.group(1) ?? '') ?? 0;
    if (n == 0) n = int.tryParse(RegExp(r'(?<![\d.A-Z])(\d{2,4})\s*B(?:ALLS?)?(?![A-Z])').firstMatch(s)?.group(1) ?? '') ?? 0;
    found.add((bga.start, (bga.group(1)!.contains('CSP') ? 'CSP' : 'BGA', n)));
  }
  if (qfp != null) found.add((qfp.start, ('QFP', int.parse(qfp.group(2)!))));
  // DFN1006 and the like are size codes, handled by the caller.
  if (qfn != null && qfn.group(2)?.length != 4) {
    final f = qfn.group(1)!;
    found.add((qfn.start, (RegExp(r'DFN|SON').hasMatch(f) ? 'DFN' : (f == 'LGA' || f == 'LCC' ? 'LGA' : 'QFN'), int.tryParse(qfn.group(2) ?? '') ?? 0)));
  }
  if (so != null) {
    final family = switch (so.group(1)!) {
      'HTSSOP' || 'TSSOP' => 'TSSOP',
      'VSSOP' || 'MSOP' => 'MSOP',
      'QSOP' || 'SSOP' => 'SSOP',
      _ => 'SOIC',
    };
    found.add((so.start, (family, int.parse(so.group(2)!))));
  }
  if (found.isEmpty) return null;
  found.sort((a, b) => a.$1.compareTo(b.$1));
  return found.first.$2;
}

PackageInfo parsePackage(String footprint, String description) {
  final fp = footprint.toUpperCase();
  final desc = description.toUpperCase();
  final text = '$fp $desc';

  // The footprint is the land pattern actually on the board, so its package
  // name wins over the description's; the description may add the count.
  final inFp = _family(fp), inDesc = _family(desc);
  final family = inFp?.$1 ?? inDesc?.$1 ?? '';
  var pins = inFp?.$2 ?? inDesc?.$2 ?? 0;
  if (pins == 0 && inFp != null && inDesc?.$1 == inFp.$1) pins = inDesc!.$2;

  // Connector style counts.
  var rows = 0;
  // Packages with a family read 4X4 as a body size, not rows × pins.
  final rp = family.isEmpty ? _rowsPins.firstMatch(text) : null;
  final pc = _pins.firstMatch(text);
  if (rp != null) {
    rows = int.parse(rp.group(1)!);
    final per = int.parse(rp.group(2)!);
    if (per >= 1 && family.isEmpty) pins = rows * per;
  }
  if (pc != null && family.isEmpty) {
    final n = int.parse(pc.group(1)!);
    if (n >= 1 && n <= 400 && (pins == 0 || n == pins || rp == null)) pins = n;
  }
  if (pins == 0 && family.isEmpty) {
    final c = _conPins.firstMatch(fp);
    if (c != null) pins = int.parse(c.group(1)!);
  }
  if (rows == 0 && RegExp(r'双排|DUAL[ -]?ROW|2ROW|DOUBLE ROW').hasMatch(text)) rows = 2;
  if (rows == 0 && RegExp(r'单排|SINGLE[ -]?ROW|1ROW').hasMatch(text)) rows = 1;

  var pitch = 0.0;
  final pm = _pitchMark.firstMatch(text);
  if (pm != null) pitch = double.parse(pm.group(1)!);
  if (pitch == 0) {
    for (final m in _pitchMm.allMatches(text)) {
      final v = double.parse(m.group(1)!);
      if (_pitches.contains(v)) {
        pitch = v;
        break;
      }
    }
  }
  if (pitch == 0) {
    for (final m in _pitchCompact.allMatches(fp)) {
      final v = double.parse('${m.group(1)}.${m.group(2)}');
      if (_pitches.contains(v)) {
        pitch = v;
        break;
      }
    }
  }
  if (pitch == 0) {
    for (final e in _series.entries) {
      if (RegExp('(?<![A-Z])${e.key}(?![A-Z])').hasMatch(text)) {
        pitch = e.value;
        break;
      }
    }
  }
  if (pitch < 0.25 || pitch > 5.1) pitch = 0;

  var length = 0.0, width = 0.0;
  RegExpMatch? decimal(String s) => _bodyDec.allMatches(s).where((m) => m.group(0)!.contains('.')).firstOrNull;
  final body = _bodyMm.firstMatch(text) ?? (family.isNotEmpty ? _bodyDec.firstMatch(fp) ?? decimal(desc) : decimal(fp));
  if (body != null) {
    final a = double.parse(body.group(1)!), b = double.parse(body.group(2)!);
    // Rows × pins written like a size (2X20) is not a body.
    final isRows = rp != null && body.start == rp.start;
    if (!isRows && a >= 0.3 && b >= 0.3 && a <= 60 && b <= 60) {
      length = a > b ? a : b;
      width = a > b ? b : a;
    }
  }

  return PackageInfo(family: family, pins: pins, rows: rows, pitch: pitch, length: length, width: width);
}
