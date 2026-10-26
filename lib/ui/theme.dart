/// Design tokens (light / dark) and typography of the SMT-FAI design.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../core/models.dart';

/// Colour tokens. The named design tokens (bg, card, glass, blue …) follow
/// the SMT-FAI design; the older names map onto them for the parts of the
/// app that predate it.
class AppColors {
  const AppColors({
    required this.dark,
    required this.bg,
    required this.tx,
    required this.tx2,
    required this.tx3,
    required this.card,
    required this.solid,
    required this.well,
    required this.hover,
    required this.glass,
    required this.glass2,
    required this.circle,
    required this.blue,
    required this.btn,
    required this.btnHover,
    required this.blueTx,
    required this.blueTint,
    required this.okTx,
    required this.okTint,
    required this.okSolid,
    required this.ngTx,
    required this.ngTint,
    required this.ngSolid,
    required this.warnTx,
    required this.warnTint,
    required this.warnSolid,
    required this.grayTint,
    required this.kbd,
    required this.navOn,
    required this.navOnTx,
    required this.navTx,
    required this.track,
    required this.mesh1,
    required this.mesh2,
    required this.mesh3,
    required this.rowSel,
    required this.band,
    required this.line,
    required this.lineStrong,
    required this.shadow,
    required this.shadowSm,
    this.industrial = false,
  });

  final bool dark;

  /// Industrial style: flat white surfaces, 1 px grey borders, small square
  /// corners, no shadows or gradients, graphite accent, system fonts.
  final bool industrial;

  /// Corner radius: the design's radius, or in the industrial style 3–6 px.
  BorderRadius r(double v) => BorderRadius.circular(!industrial || v <= 4 ? v : (v >= 100 ? 4 : (v <= 12 ? 3 : (v <= 20 ? 4 : 6))));

  /// Industrial style: every card is outlined.
  Border? get cardBorder => industrial ? Border.all(color: lineStrong) : null;
  final Color bg;
  final Color tx;
  final Color tx2;

  /// Third text level (hints, disabled), not in the design's palette.
  final Color tx3;

  /// Card and glass surfaces are the design's translucent fills composited
  /// over the page background (Flutter draws a box shadow under the box, so a
  /// see-through card would show its own shadow).
  final Color card;
  final Color solid;
  final Color well;
  final Color hover;
  final Color glass;
  final Color glass2;
  final Color circle;
  final Color blue;
  final Color btn;
  final Color btnHover;
  final Color blueTx;
  final Color blueTint;
  final Color okTx;
  final Color okTint;
  final Color okSolid;
  final Color ngTx;
  final Color ngTint;
  final Color ngSolid;
  final Color warnTx;
  final Color warnTint;
  final Color warnSolid;
  final Color grayTint;
  final Color kbd;
  final Color navOn;
  final Color navOnTx;
  final Color navTx;
  final Color track;
  final Color mesh1;
  final Color mesh2;
  final Color mesh3;
  final Color rowSel;
  final Color band;

  /// Hairlines for dividers and outlined controls.
  final Color line;
  final Color lineStrong;
  final List<BoxShadow> shadow;
  final List<BoxShadow> shadowSm;

  // Older names.
  Color get window => bg;
  Color get chrome => bg;
  Color get ribbon => card;
  Color get panel => solid;
  Color get panelAlt => well;
  Color get border => line;
  Color get borderStrong => lineStrong;
  Color get text => tx;
  Color get textDim => tx2;
  Color get textFaint => tx3;
  Color get accent => blue;
  Color get accentText => const Color(0xFFFFFFFF);
  Color get pressed => Color.alphaBlend(hover, hover);
  Color get selected => rowSel;
  Color get input => glass;
  Color get pass => okSolid;
  Color get ng => ngSolid;
  Color get excluded => const Color(0xFF8E8E93);
  Color get substitute => warnSolid;
  Color get passSoft => okTint;
  Color get ngSoft => ngTint;
  Color get excludedSoft => grayTint;
  Color get substituteSoft => warnTint;

  static const lightTheme = AppColors(
    dark: false,
    bg: Color(0xFFF5F5F7),
    tx: Color(0xFF1D1D1F),
    tx2: Color(0xFF6E6E73),
    tx3: Color(0xFF8E8E93),
    card: Color(0xFFFCFCFD),
    solid: Color(0xFFFFFFFF),
    well: Color(0xFFF5F5F7),
    hover: Color(0x0D000000),
    glass: Color(0xFFFCFCFD),
    glass2: Color(0xFFFFFFFF),
    circle: Color(0xFFFFFFFF),
    blue: Color(0xFF0071E3),
    btn: Color(0xFF0071E3),
    btnHover: Color(0xFF0077ED),
    blueTx: Color(0xFF0066CC),
    blueTint: Color(0x1A0071E3),
    okTx: Color(0xFF1F7A37),
    okTint: Color(0x1F248A3D),
    okSolid: Color(0xFF248A3D),
    ngTx: Color(0xFFC4161C),
    ngTint: Color(0x1AD70015),
    ngSolid: Color(0xFFFF3B30),
    warnTx: Color(0xFFA14A00),
    warnTint: Color(0x29FF9500),
    warnSolid: Color(0xFFFF9500),
    grayTint: Color(0xFFECECF0),
    kbd: Color(0xFFE8E8ED),
    navOn: Color(0xFF1D1D1F),
    navOnTx: Color(0xFFFFFFFF),
    navTx: Color(0xFF515154),
    track: Color(0xFFE2E2E7),
    mesh1: Color(0x4D78AAFF),
    mesh2: Color(0x3DBEA0FF),
    mesh3: Color(0x33FFC4A0),
    rowSel: Color(0x170071E3),
    band: Color(0xFFF7F7F9),
    line: Color(0xFFE5E5EA),
    lineStrong: Color(0xFFD2D2D7),
    shadow: [
      BoxShadow(color: Color(0x05000000), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0x141E2850), offset: Offset(0, 24), blurRadius: 60),
    ],
    shadowSm: [BoxShadow(color: Color(0x141E2850), offset: Offset(0, 4), blurRadius: 20)],
  );

  static const darkTheme = AppColors(
    dark: true,
    bg: Color(0xFF0A0A0C),
    tx: Color(0xFFF5F5F7),
    tx2: Color(0xFFA1A1A6),
    tx3: Color(0xFF8E8E93),
    card: Color(0xFF202023),
    solid: Color(0xFF1C1C1E),
    well: Color(0x0FFFFFFF),
    hover: Color(0x14FFFFFF),
    glass: Color(0xFF28282B),
    glass2: Color(0xFF4C4C52),
    circle: Color(0x24FFFFFF),
    blue: Color(0xFF0A84FF),
    btn: Color(0xFF0A6CF0),
    btnHover: Color(0xFF1A78F5),
    blueTx: Color(0xFF6CB4FF),
    blueTint: Color(0x330A84FF),
    okTx: Color(0xFF5FE083),
    okTint: Color(0x2930D158),
    okSolid: Color(0xFF30D158),
    ngTx: Color(0xFFFF8A8F),
    ngTint: Color(0x33FF453A),
    ngSolid: Color(0xFFFF453A),
    warnTx: Color(0xFFFFB340),
    warnTint: Color(0x33FF9F0A),
    warnSolid: Color(0xFFFF9F0A),
    grayTint: Color(0x1AFFFFFF),
    kbd: Color(0x24FFFFFF),
    navOn: Color(0xFFF5F5F7),
    navOnTx: Color(0xFF1D1D1F),
    navTx: Color(0xFFC7C7CC),
    track: Color(0x24FFFFFF),
    mesh1: Color(0x330A84FF),
    mesh2: Color(0x298C64FF),
    mesh3: Color(0x1AFF8C50),
    rowSel: Color(0x380A84FF),
    band: Color(0x0AFFFFFF),
    line: Color(0xFF2C2C2E),
    lineStrong: Color(0xFF3A3A3C),
    shadow: [
      BoxShadow(color: Color(0x4D000000), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0x73000000), offset: Offset(0, 24), blurRadius: 60),
    ],
    shadowSm: [BoxShadow(color: Color(0x59000000), offset: Offset(0, 4), blurRadius: 20)],
  );

  /// Industrial style (light), from the SMT-FAI industrial design.
  static const industrialLight = AppColors(
    industrial: true,
    dark: false,
    bg: Color(0xFFFFFFFF),
    tx: Color(0xFF000000),
    tx2: Color(0xFF333333),
    tx3: Color(0xFF555555),
    card: Color(0xFFFFFFFF),
    solid: Color(0xFFF0F0F0),
    well: Color(0xFFF5F5F5),
    hover: Color(0xFFF2F2F2),
    glass: Color(0xFFFFFFFF),
    glass2: Color(0xFFF5F5F5),
    circle: Color(0xFFFFFFFF),
    blue: Color(0xFF17191C),
    btn: Color(0xFF17191C),
    btnHover: Color(0xFF2E3136),
    blueTx: Color(0xFF17191C),
    blueTint: Color(0xFFE6E6E7),
    okTx: Color(0xFF14602C),
    okTint: Color(0xFFE4F2E8),
    okSolid: Color(0xFF1B7F3B),
    ngTx: Color(0xFFA01E25),
    ngTint: Color(0xFFFCE8E9),
    ngSolid: Color(0xFFC0262D),
    warnTx: Color(0xFF8A4A00),
    warnTint: Color(0xFFFFF1DC),
    warnSolid: Color(0xFFB35F00),
    grayTint: Color(0xFFEEEEEE),
    kbd: Color(0xFFFFFFFF),
    navOn: Color(0xFF17191C),
    navOnTx: Color(0xFFFFFFFF),
    navTx: Color(0xFF333333),
    track: Color(0xFFE6E6E6),
    mesh1: Color(0x00000000),
    mesh2: Color(0x00000000),
    mesh3: Color(0x00000000),
    rowSel: Color(0xFFE9EBEE),
    band: Color(0xFFFAFAFA),
    line: Color(0xFFE3E3E3),
    lineStrong: Color(0xFFCCCCCC),
    shadow: [],
    shadowSm: [],
  );

  /// Industrial style (dark): the same flat, outlined look on graphite.
  static const industrialDark = AppColors(
    industrial: true,
    dark: true,
    bg: Color(0xFF141516),
    tx: Color(0xFFF2F2F2),
    tx2: Color(0xFFC6C6C6),
    tx3: Color(0xFF9A9A9A),
    card: Color(0xFF1D1E20),
    solid: Color(0xFF26282B),
    well: Color(0xFF232427),
    hover: Color(0xFF2A2C2F),
    glass: Color(0xFF1D1E20),
    glass2: Color(0xFF2A2C2F),
    circle: Color(0xFF26282B),
    blue: Color(0xFFE6E6E6),
    btn: Color(0xFF3A3D42),
    btnHover: Color(0xFF474B51),
    blueTx: Color(0xFFE6E6E6),
    blueTint: Color(0xFF2F3237),
    okTx: Color(0xFF7FD69A),
    okTint: Color(0xFF1C3324),
    okSolid: Color(0xFF3FAF63),
    ngTx: Color(0xFFFF9A9E),
    ngTint: Color(0xFF3A1F21),
    ngSolid: Color(0xFFE5484D),
    warnTx: Color(0xFFFFC271),
    warnTint: Color(0xFF3A2C17),
    warnSolid: Color(0xFFE0921E),
    grayTint: Color(0xFF2A2C2F),
    kbd: Color(0xFF26282B),
    navOn: Color(0xFFE6E6E6),
    navOnTx: Color(0xFF111214),
    navTx: Color(0xFFC6C6C6),
    track: Color(0xFF34363A),
    mesh1: Color(0x00000000),
    mesh2: Color(0x00000000),
    mesh3: Color(0x00000000),
    rowSel: Color(0xFF2B2F35),
    band: Color(0xFF191A1C),
    line: Color(0xFF2E3033),
    lineStrong: Color(0xFF3C3F43),
    shadow: [],
    shadowSm: [],
  );

  /// Text colour of a result shown on its tint.
  Color categoryText(CheckCategory c) => switch (c) {
    CheckCategory.pass => okTx,
    CheckCategory.ng => ngTx,
    CheckCategory.excluded => tx2,
    CheckCategory.substitute => warnTx,
  };

  Color category(CheckCategory c) => switch (c) {
    CheckCategory.pass => pass,
    CheckCategory.ng => ng,
    CheckCategory.excluded => excluded,
    CheckCategory.substitute => substitute,
  };

  Color categorySoft(CheckCategory c) => switch (c) {
    CheckCategory.pass => passSoft,
    CheckCategory.ng => ngSoft,
    CheckCategory.excluded => excludedSoft,
    CheckCategory.substitute => substituteSoft,
  };

  Color refState(RefState s) => switch (s) {
    RefState.ok => pass,
    RefState.missing => ng,
    RefState.extra => ng,
    RefState.alternate => substitute,
    RefState.conflict => ng,
  };

  Color refStateSoft(RefState s) => switch (s) {
    RefState.ok => passSoft,
    RefState.alternate => substituteSoft,
    _ => ngSoft,
  };
}

/// Size scale: touch screens (Android tablets) get larger targets.
class Metrics {
  const Metrics({required this.touch});

  final bool touch;

  double get control => touch ? 38 : 30;
  double get compactControl => touch ? 34 : 26;
  double get tabBar => touch ? 46 : 38;
  double get docTabs => touch ? 40 : 32;
  double get menuBar => touch ? 42 : 34;
  double get ribbon => touch ? 110 : 102;
  double get rowPad => touch ? 11 : 8;
  double get iconButton => touch ? 36 : 26;
  double get statusBar => touch ? 28 : 24;

  static Metrics of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_MetricsScope>()?.metrics ?? const Metrics(touch: false);
}

class MetricsScope extends StatelessWidget {
  const MetricsScope({super.key, required this.metrics, required this.child});

  final Metrics metrics;
  final Widget child;

  @override
  Widget build(BuildContext context) => _MetricsScope(metrics: metrics, child: child);
}

class _MetricsScope extends InheritedWidget {
  const _MetricsScope({required this.metrics, required super.child});

  final Metrics metrics;

  @override
  bool updateShouldNotify(_MetricsScope old) => old.metrics.touch != metrics.touch;
}

/// Width classes for the responsive shell.
enum LayoutSize {
  /// Phone / portrait tablet: no docked panels, result cards.
  compact,

  /// Landscape tablet / small window: project panel docked, inspector floats.
  medium,

  /// Desktop: everything docked.
  wide;

  static LayoutSize of(double width) => width < 900
      ? LayoutSize.compact
      : width < 1320
      ? LayoutSize.medium
      : LayoutSize.wide;
}

class AppTheme extends InheritedWidget {
  const AppTheme({super.key, required this.colors, required super.child});

  final AppColors colors;

  static AppColors of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<AppTheme>()!.colors;

  @override
  bool updateShouldNotify(AppTheme old) => old.colors != colors;
}

/// Inter (bundled) for Latin and digits; CJK and Thai from the system.
String get uiFontFamily => 'Inter';

const uiFontFallback = [
  'PingFang SC',
  'Microsoft YaHei UI',
  'Microsoft YaHei',
  'Noto Sans CJK SC',
  'Noto Sans SC',
  'Source Han Sans SC',
  'WenQuanYi Micro Hei',
  'Leelawadee UI',
  'Noto Sans Thai',
  'Tahoma',
];

String get monoFontFamily => Platform.isWindows
    ? 'Consolas'
    : Platform.isAndroid
    ? 'monospace'
    : 'DejaVu Sans Mono';

/// The industrial style uses the Windows UI fonts (Segoe UI, Microsoft
/// YaHei), and the bundled Inter on other systems.
const _industrialFallback = ['Microsoft YaHei UI', 'Microsoft YaHei', 'PingFang SC', 'Noto Sans CJK SC', 'Noto Sans SC', 'Inter', ...uiFontFallback];

TextStyle baseTextStyle(AppColors c) => TextStyle(
  fontFamily: c.industrial && Platform.isWindows ? 'Segoe UI' : uiFontFamily,
  fontFamilyFallback: c.industrial ? _industrialFallback : uiFontFallback,
  fontSize: c.industrial ? 13.5 : 14,
  height: 1.35,
  color: c.tx,
  decoration: TextDecoration.none,
);
