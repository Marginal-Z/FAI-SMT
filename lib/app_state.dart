/// Application state: loaded files, check report, CAD output, settings.
library;

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'core/checker.dart';
import 'core/discrepancies.dart';
import 'core/exporters.dart';
import 'core/models.dart';
import 'core/parsers.dart';
import 'core/settings.dart';
import 'core/table_reader.dart';
import 'core/updater.dart';
import 'update_installer.dart';
import 'version.dart';

enum InputKind { bom, stationA, stationB, coords, boardCad }

class LoadedFile<T> {
  LoadedFile(this.name, this.result, {this.size = 0, this.sheets = 1, DateTime? loadedAt}) : loadedAt = loadedAt ?? DateTime.now();

  final String name;
  final ParseResult<T> result;

  /// File size in bytes and number of non-empty sheets read.
  final int size;
  final int sheets;
  final DateTime loadedAt;
}

/// An error whose text is a localisation key plus arguments.
class UserMessage implements Exception {
  UserMessage(this.key, [this.args = const {}]);

  final String key;
  final Map<String, Object?> args;
}

/// Function modules. Each ribbon tab opens exactly one module page.
enum Module { files, check, cad, board }

/// Sections of the full-screen settings page.
enum SettingsSection { appearance, board, rules, update, about }

/// Sections of the rules editor inside settings.
enum RulesSection { exclusion, alternates, general }

/// What the PCB view shows: the checked data, or a CAD coordinate file.
enum BoardSource { check, file }

enum UpdateStatus { idle, checking, upToDate, available, downloading, installing, failed }

/// Board view side filter.
enum BoardSideFilter { both, top, bottom }

/// What the assembly drawing colours components by.
enum BoardColoring { type, status }

/// Check page view: per-part results or the full discrepancy list.
enum CheckPageView { materials, discrepancies }

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
  DateTime? checkedAt;

  /// Manual sign-offs by [CheckRow.key]; they survive a re-check as long as
  /// the row's result and designators are unchanged.
  final Map<String, ManualCheck> confirmations = {};
  CadResult? _cad;
  List<Discrepancy>? _discrepancies;

  // UI state
  Module module = Module.files;
  bool settingsOpen = false;
  SettingsSection settingsSection = SettingsSection.appearance;
  RulesSection rulesSection = RulesSection.exclusion;

  /// PCB view: data source, an opened CAD coordinate file, full screen.
  BoardSource boardSource = BoardSource.check;
  LoadedFile<Placement>? boardFile;
  bool boardFullscreen = false;
  BoardSideFilter boardSide = BoardSideFilter.both;

  /// Incremented to ask the board view to fit the board to the window.
  int boardFitRequest = 0;

  /// View rotation in quarter turns (counter-clockwise) and mirror flag.
  int boardQuarterTurns = 0;
  bool boardMirror = false;
  BoardColoring boardColoring = BoardColoring.type;
  CheckPageView checkView = CheckPageView.materials;

  // Updates
  UpdateStatus updateStatus = UpdateStatus.idle;
  ReleaseInfo? latestRelease;
  double updateProgress = 0;
  String updateError = '';

  bool get updateAvailable => latestRelease != null && compareVersions(latestRelease!.version, appVersion) > 0;
  CheckCategory? filter;
  String search = '';
  CheckRow? selected;
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

  void setAutoUpdate(bool v) {
    settings.autoUpdate = v;
    persist();
    notifyListeners();
  }

  /// Queries GitHub Releases. [silent] keeps failures out of the status bar
  /// (used for the start-up check).
  Future<void> checkForUpdates({bool silent = false}) async {
    if (updateStatus == UpdateStatus.checking || updateStatus == UpdateStatus.downloading) return;
    updateStatus = UpdateStatus.checking;
    updateError = '';
    notifyListeners();
    try {
      latestRelease = await fetchLatestRelease();
      updateStatus = updateAvailable ? UpdateStatus.available : UpdateStatus.upToDate;
      if (updateAvailable) _status('update_found', {'v': latestRelease!.version});
    } on UpdateException catch (e) {
      updateStatus = silent ? UpdateStatus.idle : UpdateStatus.failed;
      updateError = e.code == 'no_release' ? 'upd_err_no_release' : 'upd_err_network';
    }
    notifyListeners();
  }

  /// Downloads the package for this platform and hands it to the installer.
  Future<void> downloadAndInstall() async {
    final release = latestRelease;
    if (release == null) return;
    final asset = pickAsset(release, Abi.current());
    if (asset == null) {
      updateStatus = UpdateStatus.failed;
      updateError = 'upd_err_no_asset';
      notifyListeners();
      return;
    }
    updateStatus = UpdateStatus.downloading;
    updateProgress = 0;
    notifyListeners();
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}smt_fai_update_${release.version}');
      final file = await downloadAsset(asset, dir, (p) {
        updateProgress = p;
        notifyListeners();
      });
      updateStatus = UpdateStatus.installing;
      notifyListeners();
      await installUpdate(file, release);
    } on UpdateException catch (e) {
      updateStatus = UpdateStatus.failed;
      updateError = 'upd_err_${e.code}';
      notifyListeners();
    }
  }

  void setTheme(ThemePref t) {
    settings.theme = t;
    persist();
    notifyListeners();
  }

  /// Cycles system → light → dark, for the title-bar toggle.
  void cycleTheme() => setTheme(ThemePref.values[(theme.index + 1) % ThemePref.values.length]);

  void setModule(Module m) {
    module = m;
    notifyListeners();
  }

  void openSettings([SettingsSection section = SettingsSection.appearance]) {
    settingsOpen = true;
    settingsSection = section;
    notifyListeners();
  }

  void closeSettings() {
    settingsOpen = false;
    notifyListeners();
  }

  void setSettingsSection(SettingsSection s) {
    settingsSection = s;
    notifyListeners();
  }

  void openRules(RulesSection section) {
    settingsOpen = true;
    settingsSection = SettingsSection.rules;
    rulesSection = section;
    notifyListeners();
  }

  void setBoardSource(BoardSource s) {
    boardSource = s;
    boardFitRequest++;
    notifyListeners();
  }

  /// Sets (or with null resets) the colour of one part type in the navigator.
  void setPartColor(String kind, int? argb) {
    if (argb == null) {
      settings.board.partColors.remove(kind);
    } else {
      settings.board.partColors[kind] = argb;
    }
    persist();
    notifyListeners();
  }

  void setBoardBackground(BoardBackground b, {int? custom}) {
    settings.board.background = b;
    if (custom != null) settings.board.customBackground = custom;
    persist();
    notifyListeners();
  }

  void setBoardDepth(bool v) {
    settings.board.depth = v;
    persist();
    notifyListeners();
  }

  /// Restores the default colours; the flat / 3D choice is kept.
  void resetBoardStyle() {
    settings.board = BoardStyle(depth: settings.board.depth);
    persist();
    notifyListeners();
  }

  void setBoardFullscreen(bool v) {
    boardFullscreen = v;
    notifyListeners();
  }

  /// Back to the default view: no rotation, not mirrored, fitted.
  void resetBoardView() {
    boardQuarterTurns = 0;
    boardMirror = false;
    boardFitRequest++;
    notifyListeners();
  }

  void setBoardSide(BoardSideFilter side) {
    boardSide = side;
    notifyListeners();
  }

  void rotateBoard(int quarterTurns) {
    boardQuarterTurns = (boardQuarterTurns + quarterTurns) % 4;
    boardFitRequest++;
    notifyListeners();
  }

  void toggleBoardMirror() {
    boardMirror = !boardMirror;
    boardFitRequest++;
    notifyListeners();
  }

  void setBoardColoring(BoardColoring c) {
    boardColoring = c;
    notifyListeners();
  }

  void setCheckView(CheckPageView v) {
    checkView = v;
    notifyListeners();
  }

  void fitBoard() {
    boardFitRequest++;
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
          bom = LoadedFile(name, parseBom(grids), size: bytes.length, sheets: grids.length);
        case InputKind.stationA:
          stationA = LoadedFile(name, parseStation(grids, StationSide.a), size: bytes.length, sheets: grids.length);
        case InputKind.stationB:
          stationB = LoadedFile(name, parseStation(grids, StationSide.b), size: bytes.length, sheets: grids.length);
        case InputKind.coords:
          _coordBytes = bytes;
          coords = LoadedFile(name, parseCoordinates(grids, unit: settings.coordUnit), size: bytes.length, sheets: grids.length);
        case InputKind.boardCad:
          boardFile = LoadedFile(name, parseCoordinates(grids), size: bytes.length, sheets: grids.length);
          boardSource = BoardSource.file;
          boardFitRequest++;
          _status('status_loaded', {'name': name});
          notifyListeners();
          return;
      }
    } on ParseException catch (e) {
      throw UserMessage('err_${e.code}', {'detail': e.detail});
    }
    if (kind != InputKind.coords) {
      report = null;
      selected = null;
    }
    _cad = null;
    _discrepancies = null;
    _status('status_loaded', {'name': name});
    if (kind == InputKind.coords && report != null) {
      runCheckNow();
      return;
    }
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
      case InputKind.boardCad:
        boardFile = null;
        boardSource = BoardSource.check;
        notifyListeners();
        return;
    }
    if (kind != InputKind.coords) {
      report = null;
      selected = null;
    }
    _cad = null;
    _discrepancies = null;
    _status('status_ready');
    if (kind == InputKind.coords && report != null) {
      runCheckNow();
      return;
    }
    notifyListeners();
  }

  ManualCheck? confirmationOf(CheckRow r) => confirmations[r.key];

  void setConfirmed(Iterable<CheckRow> rows, bool confirmed) {
    final now = DateTime.now();
    for (final r in rows) {
      if (!confirmed) {
        confirmations.remove(r.key);
      } else {
        confirmations.putIfAbsent(r.key, () => ManualCheck(now));
      }
    }
    notifyListeners();
  }

  void setConfirmNote(CheckRow r, String note) {
    final old = confirmations[r.key];
    confirmations[r.key] = ManualCheck(old?.at ?? DateTime.now(), note: note);
    notifyListeners();
  }

  /// Confirmed rows of the current report, optionally of one category.
  int confirmedCount([CheckCategory? category]) =>
      report?.rows.where((r) => (category == null || r.category == category) && confirmations.containsKey(r.key)).length ?? 0;

  void clearAll() {
    confirmations.clear();
    bom = stationA = stationB = null;
    coords = null;
    _coordBytes = null;
    report = null;
    _cad = null;
    _discrepancies = null;
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
      coords = LoadedFile(c.name, parseCoordinates(readTableBytes(_coordBytes!, c.name), unit: u),
          size: c.size, sheets: c.sheets, loadedAt: c.loadedAt);
      _cad = null;
    }
    notifyListeners();
  }

  void runCheckNow() {
    if (bom == null) throw UserMessage('msg_need_bom');
    if (stationA == null && stationB == null) throw UserMessage('msg_need_station');
    final stations = [...?stationA?.result.items, ...?stationB?.result.items];
    final raw = runCheck(bom!.result.items, stations, settings.rules);
    _discrepancies = findDiscrepancies(
      bom: bom!.result.items,
      stations: stations,
      report: raw,
      rules: settings.rules,
      placements: coords?.result.items,
      bomIssues: bom!.result.issues,
      stationAIssues: stationA?.result.issues ?? const [],
      stationBIssues: stationB?.result.issues ?? const [],
      coordIssues: coords?.result.issues ?? const [],
    );
    report = foldIntoReport(raw, _discrepancies!);
    checkedAt = DateTime.now();
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

  /// All inconsistencies across the loaded files, or null before a check.
  List<Discrepancy>? get discrepancies => report == null ? null : _discrepancies;

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
