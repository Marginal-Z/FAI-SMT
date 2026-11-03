/// User settings, persisted as JSON.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'ai_check.dart';

enum ThemePref { system, light, dark }

/// Interface styles: the modern design, and the flat industrial one.
enum ThemeStyle { modern, industrial }

class AppSettings {
  AppSettings({
    this.language = 'zh',
    this.theme = ThemePref.system,
    this.themeStyle = ThemeStyle.modern,
    this.autoUpdate = true,
    this.uiScale = 0,
    this.tourDone = false,
    this.aiEnabled = false,
    AiConfig? ai,
  }) : ai = ai ?? AiConfig();

  String language;
  ThemePref theme;
  ThemeStyle themeStyle;

  /// Check GitHub Releases for a newer version at start-up.
  bool autoUpdate;

  /// Interface zoom factor; 0 follows the display (see autoUiScale).
  double uiScale;

  /// The first-run guided tour has been finished.
  bool tourDone;

  /// Run the AI check together with the local one.
  bool aiEnabled;
  AiConfig ai;

  Map<String, dynamic> toJson() => {
    'language': language,
    'theme': theme.name,
    'themeStyle': themeStyle.name,
    'autoUpdate': autoUpdate,
    'uiScale': uiScale,
    'tourDone': tourDone,
    'aiEnabled': aiEnabled,
    'ai': ai.toJson(),
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    language: j['language'] as String? ?? 'zh',
    theme: ThemePref.values.firstWhere((t) => t.name == j['theme'], orElse: () => ThemePref.system),
    themeStyle: ThemeStyle.values.firstWhere((t) => t.name == j['themeStyle'], orElse: () => ThemeStyle.modern),
    autoUpdate: j['autoUpdate'] as bool? ?? true,
    uiScale: (j['uiScale'] as num?)?.toDouble() ?? 0,
    tourDone: j['tourDone'] == true,
    aiEnabled: j['aiEnabled'] == true,
    ai: j['ai'] is Map ? AiConfig.fromJson((j['ai'] as Map).cast()) : null,
  );

  static Future<AppSettings> load(String dir) async {
    try {
      final f = File(p.join(dir, 'settings.json'));
      if (await f.exists()) {
        return AppSettings.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>);
      }
    } catch (_) {
      // A corrupt settings file falls back to defaults.
    }
    return AppSettings();
  }

  Future<void> save(String dir) async {
    await Directory(dir).create(recursive: true);
    await File(p.join(dir, 'settings.json')).writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()));
  }
}
