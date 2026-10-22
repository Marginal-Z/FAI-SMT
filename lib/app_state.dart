/// Application state: loaded files, check report, CAD output, settings.
library;

import 'package:flutter/foundation.dart';

import 'core/checker.dart';
import 'core/exporters.dart';
import 'core/models.dart';
import 'core/parsers.dart';
import 'core/settings.dart';
import 'core/table_reader.dart';

enum InputKind { bom, stationA, stationB, coords }

class LoadedFile<T> {
  LoadedFile(this.name, this.result);

  final String name;
  final ParseResult<T> result;
}

/// An error whose text is a localisation key plus arguments.
class UserMessage implements Exception {
  UserMessage(this.key, [this.args = const {}]);

  final String key;
  final Map<String, Object?> args;
}

enum Workspace { check, board, cad }

class AppState extends ChangeNotifier {
  AppState(this.settings, this.settingsDir);

  AppSettings settings;
  final String settingsDir;

  LoadedFile<BomItem>? bom;
  LoadedFile<StationItem>? stationA;
  LoadedFile<StationItem>? stationB;
  LoadedFile<Placement>? coords;
  Uint8List? _coordBytes;

  CheckReport? report;
  CadResult? _cad;

  // UI state
  int ribbonTab = 0;
  Workspace workspace = Workspace.check;
  CheckCategory? filter;
  String search = '';
  CheckRow? selected;
  bool showProject = true;
  bool showInspector = true;
  String statusKey = 'status_ready';
  Map<String, Object?> statusArgs = const {};

  String get language => settings.language;
  ThemePref get theme => settings.theme;

  void _status(String key, [Map<String, Object?> args = const {}]) {
    statusKey = key;
    statusArgs = args;
  }

  Future<void> persist() => settings.save(settingsDir);

  void setLanguage(String lang) {
    settings.language = lang;
    persist();
    notifyListeners();
  }

  void setTheme(ThemePref t) {
    settings.theme = t;
    persist();
    notifyListeners();
  }

  /// Cycles system → light → dark, for the title-bar toggle.
  void cycleTheme() => setTheme(ThemePref.values[(theme.index + 1) % ThemePref.values.length]);

  void setRibbonTab(int i) {
    ribbonTab = i;
    notifyListeners();
  }

  void setWorkspace(Workspace w) {
    workspace = w;
    notifyListeners();
  }

  void setFilter(CheckCategory? c) {
    filter = c;
    notifyListeners();
  }

  void setSearch(String s) {
    search = s;
    notifyListeners();
  }

  void select(CheckRow? r) {
    selected = r;
    notifyListeners();
  }

  void togglePanel({bool project = false, bool inspector = false}) {
    if (project) showProject = !showProject;
    if (inspector) showInspector = !showInspector;
    notifyListeners();
  }

  /// Parses [bytes] as the given input kind. Throws [UserMessage] on failure.
  void load(InputKind kind, String name, Uint8List bytes) {
    final List<Grid> grids;
    try {
      grids = readTableBytes(bytes, name);
    } on TableReadException catch (e) {
      throw UserMessage('err_${e.code}', {'detail': e.detail});
    }
    try {
      switch (kind) {
        case InputKind.bom:
          bom = LoadedFile(name, parseBom(grids));
        case InputKind.stationA:
          stationA = LoadedFile(name, parseStation(grids, StationSide.a));
        case InputKind.stationB:
          stationB = LoadedFile(name, parseStation(grids, StationSide.b));
        case InputKind.coords:
          _coordBytes = bytes;
          coords = LoadedFile(name, parseCoordinates(grids, unit: settings.coordUnit));
      }
    } on ParseException catch (e) {
      throw UserMessage('err_${e.code}', {'detail': e.detail});
    }
    if (kind != InputKind.coords) {
      report = null;
      selected = null;
    }
    _cad = null;
    _status('status_loaded', {'name': name});
    notifyListeners();
  }

  void unload(InputKind kind) {
    switch (kind) {
      case InputKind.bom:
        bom = null;
      case InputKind.stationA:
        stationA = null;
      case InputKind.stationB:
        stationB = null;
      case InputKind.coords:
        coords = null;
        _coordBytes = null;
    }
    if (kind != InputKind.coords) {
      report = null;
      selected = null;
    }
    _cad = null;
    _status('status_ready');
    notifyListeners();
  }

  void clearAll() {
    bom = stationA = stationB = null;
    coords = null;
    _coordBytes = null;
    report = null;
    _cad = null;
    selected = null;
    filter = null;
    search = '';
    _status('status_ready');
    notifyListeners();
  }

  void setCoordUnit(CoordUnit u) {
    settings.coordUnit = u;
    persist();
    final c = coords;
    if (c != null && _coordBytes != null) {
      coords = LoadedFile(c.name, parseCoordinates(readTableBytes(_coordBytes!, c.name), unit: u));
      _cad = null;
    }
    notifyListeners();
  }

  void runCheckNow() {
    if (bom == null) throw UserMessage('msg_need_bom');
    if (stationA == null && stationB == null) throw UserMessage('msg_need_station');
    final stations = [...?stationA?.result.items, ...?stationB?.result.items];
    report = runCheck(bom!.result.items, stations, settings.rules);
    _cad = null;
    selected = null;
    _status('status_checked', {
      'pass': report!.count(CheckCategory.pass),
      'ng': report!.count(CheckCategory.ng),
      'ex': report!.count(CheckCategory.excluded),
      'alt': report!.count(CheckCategory.substitute),
    });
    notifyListeners();
  }

  void updateRules(CheckRules rules) {
    settings.rules = rules;
    persist();
    if (report != null) {
      runCheckNow();
    } else {
      notifyListeners();
    }
  }

  void updateCadTemplate(CadTemplate t) {
    settings.cad = t;
    persist();
    _cad = null;
    notifyListeners();
  }

  /// CAD output for the current report and coordinates, or null when either
  /// is missing.
  CadResult? get cad {
    if (report == null || coords == null) return null;
    return _cad ??= buildCad(coords!.result.items, report!, settings.cad, settings.rules);
  }

  List<CheckRow> visibleRows() {
    final r = report;
    if (r == null) return const [];
    final q = search.trim().toUpperCase();
    return r.rows.where((row) {
      if (filter != null && row.category != filter) return false;
      if (q.isEmpty) return true;
      return row.partNo.toUpperCase().contains(q) ||
          row.description.toUpperCase().contains(q) ||
          row.smtPartNos.any((p) => p.toUpperCase().contains(q)) ||
          row.bomRefs.any((m) => m.ref == q) ||
          row.smtRefs.any((m) => m.ref == q);
    }).toList();
  }

  /// Base name for exported files, taken from the BOM file name.
  String get exportBaseName {
    final n = bom?.name ?? 'SMT-FAI';
    final dot = n.lastIndexOf('.');
    return dot > 0 ? n.substring(0, dot) : n;
  }
}
