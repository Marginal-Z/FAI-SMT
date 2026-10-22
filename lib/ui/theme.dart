/// Flat desktop palette (no gradients, no purple) and typography.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../core/models.dart';

class AppColors {
  const AppColors({
    required this.dark,
    required this.window,
    required this.chrome,
    required this.ribbon,
    required this.panel,
    required this.panelAlt,
    required this.border,
    required this.borderStrong,
    required this.text,
    required this.textDim,
    required this.textFaint,
    required this.accent,
    required this.accentText,
    required this.hover,
    required this.pressed,
    required this.selected,
    required this.input,
    required this.pass,
    required this.ng,
    required this.excluded,
    required this.substitute,
    required this.passSoft,
    required this.ngSoft,
    required this.excludedSoft,
    required this.substituteSoft,
  });

  final bool dark;
  final Color window;
  final Color chrome;
  final Color ribbon;
  final Color panel;
  final Color panelAlt;
  final Color border;
  final Color borderStrong;
  final Color text;
  final Color textDim;
  final Color textFaint;
  final Color accent;
  final Color accentText;
  final Color hover;
  final Color pressed;
  final Color selected;
  final Color input;
  final Color pass;
  final Color ng;
  final Color excluded;
  final Color substitute;
  final Color passSoft;
  final Color ngSoft;
  final Color excludedSoft;
  final Color substituteSoft;

  /// Graphite workspace, like CAD / image-editor dark UIs.
  static const darkTheme = AppColors(
    dark: true,
    window: Color(0xFF17181B),
    chrome: Color(0xFF1E1F22),
    ribbon: Color(0xFF26272B),
    panel: Color(0xFF212225),
    panelAlt: Color(0xFF292A2E),
    border: Color(0xFF323438),
    borderStrong: Color(0xFF43464C),
    text: Color(0xFFE6E7E9),
    textDim: Color(0xFFA3A7AE),
    textFaint: Color(0xFF6D727A),
    accent: Color(0xFF4C8DF6),
    accentText: Color(0xFFFFFFFF),
    hover: Color(0xFF2E3034),
    pressed: Color(0xFF373A3F),
    selected: Color(0xFF1D3150),
    input: Color(0xFF1A1B1E),
    pass: Color(0xFF22C55E),
    ng: Color(0xFFF05252),
    excluded: Color(0xFF8E939B),
    substitute: Color(0xFFF5A524),
    passSoft: Color(0xFF16301F),
    ngSoft: Color(0xFF3A1D1F),
    excludedSoft: Color(0xFF2B2D31),
    substituteSoft: Color(0xFF382B14),
  );

  /// Clean neutral light UI.
  static const lightTheme = AppColors(
    dark: false,
    window: Color(0xFFF0F2F5),
    chrome: Color(0xFFF7F8FA),
    ribbon: Color(0xFFFFFFFF),
    panel: Color(0xFFFFFFFF),
    panelAlt: Color(0xFFF7F8FA),
    border: Color(0xFFE3E6EA),
    borderStrong: Color(0xFFCDD2D8),
    text: Color(0xFF1D2129),
    textDim: Color(0xFF4E5969),
    textFaint: Color(0xFF8A929E),
    accent: Color(0xFF1F6FEB),
    accentText: Color(0xFFFFFFFF),
    hover: Color(0xFFF0F2F5),
    pressed: Color(0xFFE4E7EB),
    selected: Color(0xFFE6F0FD),
    input: Color(0xFFFFFFFF),
    pass: Color(0xFF16A34A),
    ng: Color(0xFFDC2626),
    excluded: Color(0xFF6B7280),
    substitute: Color(0xFFD97706),
    passSoft: Color(0xFFEAF7EF),
    ngSoft: Color(0xFFFDEEEE),
    excludedSoft: Color(0xFFF2F3F5),
    substituteSoft: Color(0xFFFDF4E3),
  );

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
  double get ribbon => touch ? 100 : 92;
  double get rowPad => touch ? 11 : 8;
  double get iconButton => touch ? 36 : 26;
  double get statusBar => touch ? 28 : 24;

  static Metrics of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_MetricsScope>()?.metrics ?? const Metrics(touch: false);
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

/// Platform UI fonts with CJK and Thai fallbacks.
String get uiFontFamily => Platform.isWindows
    ? 'Segoe UI'
    : Platform.isAndroid
    ? 'Roboto'
    : 'Noto Sans';

const uiFontFallback = [
  'Microsoft YaHei UI',
  'PingFang SC',
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

TextStyle baseTextStyle(AppColors c) => TextStyle(
  fontFamily: uiFontFamily,
  fontFamilyFallback: uiFontFallback,
  fontSize: 13,
  height: 1.35,
  color: c.text,
  decoration: TextDecoration.none,
);
