/// User-editable rules and export template, persisted as JSON.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'parsers.dart';

class CheckRules {
  CheckRules({
    List<String>? excludeKeywords,
    List<String>? excludePrefixes,
    List<String>? ignoreRefPatterns,
    Map<String, List<String>>? substitutes,
    List<String>? programKeywords,
    this.excludeNoRefs = true,
    this.checkQty = true,
  }) : excludeKeywords = excludeKeywords ?? List.of(defaultExcludeKeywords),
       excludePrefixes = excludePrefixes ?? [],
       ignoreRefPatterns = ignoreRefPatterns ?? List.of(defaultIgnoreRefs),
       substitutes = substitutes ?? {},
       programKeywords = programKeywords ?? List.of(defaultProgramKeywords);

  static const defaultExcludeKeywords = [
    'PCB',
    '锡膏',
    '锡条',
    '锡线',
    '红胶',
    '钢网',
    '助焊剂',
    '标签',
    '贴纸',
    '包装',
    '纸箱',
    '静电袋',
    '螺丝',
    'DIP',
    '插件',
    '散热膏',
  ];
  static const defaultIgnoreRefs = ['MARK*', 'FID*', 'FM*'];
  static const defaultProgramKeywords = ['烧录', 'PRG', 'F/W'];

  /// A BOM line whose name contains one of these is a programmed part. When it
  /// is on the line, the blank part sharing its designators is not loaded
  /// separately and goes to Excluded.
  List<String> programKeywords;

  /// BOM lines whose 品名/规格 contain one of these are not SMT materials.
  List<String> excludeKeywords;

  /// BOM lines whose part number starts with one of these are excluded.
  List<String> excludePrefixes;

  /// Designators ignored everywhere (fiducials etc.); `*` is a wildcard.
  List<String> ignoreRefPatterns;

  /// Main part number -> approved alternates, in addition to the BOM's own.
  Map<String, List<String>> substitutes;

  /// BOM lines without 插件位置 are excluded instead of reported as NG.
  bool excludeNoRefs;

  /// Compare BOM 组成用量 with the number of designators.
  bool checkQty;

  bool isIgnoredRef(String ref) => ignoreRefPatterns.any((pat) {
    final re = RegExp('^${RegExp.escape(pat.trim().toUpperCase()).replaceAll(r'\*', '.*')}\$');
    return pat.trim().isNotEmpty && re.hasMatch(ref);
  });

  Map<String, dynamic> toJson() => {
    'excludeKeywords': excludeKeywords,
    'excludePrefixes': excludePrefixes,
    'ignoreRefPatterns': ignoreRefPatterns,
    'substitutes': substitutes,
    'programKeywords': programKeywords,
    'excludeNoRefs': excludeNoRefs,
    'checkQty': checkQty,
  };

  factory CheckRules.fromJson(Map<String, dynamic> j) => CheckRules(
    excludeKeywords: (j['excludeKeywords'] as List?)?.cast<String>(),
    excludePrefixes: (j['excludePrefixes'] as List?)?.cast<String>(),
    ignoreRefPatterns: (j['ignoreRefPatterns'] as List?)?.cast<String>(),
    substitutes: (j['substitutes'] as Map?)?.map((k, v) => MapEntry(k as String, (v as List).cast<String>())),
    programKeywords: (j['programKeywords'] as List?)?.cast<String>(),
    excludeNoRefs: j['excludeNoRefs'] as bool? ?? true,
    checkQty: j['checkQty'] as bool? ?? true,
  );
}

/// Fields that can appear in the generated FAI CAD file.
enum CadField { ref, x, y, rotation, description, partNo, side, qty, loadedPartNo, value, footprint, slot }

enum CadFormat { xlsx, text }

/// Layout of the CAD coordinate file fed to the FAI i450 tester.
///
/// The defaults reproduce the tester's own "CAD BOM" merge export
/// (db/template_bom.xlsx in the FAI program): one row per designator with
/// `Location X Y Angle Specification PartNo Layer Qty`. The tester finds these
/// columns by header keyword (config/cad_property.ini, bom_property.ini) and
/// reads Layer through PcbLayer.dat (TOP / BOTTOM), so the same workbook loads
/// as both its CAD and its BOM.
class CadTemplate {
  /// Bumped when the defaults change, so stale saved layouts are replaced.
  static const schema = 2;

  CadTemplate({
    List<CadField>? fields,
    Map<String, String>? headers,
    this.format = CadFormat.xlsx,
    this.delimiter = ',',
    this.writeHeader = true,
    this.extension = 'csv',
    this.encoding = 'utf8',
    this.decimals = 3,
    this.unit = CoordUnit.mm,
    this.topText = 'TOP',
    this.bottomText = 'BOTTOM',
    this.includeUnmatched = false,
    this.sideFromStation = true,
  }) : fields =
           fields ??
           [
             CadField.ref,
             CadField.x,
             CadField.y,
             CadField.rotation,
             CadField.description,
             CadField.partNo,
             CadField.side,
             CadField.qty,
           ],
       headers = headers ?? {};

  List<CadField> fields;

  /// Optional header text per field name; falls back to the English default.
  Map<String, String> headers;
  CadFormat format;

  /// Text format only.
  String delimiter;
  bool writeHeader;

  /// Text format only; the workbook is always `.xlsx`.
  String extension;

  String get fileExtension => format == CadFormat.xlsx ? 'xlsx' : extension;

  /// `utf8`, `utf8bom` or `gbk`.
  String encoding;
  int decimals;
  CoordUnit unit;
  String topText;
  String bottomText;

  /// Also write coordinate rows whose designator is not in the BOM.
  bool includeUnmatched;

  /// When the coordinate file has no layer column, take the side from the
  /// station list (A = top, B = bottom).
  bool sideFromStation;

  static const defaultHeaders = {
    CadField.ref: 'Location',
    CadField.x: 'X',
    CadField.y: 'Y',
    CadField.rotation: 'Angle',
    CadField.description: 'Specification',
    CadField.partNo: 'PartNo',
    CadField.side: 'Layer',
    CadField.qty: 'Qty',
    CadField.loadedPartNo: 'LoadedPartNo',
    CadField.value: 'Value',
    CadField.footprint: 'Footprint',
    CadField.slot: 'Station',
  };

  String headerOf(CadField f) {
    final h = headers[f.name];
    return (h == null || h.isEmpty) ? defaultHeaders[f]! : h;
  }

  Map<String, dynamic> toJson() => {
    'schema': schema,
    'format': format.name,
    'fields': fields.map((f) => f.name).toList(),
    'headers': headers,
    'delimiter': delimiter,
    'writeHeader': writeHeader,
    'extension': extension,
    'encoding': encoding,
    'decimals': decimals,
    'unit': unit.name,
    'topText': topText,
    'bottomText': bottomText,
    'includeUnmatched': includeUnmatched,
    'sideFromStation': sideFromStation,
  };

  factory CadTemplate.fromJson(Map<String, dynamic> j) => j['schema'] != schema
      ? CadTemplate()
      : CadTemplate(
          format: CadFormat.values.firstWhere((f) => f.name == j['format'], orElse: () => CadFormat.xlsx),
          fields: (j['fields'] as List?)
              ?.map((n) => CadField.values.where((f) => f.name == n))
              .expand((e) => e)
              .toList(),
          headers: (j['headers'] as Map?)?.cast<String, String>(),
          delimiter: j['delimiter'] as String? ?? ',',
          writeHeader: j['writeHeader'] as bool? ?? true,
          extension: j['extension'] as String? ?? 'csv',
          encoding: j['encoding'] as String? ?? 'utf8',
          decimals: j['decimals'] as int? ?? 3,
          unit: CoordUnit.values.firstWhere((u) => u.name == j['unit'], orElse: () => CoordUnit.mm),
          topText: j['topText'] as String? ?? 'TOP',
          bottomText: j['bottomText'] as String? ?? 'BOTTOM',
          includeUnmatched: j['includeUnmatched'] as bool? ?? false,
          sideFromStation: j['sideFromStation'] as bool? ?? true,
        );
}

/// Light / dark appearance, or follow the operating system.
enum ThemePref { system, light, dark }

/// PCB board colour in the navigator.
enum BoardBackground { canvas, green, black, custom }

/// Navigator colours: per-part-type overrides (ARGB, keyed by PartKind name)
/// and the board background.
class BoardStyle {
  BoardStyle({Map<String, int>? partColors, this.background = BoardBackground.canvas, this.customBackground = 0xFF1E5E3B})
      : partColors = partColors ?? {};

  Map<String, int> partColors;
  BoardBackground background;
  int customBackground;

  Map<String, dynamic> toJson() => {
        'partColors': partColors,
        'background': background.name,
        'customBackground': customBackground,
      };

  factory BoardStyle.fromJson(Map<String, dynamic> j) => BoardStyle(
        partColors: (j['partColors'] as Map?)?.map((k, v) => MapEntry(k as String, (v as num).toInt())),
        background: BoardBackground.values.firstWhere((b) => b.name == j['background'], orElse: () => BoardBackground.canvas),
        customBackground: (j['customBackground'] as num?)?.toInt() ?? 0xFF1E5E3B,
      );
}

class AppSettings {
  AppSettings({
    BoardStyle? board,
    CheckRules? rules,
    CadTemplate? cad,
    this.language = 'zh',
    this.theme = ThemePref.system,
    this.autoUpdate = true,
    this.coordUnit = CoordUnit.auto,
  }) : rules = rules ?? CheckRules(),
       cad = cad ?? CadTemplate(),
       board = board ?? BoardStyle();

  BoardStyle board;
  CheckRules rules;
  CadTemplate cad;
  String language;
  ThemePref theme;

  /// Check GitHub Releases for a newer version at start-up.
  bool autoUpdate;
  CoordUnit coordUnit;

  Map<String, dynamic> toJson() => {
    'rules': rules.toJson(),
    'board': board.toJson(),
    'cad': cad.toJson(),
    'language': language,
    'theme': theme.name,
    'autoUpdate': autoUpdate,
    'coordUnit': coordUnit.name,
  };

  factory AppSettings.fromJson(Map<String, dynamic> j) => AppSettings(
    rules: j['rules'] is Map ? CheckRules.fromJson((j['rules'] as Map).cast()) : null,
    board: j['board'] is Map ? BoardStyle.fromJson((j['board'] as Map).cast()) : null,
    cad: j['cad'] is Map ? CadTemplate.fromJson((j['cad'] as Map).cast()) : null,
    language: j['language'] as String? ?? 'zh',
    theme: ThemePref.values.firstWhere(
      (t) => t.name == j['theme'],
      // Settings saved before the theme preference existed only had a flag.
      orElse: () => switch (j['dark']) {
        true => ThemePref.dark,
        false => ThemePref.light,
        _ => ThemePref.system,
      },
    ),
    autoUpdate: j['autoUpdate'] as bool? ?? true,
    coordUnit: CoordUnit.values.firstWhere((u) => u.name == j['coordUnit'], orElse: () => CoordUnit.auto),
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
