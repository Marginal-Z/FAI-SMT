/// User settings, persisted as JSON.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'bom_compare.dart' show CompareOptions, CheckStatus;
import 'cloud/hybrid.dart' show PrivacyOptions;
import 'cloud/provider.dart';
import 'report.dart' show ReportOptions;

enum ThemePref { system, light, dark }

/// How a check is run: the program and local models only; then the cloud
/// for what they could not settle; or the cloud reading and pairing.
enum CheckMode { local, hybrid, cloudFull }

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
    this.localAiEnabled = false,
    this.embeddingModel = '',
    this.checkMode = CheckMode.local,
    this.privacy = const PrivacyOptions(),
    ProviderConfig? cloud,
    this.legacyApiKey = '',
    Set<String>? compareSkip,
    Set<String>? reportHidden,
    Set<String>? reportStatuses,
  }) : cloud = cloud ?? ProviderConfig(),
       compareSkip = compareSkip ?? {},
       reportHidden = reportHidden ?? {},
       reportStatuses = reportStatuses ?? {};

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

  /// Use the downloaded local models in the check.
  bool localAiEnabled;

  /// Id of the chosen embedding model; empty picks one that is on disk,
  /// else the default.
  String embeddingModel;

  CheckMode checkMode;

  /// What may be sent to a cloud model.
  PrivacyOptions privacy;
  /// Cloud AI provider; its API key is kept in the secure key store.
  ProviderConfig cloud;

  /// Fields left out of the check (see compareFields).
  final Set<String> compareSkip;

  /// Report column groups left out, and the results listed (all when empty).
  final Set<String> reportHidden;
  final Set<String> reportStatuses;

  CompareOptions get compareOptions => CompareOptions(skip: {...compareSkip});

  ReportOptions get reportOptions => ReportOptions(
    hidden: {...reportHidden},
    statuses: {for (final st in CheckStatus.values) if (reportStatuses.contains(st.name)) st},
  );

  /// A key found in an old settings file (2.0 kept it in plain text); moved
  /// to the key store at start-up and never written back.
  final String legacyApiKey;

  Map<String, dynamic> toJson() => {
    'language': language,
    'theme': theme.name,
    'themeStyle': themeStyle.name,
    'autoUpdate': autoUpdate,
    'uiScale': uiScale,
    'tourDone': tourDone,
    'aiEnabled': aiEnabled,
    'localAiEnabled': localAiEnabled,
    'embeddingModel': embeddingModel,
    'checkMode': checkMode.name,
    'privacy': privacy.toJson(),
    'cloud': cloud.toJson(),
    'compareSkip': compareSkip.toList(),
    'reportHidden': reportHidden.toList(),
    'reportStatuses': reportStatuses.toList(),
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    language: j['language'] as String? ?? 'zh',
    theme: ThemePref.values.firstWhere((t) => t.name == j['theme'], orElse: () => ThemePref.system),
    themeStyle: ThemeStyle.values.firstWhere((t) => t.name == j['themeStyle'], orElse: () => ThemeStyle.modern),
    autoUpdate: j['autoUpdate'] as bool? ?? true,
    uiScale: (j['uiScale'] as num?)?.toDouble() ?? 0,
    tourDone: j['tourDone'] == true,
    aiEnabled: j['aiEnabled'] == true,
    localAiEnabled: j['localAiEnabled'] == true,
    embeddingModel: j['embeddingModel'] as String? ?? '',
    checkMode: CheckMode.values.firstWhere((m) => m.name == j['checkMode'], orElse: () => CheckMode.local),
    privacy: j['privacy'] is Map ? PrivacyOptions.fromJson((j['privacy'] as Map).cast()) : const PrivacyOptions(),
    cloud: j['cloud'] is Map ? ProviderConfig.fromJson((j['cloud'] as Map).cast()) : _legacyCloud(j['ai']),
    legacyApiKey: j['ai'] is Map ? '${(j['ai'] as Map)['apiKey'] ?? ''}' : '',
    compareSkip: _strings(j['compareSkip']),
    reportHidden: _strings(j['reportHidden']),
    reportStatuses: _strings(j['reportStatuses']),
  );

  static Set<String> _strings(Object? v) => v is List ? {for (final x in v) '$x'} : {};

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

/// The provider of a 2.0 settings file.
ProviderConfig? _legacyCloud(Object? ai) {
  if (ai is! Map) return null;
  final base = '${ai['baseUrl'] ?? ''}';
  final kind = ai['provider'] == 'anthropic'
      ? ProviderKind.anthropic
      : base.contains('deepseek')
      ? ProviderKind.deepseek
      : base.isEmpty
      ? ProviderKind.openai
      : ProviderKind.custom;
  return ProviderConfig(kind: kind, baseUrl: base, model: '${ai['model'] ?? ''}');
}
