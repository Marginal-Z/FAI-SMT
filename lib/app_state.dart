/// Application state: the single BOM, A-BOM and B-BOM, the comparison, the
/// AI analysis, settings and updates.
library;

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'core/ai_check.dart';
import 'core/bom.dart';
import 'core/bom_compare.dart';
import 'core/local_ai/model_store.dart';
import 'core/settings.dart';
import 'core/table_reader.dart';
import 'core/updater.dart';
import 'update_installer.dart';
import 'version.dart';

/// The three inputs: the single (reference) BOM, A-BOM and the optional
/// B-BOM; A and B are merged and compared with the single BOM.
enum InputKind { single, a, b }

class LoadedFile {
  LoadedFile(this.name, this.bom, {this.size = 0, this.sheets = 1, DateTime? loadedAt}) : loadedAt = loadedAt ?? DateTime.now();

  final String name;
  final BomDocument bom;

  /// File size in bytes and number of sheets read.
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

/// Pages of the settings screen.
enum SettingsSection { appearance, ai, localAi, guide, about }

enum UpdateStatus { idle, checking, upToDate, available, downloading, installing, failed }

enum AiStatus { idle, running, done, failed }

class AppState extends ChangeNotifier {
  AppState(this.settings, this.settingsDir, {ModelStore? models}) : models = models ?? ModelStore.forApp(settingsDir);

  AppSettings settings;
  final String settingsDir;

  LoadedFile? single;
  LoadedFile? bomA;
  LoadedFile? bomB;

  CompareReport? report;

  // AI check
  AiStatus aiStatus = AiStatus.idle;
  AiResult? ai;
  String aiError = '';
  String aiErrorDetail = '';
  int _aiRun = 0;

  // UI state
  bool settingsOpen = false;

  /// Open settings page; null is the list of all of them.
  SettingsSection? settingsSection;

  // Updates
  UpdateStatus updateStatus = UpdateStatus.idle;
  ReleaseInfo? latestRelease;
  double updateProgress = 0;
  String updateError = '';

  bool get updateAvailable => latestRelease != null && compareVersions(latestRelease!.version, appVersion) > 0;

  /// Result filter; null shows every row.
  DiffStatus? filter;
  String search = '';
  CompareRow? selected;
  String statusKey = 'status_ready';
  Map<String, Object?> statusArgs = const {};

  String get language => settings.language;
  ThemePref get theme => settings.theme;

  void _status(String key, [Map<String, Object?> args = const {}]) {
    statusKey = key;
    statusArgs = args;
  }

  Future<void> persist() => settings.save(settingsDir);

  LoadedFile? file(InputKind k) => switch (k) {
    InputKind.single => single,
    InputKind.a => bomA,
    InputKind.b => bomB,
  };

  bool get ready => single != null && bomA != null;
  int get loadedCount => [single, bomA, bomB].whereType<LoadedFile>().length;

  // ------------------------------------------------------------- appearance

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

  /// Cycles system → light → dark, for the header toggle.
  void cycleTheme() => setTheme(ThemePref.values[(theme.index + 1) % ThemePref.values.length]);

  void setThemeStyle(ThemeStyle v) {
    settings.themeStyle = v;
    persist();
    notifyListeners();
  }

  void setUiScale(double v) {
    settings.uiScale = v;
    persist();
    notifyListeners();
  }

  // --------------------------------------------------------------- settings

  /// Opens Settings at [section], or at the list of pages.
  void openSettings([SettingsSection? section]) {
    settingsOpen = true;
    settingsSection = section;
    notifyListeners();
  }

  void closeSettings() {
    settingsOpen = false;
    notifyListeners();
  }

  void setSettingsSection(SettingsSection? s) {
    settingsSection = s;
    notifyListeners();
  }

  // ------------------------------------------------------------------- tour

  /// Open step of the guided tour, or null when it is not running.
  int? tourStep;

  /// The tour loaded the sample files; they are cleared when it ends.
  bool tourDemo = false;

  void startTour() {
    settingsOpen = false;
    tourStep = 0;
    notifyListeners();
  }

  void setTourStep(int step) {
    tourStep = step;
    notifyListeners();
  }

  void endTour() {
    tourStep = null;
    if (tourDemo) {
      tourDemo = false;
      clearAll();
    }
    settings.tourDone = true;
    persist();
    notifyListeners();
  }

  // ---------------------------------------------------------------- updates

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
    final asset = pickAsset(release, Abi.current(), installer: installedWithSetup);
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

  // ----------------------------------------------------------- local models

  final ModelStore models;
  final modelStatus = <String, ModelStatus>{};
  final _downloads = <String, DownloadCancel>{};

  bool get localModelsReady => localModels.every((m) => modelStatus[m.id]?.state == ModelState.ready);

  Future<void> refreshModels() async {
    for (final m in localModels) {
      if (_downloads.containsKey(m.id)) continue;
      modelStatus[m.id] = await models.status(m);
    }
    notifyListeners();
  }

  /// Downloads [m] in the background; the status follows in [modelStatus].
  Future<void> downloadModel(LocalModelSpec m) async {
    if (_downloads.containsKey(m.id)) return;
    final cancel = _downloads[m.id] = DownloadCancel();
    modelStatus[m.id] = const ModelStatus(ModelState.downloading);
    notifyListeners();
    try {
      await models.download(m, language: language, cancel: cancel, onStatus: (s) {
        modelStatus[m.id] = s;
        notifyListeners();
      });
    } on ModelDownloadException catch (e) {
      final partial = await models.status(m);
      modelStatus[m.id] = e.code == 'cancelled' ? partial : ModelStatus(ModelState.failed, progress: partial.progress, error: 'model_err_${e.code}', detail: e.detail);
    } finally {
      _downloads.remove(m.id);
      notifyListeners();
    }
  }

  void cancelModelDownload(LocalModelSpec m) => _downloads[m.id]?.cancel();

  Future<void> deleteModel(LocalModelSpec m) async {
    await models.delete(m);
    await refreshModels();
  }

  void setLocalAiEnabled(bool v) {
    settings.localAiEnabled = v;
    persist();
    notifyListeners();
  }

  // ------------------------------------------------------------------ files

  /// Reads [bytes] as the given BOM. Throws [UserMessage] on failure.
  void load(InputKind kind, String name, Uint8List bytes) {
    final List<Grid> grids;
    try {
      grids = readTableBytes(bytes, name);
    } on TableReadException catch (e) {
      throw UserMessage('err_${e.code}', {'detail': e.detail});
    }
    final BomDocument bom;
    try {
      bom = readBom(grids, file: name, id: switch (kind) {
        InputKind.single => 'S',
        InputKind.a => 'A',
        InputKind.b => 'B',
      });
    } on BomReadException catch (e) {
      throw UserMessage('err_${e.code}');
    }
    final f = LoadedFile(name, bom, size: bytes.length, sheets: grids.length);
    switch (kind) {
      case InputKind.single:
        single = f;
      case InputKind.a:
        bomA = f;
      case InputKind.b:
        bomB = f;
    }
    _reset();
    _status('status_loaded', {'name': name});
    notifyListeners();
  }

  void unload(InputKind kind) {
    switch (kind) {
      case InputKind.single:
        single = null;
      case InputKind.a:
        bomA = null;
      case InputKind.b:
        bomB = null;
    }
    _reset();
    _status('status_ready');
    notifyListeners();
  }

  void clearAll() {
    single = bomA = bomB = null;
    _reset();
    _status('status_ready');
    notifyListeners();
  }

  void _reset() {
    report = null;
    selected = null;
    ai = null;
    aiStatus = AiStatus.idle;
    aiError = '';
    _aiRun++;
  }

  // ------------------------------------------------------------------ check

  /// Local check; the AI check follows when it is switched on.
  void runCheckNow() {
    if (single == null) throw UserMessage('msg_need_single');
    if (bomA == null) throw UserMessage('msg_need_a');
    report = compareBoms(single!.bom, bomA!.bom, bomB?.bom);
    selected = null;
    ai = null;
    aiStatus = AiStatus.idle;
    if (report!.complete) {
      _status('status_checked', {
        'same': report!.count(DiffStatus.same),
        'diff': report!.count(DiffStatus.different),
        'single': report!.count(DiffStatus.onlySingle),
        'merged': report!.count(DiffStatus.onlyMerged),
      });
    } else {
      // Never report a finished check while records are unaccounted for.
      _status('status_incomplete', {'n': report!.uncovered.length});
    }
    notifyListeners();
    if (settings.aiEnabled && settings.ai.ready) runAi();
  }

  void setAiEnabled(bool v) {
    settings.aiEnabled = v;
    persist();
    notifyListeners();
    if (v && report != null && ai == null && aiStatus != AiStatus.running && settings.ai.ready) runAi();
  }

  void updateAi(AiConfig cfg) {
    settings.ai = cfg;
    persist();
    notifyListeners();
  }

  /// Sends the comparison to the configured model; a newer run or a reload
  /// discards an older answer.
  Future<void> runAi() async {
    final r = report;
    if (r == null) return;
    final run = ++_aiRun;
    aiStatus = AiStatus.running;
    aiError = '';
    aiErrorDetail = '';
    notifyListeners();
    try {
      final result = await runAiCheck(settings.ai, r);
      if (run != _aiRun) return;
      ai = result;
      aiStatus = AiStatus.done;
      _status('status_ai_done', {'n': result.findings.length});
    } on AiException catch (e) {
      if (run != _aiRun) return;
      aiStatus = AiStatus.failed;
      aiError = 'err_${e.code}';
      aiErrorDetail = e.detail;
    }
    notifyListeners();
  }

  void cancelAi() {
    _aiRun++;
    aiStatus = AiStatus.idle;
    notifyListeners();
  }

  // ------------------------------------------------------------------- view

  void setFilter(DiffStatus? s) {
    filter = s;
    notifyListeners();
  }

  void setSearch(String s) {
    search = s;
    notifyListeners();
  }

  void select(CompareRow? r) {
    selected = r;
    notifyListeners();
  }

  /// Parts flagged by the AI check.
  Set<String> get aiParts => {for (final f in ai?.findings ?? const <AiFinding>[]) f.partNo};

  List<CompareRow> visibleRows() {
    final r = report;
    if (r == null) return const [];
    final q = search.trim().toUpperCase();
    return r.rows.where((row) {
      if (filter != null && row.status != filter) return false;
      if (q.isEmpty) return true;
      return row.partNo.toUpperCase().contains(q) ||
          row.description.toUpperCase().contains(q) ||
          (row.single?.refs.contains(q) ?? false) ||
          (row.merged?.refs.contains(q) ?? false);
    }).toList();
  }

  /// Base name for exported files, taken from the single BOM's file name.
  String get exportBaseName {
    final n = single?.name ?? 'BOM';
    final dot = n.lastIndexOf('.');
    return dot > 0 ? n.substring(0, dot) : n;
  }
}
