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

  static const darkTheme = AppColors(
    dark: true,
    window: Color(0xFF1B1C1F),
    chrome: Color(0xFF232427),
    ribbon: Color(0xFF2B2D31),
    panel: Color(0xFF26282B),
    panelAlt: Color(0xFF2A2C30),
    border: Color(0xFF383A3F),
    borderStrong: Color(0xFF4A4D53),
    text: Color(0xFFE3E5E8),
    textDim: Color(0xFFA2A6AD),
    textFaint: Color(0xFF6E737B),
    accent: Color(0xFF3C82F6),
    accentText: Color(0xFFFFFFFF),
    hover: Color(0xFF34373C),
    pressed: Color(0xFF3E4148),
    selected: Color(0xFF243B5C),
    input: Color(0xFF1E1F22),
    pass: Color(0xFF22C55E),
    ng: Color(0xFFEF4444),
    excluded: Color(0xFF8B9099),
    substitute: Color(0xFFF59E0B),
    passSoft: Color(0xFF173A26),
    ngSoft: Color(0xFF45201F),
    excludedSoft: Color(0xFF303237),
    substituteSoft: Color(0xFF3F3017),
  );

  static const lightTheme = AppColors(
    dark: false,
    window: Color(0xFFEDEFF2),
    chrome: Color(0xFFE2E5E9),
    ribbon: Color(0xFFF7F8FA),
    panel: Color(0xFFFFFFFF),
    panelAlt: Color(0xFFF7F8FA),
    border: Color(0xFFD8DCE1),
    borderStrong: Color(0xFFC2C7CE),
    text: Color(0xFF1F2328),
    textDim: Color(0xFF59616B),
    textFaint: Color(0xFF959BA3),
    accent: Color(0xFF1C6ED8),
    accentText: Color(0xFFFFFFFF),
    hover: Color(0xFFE6E9ED),
    pressed: Color(0xFFD9DDE3),
    selected: Color(0xFFDCE8F8),
    input: Color(0xFFFFFFFF),
    pass: Color(0xFF16A34A),
    ng: Color(0xFFDC2626),
    excluded: Color(0xFF6B7280),
    substitute: Color(0xFFD97706),
    passSoft: Color(0xFFE8F8EE),
    ngSoft: Color(0xFFFDECEC),
    excludedSoft: Color(0xFFF1F2F4),
    substituteSoft: Color(0xFFFEF4E2),
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

class AppTheme extends InheritedWidget {
  const AppTheme({super.key, required this.colors, required super.child});

  final AppColors colors;

  static AppColors of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppTheme>()!.colors;

  @override
  bool updateShouldNotify(AppTheme old) => old.colors != colors;
}

/// Platform UI fonts with CJK and Thai fallbacks.
String get uiFontFamily => Platform.isWindows ? 'Segoe UI' : 'Noto Sans';

const uiFontFallback = [
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

String get monoFontFamily => Platform.isWindows ? 'Consolas' : 'DejaVu Sans Mono';

TextStyle baseTextStyle(AppColors c) => TextStyle(
      fontFamily: uiFontFamily,
      fontFamilyFallback: uiFontFallback,
      fontSize: 13,
      height: 1.35,
      color: c.text,
      decoration: TextDecoration.none,
    );
