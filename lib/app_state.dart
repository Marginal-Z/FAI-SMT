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
import 'core/cloud/full.dart';
import 'core/cloud/hybrid.dart';
import 'core/cloud/provider.dart';
import 'core/history.dart';
import 'core/local_ai/local_ai.dart';
import 'core/local_ai/model_store.dart';
import 'core/local_ai/semantic_match.dart';
import 'core/local_ai/usage.dart';
import 'core/local_ai/local_review.dart';
import 'core/settings.dart';
import 'core/table_reader.dart';
import 'core/report.dart';
import 'core/updater.dart';
import 'l10n/strings.dart';
import 'services/key_store.dart';
import 'update_installer.dart';
import 'version.dart';

/// The three inputs: the single (reference) BOM, A-BOM and the optional
/// B-BOM; A and B are merged and compared with the single BOM.
enum InputKind { single, a, b }

class LoadedFile {
  LoadedFile(this.name, this.bom, {this.size = 0, this.sheets = 1, this.grids = const [], this.bytes, DateTime? loadedAt}) : loadedAt = loadedAt ?? DateTime.now();

  final String name;

  /// The file as loaded, kept for the check history.
  final Uint8List? bytes;
  final BomDocument bom;

  /// The sheets as read, for a cloud reading of the columns (CLOUD_FULL).
  final List<Grid> grids;

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
enum SettingsSection { history, appearance, checking, ai, localAi, guide, about }

enum UpdateStatus { idle, checking, upToDate, available, downloading, installing, failed }

enum AiStatus { idle, running, done, failed }

enum LocalStatus { idle,
  disabled,
  unavailable,
  notNeeded,
  cloudOnly,
  running, done, failed }

class AppState extends ChangeNotifier {
  AppState(this.settings, this.settingsDir, {ModelStore? models, KeyStore? keys, this.history,
    this.localModelsFactory,
  }) : models = models ?? ModelStore.forApp(settingsDir), keys = keys ?? SecureKeyStore();
  final Future<LocalModels> Function(ModelStore, LocalModelSpec)?
  localModelsFactory;

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
  CheckStatus? filter;
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

  Future<void> _persistTail = Future<void>.value();

  /// Keep rapid preference changes ordered, with a snapshot for each write.
  Future<void> persist() {
    final snapshot = AppSettings.fromJson(settings.toJson());
    final save = _persistTail.then((_) => snapshot.save(settingsDir));
    // A failed write must not prevent later saves from being attempted.
    _persistTail = save.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return save;
  }

  /// Restore runtime availability before the first check after launch.
  /// A saved enabled switch alone does not populate the model status map.
  Future<void> initialize() async {
    await Future.wait([loadKeys(), refreshModels()]);
  }

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

  /// Switches a field of the check on or off; the next check uses it.
  void setCompared(String key, bool on) {
    on ? settings.compareSkip.remove(key) : settings.compareSkip.add(key);
    persist();
    notifyListeners();
  }

  void setReportColumn(String group, bool on) {
    on ? settings.reportHidden.remove(group) : settings.reportHidden.add(group);
    persist();
    notifyListeners();
  }

  void setReportStatus(String status, bool on) {
    on ? settings.reportStatuses.add(status) : settings.reportStatuses.remove(status);
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

  /// The embedding model a check uses: the one chosen, else one already on
  /// disk (an earlier version's download keeps working), else the default.
  LocalModelSpec get activeEmbedding {
    if (settings.embeddingModel.isNotEmpty) return embeddingModel(settings.embeddingModel);
    return embeddingModels.firstWhere((m) => modelStatus[m.id]?.state == ModelState.ready, orElse: () => embeddingModels.first);
  }

  bool get localModelsReady => modelStatus[activeEmbedding.id]?.state == ModelState.ready;
  LocalModelSpec get localAnalysisModel => modelFor(LocalModelRole.language);
  bool get localAnalysisReady => modelStatus[localAnalysisModel.id]?.state == ModelState.ready;
  bool get localAnalysisRequired => settings.checkMode == CheckMode.local;
  bool get activeLocalReady => localAnalysisRequired ? localAnalysisReady : localModelsReady;
  bool get canExportReport => report != null && (!localAnalysisRequired ||
      (report!.complete && report!.localModel.kind == 'analysis' && report!.localModel.state == 'done' &&
       report!.localModel.rows == report!.rows.length && report!.localModel.total == report!.rows.length));

  /// Uses [m] for the next checks.
  Future<void> setEmbeddingModel(LocalModelSpec m) async {
    if (localBusy || m.role != LocalModelRole.embedding) return;
    _modelChanging = true;
    settings.embeddingModel = m.id;
    localTestKey = localTestDetail = '';
    final old = _local;
    _local = null;
    notifyListeners();
    try {
      await old?.dispose();
    } finally {
      _modelChanging = false;
      notifyListeners();
    }
    await persist();
  }

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
    if (localBusy) return;
    final old = _local;
    _local = null;
    await old?.dispose();
    if (m.role == LocalModelRole.language) {
      final oldAnalysis = _analysis;
      _analysis = null;
      await oldAnalysis?.dispose();
    }
    await models.delete(m);
    await refreshModels();
  }

  void setLocalAiEnabled(bool v) {
    if (localBusy || localAnalysisRequired) return;
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
    final f = LoadedFile(name, bom, size: bytes.length, sheets: grids.length, grids: grids, bytes: bytes);
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
    _checkRun++;
    if (_analysis case final LlamaLocalModels model) model.cancel();
    _cloudCancel?.cancel();
    _aiCancel?.cancel();
    cloudRunning = false;
    cloudRun = null;
    cloudError = '';
    localStatus = LocalStatus.idle;
    localRows = localTotal = localCalls = 0;
    localProgress = 0;
    localPaired = localTexts = localMillis = 0;
    localError = '';
    localErrorDetail = '';
    localLoading = false;
    _historyId = null;
    report = null;
    selected = null;
    ai = null;
    aiStatus = AiStatus.idle;
    aiError = '';
    _aiRun++;
  }

  // ------------------------------------------------------------------ check

  /// Local mode publishes only after every row has a language-model decision.
  void runCheckNow() {
    if (single == null) throw UserMessage('msg_need_single');
    if (bomA == null) throw UserMessage('msg_need_a');
    if (settings.checkMode != CheckMode.local && !cloudReady) {
      throw UserMessage('err_cloud_no_key');
    }
    // Never start a second inference on the same native engine.
    if (localBusy) throw UserMessage('local_wait');
    _aiRun++;
    _aiCancel?.cancel();
    _cloudCancel?.cancel();
    cloudRunning = false;
    cloudRun = null;
    cloudError = '';
    final run = ++_checkRun;
    if (settings.checkMode == CheckMode.local) {
      report = null;
      _historyId = null;
      selected = null;
      ai = null;
      aiStatus = AiStatus.idle;
      localKind = 'analysis';
      localTexts = localPaired = localMillis = localRows = localTotal = localCalls = 0;
      localProgress = 0;
      localModelName = localAnalysisModel.name;
      localError = '';
      localErrorDetail = '';
      if (!localAnalysisReady) {
        localStatus = LocalStatus.unavailable;
        _status('local_analysis_missing');
        notifyListeners();
        throw UserMessage('local_analysis_missing');
      }
      _runRequiredLocal(run);
      return;
    }
    report = compareBoms(single!.bom, bomA!.bom, bomB?.bom, options: settings.compareOptions);
    _historyId = HistoryStore.newId(report!.at);
    selected = null;
    ai = null;
    aiStatus = AiStatus.idle;
    localStatus = settings.checkMode == CheckMode.cloudFull
        ? LocalStatus.cloudOnly
        : !settings.localAiEnabled
        ? LocalStatus.disabled
        : !localModelsReady
        ? LocalStatus.unavailable
        : report!.rows.any(
                (r) => r.status == CheckStatus.unmatched && r.single != null,
              ) &&
              report!.rows.any(
                (r) => r.status == CheckStatus.unmatched && r.merged != null,
              )
        ? LocalStatus.running
        : LocalStatus.notNeeded;
    localProgress = 0;
    localKind = 'embedding';
    localRows = localTotal = localCalls = 0;
    localPaired = localTexts = localMillis = 0;
    localModelName = activeEmbedding.name;
    localError = '';
    report!.pending =
        localStatus == LocalStatus.running ||
        settings.checkMode != CheckMode.local;
    if (settings.checkMode != CheckMode.cloudFull) _checkedStatus();
    notifyListeners();
    if (settings.checkMode == CheckMode.cloudFull) {
      _runCloudFull(run);
    } else if (localStatus == LocalStatus.running) {
      // The local embedding model proposes counterparts for unmatched
      // lines; the cloud steps wait for its result.
      _runLocal(run);
    } else {
      _afterLocal(run);
    }
  }

  /// After the local check: the HYBRID cloud step, then the AI analysis.
  void _afterLocal(int run) {
    if (run != _checkRun) return;
    if (settings.checkMode == CheckMode.hybrid && cloudReady) {
      _runHybrid(run);
    } else if (settings.aiEnabled && cloudReady) {
      runAi();
    }
  }

  void setCheckMode(CheckMode m) {
    if (localBusy || cloudRunning) return;
    if (m != settings.checkMode) _reset();
    settings.checkMode = m;
    persist();
    notifyListeners();
  }

  void setPrivacy(PrivacyOptions p) {
    settings.privacy = p;
    persist();
    notifyListeners();
  }

  /// Progress of the cloud part of the running or last check.
  CloudRun? cloudRun;
  String cloudError = '';
  bool cloudRunning = false;
  CloudCancel? _cloudCancel;

  void cancelCloud() => _cloudCancel?.cancel();

  Future<void> _runHybrid(int run) async {
    final localUsage = report!.localModel;
    final cancel = _cloudCancel = CloudCancel();
    cloudRunning = true;
    _status('status_cloud_running');
    notifyListeners();
    final (r, cr) = await hybridCheck(report!, cloudProvider, privacy: settings.privacy, cancel: cancel, onProgress: (p) {
        if (run != _checkRun) return;
        cloudRun = p;
      notifyListeners();
    });
    if (run != _checkRun) return;
    report = r;
    report!.pending = false;
    report!.localModel = localUsage;
    cloudRun = cr;
    cloudRunning = false;
    _checkedStatus();
    if (cr.complete) {
      // Final metadata and history are already captured above.
    } else {
      // The local result stands where the cloud did not answer.
      _status('status_cloud_partial', {'done': cr.batchesDone, 'all': cr.batches, 'e': cr.errors.toSet().join(', ')});
    }
    notifyListeners();
    if (settings.aiEnabled) runAi();
  }

  Future<void> _runCloudFull(int run) async {
    final cancel = _cloudCancel = CloudCancel();
    cloudRunning = true;
    // Until the cloud has answered there is no CLOUD_FULL result.
    report = null;
    _status('status_cloud_running');
    notifyListeners();
    try {
      final (r, cr) = await cloudFullCheck(
        single!.grids,
        bomA!.grids,
        bomB?.grids,
        cloudProvider,
        singleName: single!.name,
        aName: bomA!.name,
        bName: bomB?.name ?? '',
        privacy: settings.privacy,
        options: settings.compareOptions,
        cancel: cancel,
        onProgress: (p) {
          if (run != _checkRun) return;
          cloudRun = p;
          notifyListeners();
        },
      );
      if (run != _checkRun) return;
      report = r;
      cloudRun = cr;
      _checkedStatus();
    } on CloudException catch (e) {
      if (run != _checkRun) return;
      cloudError = 'err_cloud_${e.code}';
      _status('status_cloud_failed', {'e': e.code});
    }
    cloudRunning = false;
    notifyListeners();
    if (run == _checkRun && report != null && settings.aiEnabled) runAi();
  }

  void _checkedStatus() {
    report!
      ..mode = settings.checkMode.name
      ..models = [
        if (localStatus == LocalStatus.done && localTexts > 0) localModelName,
        if (settings.checkMode != CheckMode.local && cloudRun != null) '${settings.cloud.kind.name} ${settings.cloud.modelName}',
      ];
    report!.localModel = currentLocalUsage;
    if (report!.pending) {
      _status(
        localStatus == LocalStatus.running
            ? 'status_local_running'
            : 'status_cloud_running',
      );
      return;
    }
    if (report!.complete) {
      _status('status_checked', {
        'pass': report!.count(CheckStatus.pass),
        'ng': report!.count(CheckStatus.ng),
        'review': report!.count(CheckStatus.review),
        'unmatched': report!.count(CheckStatus.unmatched),
        'sub': report!.count(CheckStatus.substitute),
      });
    } else {
      _status('status_incomplete', {'n': report!.uncovered.length});
    }
    _archive();
  }

  LocalModelUsage get currentLocalUsage => LocalModelUsage(
      state: localStatus.name,
      model: localModelName,
      texts: localTexts,
      paired: localPaired,
      millis: localMillis,
      error: localError,
      kind: localKind, rows: localRows, total: localTotal, calls: localCalls,
    );

  // ---------------------------------------------------------------- history

  /// Where checks are kept; none in tests that do not ask for it.
  final HistoryStore? history;
  List<HistoryEntry> historyEntries = const [];
  String historyError = '';

  /// Entry of the current check; later stages (local model, cloud, AI)
  /// replace it rather than adding another.
  String? _historyId;
  Future<void> _archiving = Future.value();

  /// Keeps the current result with its input files. A failure is shown in
  /// the history page, never hidden.
  Future<void> _archive() {
    final r = report, id = _historyId, store = history;
    final s1 = single, a = bomA, b = bomB;
    if (r == null || id == null || s1 == null || a == null || store == null) return _archiving;
    final files = [
      for (final (role, f) in [('A', s1), ('B', a), ('C', b)])
        if (f != null && f.bytes != null) (role, f.name, f.bytes!),
    ];
    final book = exportCompareWorkbook(r, Strings(language).t, ai: ai, singleName: s1.name, aName: a.name, bName: b?.name ?? '');
    return _archiving = _archiving.then((_) async {
      try {
        await store.save(id: id, report: r, files: files, workbook: book, appVersion: appVersion);
        historyError = '';
      } catch (e) {
        historyError = '$e';
      }
      await refreshHistory();
    });
  }

  Future<void> refreshHistory() async {
    final store = history;
    if (store == null) return;
    try {
      historyEntries = await store.list();
    } catch (e) {
      historyError = '$e';
    }
    notifyListeners();
  }

  Future<void> deleteHistory(String id) async {
    await history?.delete(id);
    await refreshHistory();
  }

  /// Loads a past check's stored input files and checks them again.
  Future<void> reopenHistory(HistoryEntry e) async {
    final kinds = {'A': InputKind.single, 'B': InputKind.a, 'C': InputKind.b};
    final loaded = <(InputKind, String, Uint8List)>[];
    for (final f in e.files) {
      final bytes = await history?.input(e.id, f);
      if (bytes == null) throw UserMessage('hist_err_input', {'name': f.name});
      loaded.add((kinds[f.role]!, f.name, bytes));
    }
    single = bomA = bomB = null;
    for (final (k, name, bytes) in loaded) {
      load(k, name, bytes);
    }
    settingsOpen = false;
    runCheckNow();
  }

  // ------------------------------------------------------------ local AI

  LocalStatus localStatus = LocalStatus.idle;
  String localKind = 'embedding';
  int localRows = 0, localTotal = 0, localCalls = 0;
  bool localLoading = false;

  /// Share of descriptions the local model has read (0–1).
  double localProgress = 0;
  String localError = '';
  String localErrorDetail = '';

  /// Lines the local model paired in the last check.
  int localPaired = 0;
  int localTexts = 0;
  int localMillis = 0;
  String localModelName = '';
  bool localTesting = false;
  bool _localBusy = false;
  bool _modelChanging = false;
  bool get localBusy => _localBusy || localTesting || _modelChanging;
  String localTestKey = '';
  String localTestDetail = '';
  int localTestMillis = 0;
  int _checkRun = 0;
  LocalModels? _local;
  LocalModels? _analysis;

  /// Opened on first use and kept for later checks.
  Future<LocalModels> _localModels() async => _local ??= await (localModelsFactory?.call(models, activeEmbedding) ??
          LlamaLocalModels.open(models, embedding: activeEmbedding));
  Future<LocalModels> _analysisModels() async => _analysis ??= await (localModelsFactory?.call(models, localAnalysisModel) ??
      LlamaLocalModels.openAnalysis(models));

  /// A separate real embedding call; success never claims a BOM used it.
  Future<void> testLocalModel() async {
    if (localBusy || !activeLocalReady) return;
    localTesting = true;
    localTestKey = 'local_test_running';
    localTestDetail = '';
    notifyListeners();
    final watch = Stopwatch()..start();
    try {
      if (localAnalysisRequired) {
        final model = await _analysisModels();
        final reply = await model.structured(system: 'Return JSON {"ok":true}.', user: '确认能生成 JSON。',
          schema: const {'type': 'object', 'properties': {'ok': {'type': 'boolean'}}, 'required': ['ok'], 'additionalProperties': false}, maxTokens: 64);
        if (reply['ok'] != true) throw LocalAiException('bad_output');
      } else {
        final ai = await _localModels();
        checkedVectors(
        await ai.embed(['贴片电阻 10K 0402', 'Chip resistor 10kΩ 0402']),
        2,
      );
      }
      localTestKey = 'local_test_ok';
    } catch (e) {
      localTestKey = 'local_test_failed';
      localTestDetail = '$e';
      final old = _local;
      _local = null;
      await old?.dispose();
      final oldAnalysis = _analysis;
      _analysis = null;
      await oldAnalysis?.dispose();
    } finally {
      localTestMillis = watch.elapsedMilliseconds;
      localTesting = false;
      notifyListeners();
    }
  }

  Future<void> _runRequiredLocal(int run) async {
    _localBusy = true;
    localLoading = true;
    localStatus = LocalStatus.running;
    _status('status_local_required_running');
    notifyListeners();
    final watch = Stopwatch()..start();
    try {
      final draft = compareBoms(single!.bom, bomA!.bom, bomB?.bom, options: settings.compareOptions);
      localTotal = draft.rows.length;
      notifyListeners();
      final model = await _analysisModels();
      if (run != _checkRun) return;
      if (model case LocalAnalysisPreparation preparation) await preparation.prepareAnalysis();
      if (run != _checkRun) return;
      localLoading = false;
      notifyListeners();
      final result = await reviewLocally(draft, model, cancelled: () => run != _checkRun,
        onProgress: (done, total, calls) {
          if (run != _checkRun) return;
          localRows = localTexts = done;
          localTotal = total;
          localCalls = calls;
          localMillis = watch.elapsedMilliseconds;
          localProgress = total == 0 ? 0 : done / total;
          notifyListeners();
        });
      if (run != _checkRun) return;
      report = result.report;
      _historyId = HistoryStore.newId(report!.at);
      localRows = localTexts = result.rows;
      localCalls = result.calls;
      localMillis = watch.elapsedMilliseconds;
      localStatus = LocalStatus.done;
      _checkedStatus();
    } catch (e) {
      if (run != _checkRun) return;
      report = null;
      localStatus = LocalStatus.failed;
      localMillis = watch.elapsedMilliseconds;
      localError = e is LocalAiException ? 'local_err_${e.code}' : 'local_err_inference_failed';
      localErrorDetail = '$e';
      _status('status_local_required_failed', {'e': Strings(language).t(localError)});
      final old = _analysis;
      _analysis = null;
      await old?.dispose();
    } finally {
      localLoading = false;
      _localBusy = false;
      notifyListeners();
    }
  }

  void cancelLocalAnalysis() {
    if (!_localBusy || localKind != 'analysis') return;
    _checkRun++;
    localLoading = false;
    if (_analysis case final LlamaLocalModels model) model.cancel();
    report = null;
    localStatus = LocalStatus.idle;
    localError = 'local_err_cancelled';
    _status('local_analysis_cancelled');
    notifyListeners();
  }

  Future<void> _runLocal(int run) async {
    _localBusy = true;
    localStatus = LocalStatus.running;
    _status('status_local_running');
    notifyListeners();
    final watch = Stopwatch()..start();
    try {
      final ai = await _localModels();
      if (run != _checkRun) return;
      final first = report!;
      final sug = await semanticSuggestions(first, ai, cancelled: () => run != _checkRun,
        onEmbedded: (n) {
          if (run == _checkRun) localTexts = n;
        },
        onProgress: (p) {
          if (run != _checkRun) return;
          localProgress = p;
        notifyListeners();
      });
      if (run != _checkRun) return;
      report = compareBoms(single!.bom, bomA!.bom, bomB?.bom, semantic: sug, options: settings.compareOptions);
      report!.pending = settings.checkMode == CheckMode.hybrid;
      localPaired = sug.length;
      localMillis = watch.elapsedMilliseconds;
      localStatus = LocalStatus.done;
      _checkedStatus();
    } catch (e) {
      if (run != _checkRun) return;
      // The rule result stands; the failure is shown, not hidden.
      localStatus = LocalStatus.failed;
      localMillis = watch.elapsedMilliseconds;
      localError = e is LocalAiException
          ? 'local_err_${e.code}'
          : 'local_err_inference_failed';
      report!.pending = false;
      _checkedStatus();
      _status('status_local_failed', {'e': '$e'});
    } finally {
      _localBusy = false;
    }
    if (run != _checkRun) return;
    notifyListeners();
    _afterLocal(run);
  }

  void setAiEnabled(bool v) {
    settings.aiEnabled = v;
    persist();
    notifyListeners();
    if (!localAnalysisRequired && v && report != null && ai == null && aiStatus != AiStatus.running && cloudReady) runAi();
  }

  // ----------------------------------------------------------------- cloud

  final KeyStore keys;

  /// API key of the selected provider, read from the key store.
  String cloudKey = '';

  /// Every cloud request of this session (no prompt text or key), newest last.
  final requestLog = <RequestRecord>[];
  final sessionUsage = Usage();

  bool get cloudReady => cloudKey.trim().isNotEmpty || (settings.cloud.kind == ProviderKind.custom && settings.cloud.url.isNotEmpty);

  /// Reads the selected provider's key; moves a 2.0 plain-text key into
  /// the key store and out of the settings file.
  Future<void> loadKeys() async {
    if (settings.legacyApiKey.isNotEmpty) {
      await keys.write(settings.cloud.kind.name, settings.legacyApiKey);
      await persist();
    }
    cloudKey = await keys.read(settings.cloud.kind.name) ?? '';
    notifyListeners();
  }

  Future<void> setCloudKey(String key) async {
    cloudKey = key.trim();
    if (cloudKey.isEmpty) {
      await keys.delete(settings.cloud.kind.name);
    } else {
      await keys.write(settings.cloud.kind.name, cloudKey);
    }
    notifyListeners();
  }

  /// Switching vendor loads that vendor's key.
  Future<void> updateCloud(ProviderConfig cfg) async {
    final kindChanged = cfg.kind != settings.cloud.kind;
    settings.cloud = cfg;
    persist();
    if (kindChanged) cloudKey = await keys.read(cfg.kind.name) ?? '';
    notifyListeners();
  }

  CloudProvider get cloudProvider => HttpCloudProvider(settings.cloud, cloudKey, onRecord: _record);

  void _record(RequestRecord r) {
    requestLog.add(r);
    if (requestLog.length > 200) requestLog.removeAt(0);
    sessionUsage.add(r.usage);
    notifyListeners();
  }

  CloudCancel? _aiCancel;

  /// Sends the comparison to the configured model; a newer run or a reload
  /// discards an older answer.
  Future<void> runAi() async {
    if (localAnalysisRequired) return;
    final r = report;
    if (r == null) return;
    final run = ++_aiRun;
    _aiCancel?.cancel();
    final cancel = _aiCancel = CloudCancel();
    aiStatus = AiStatus.running;
    aiError = '';
    aiErrorDetail = '';
    notifyListeners();
    try {
      final result = await runAiCheck(cloudProvider, r, cancel: cancel, privacy: settings.privacy);
      if (run != _aiRun) return;
      ai = result;
      aiStatus = AiStatus.done;
      _status('status_ai_done', {'n': result.findings.length});
      _archive();
    } on CloudException catch (e) {
      if (run != _aiRun) return;
      aiStatus = AiStatus.failed;
      aiError = 'err_cloud_${e.code}';
      aiErrorDetail = e.detail;
    }
    notifyListeners();
  }

  void cancelAi() {
    _aiCancel?.cancel();
    _aiRun++;
    aiStatus = AiStatus.idle;
    notifyListeners();
  }

  // ------------------------------------------------------------------- view

  /// Risk and reason filters; null shows every row.
  Risk? riskFilter;
  String? reasonFilter;

  void setRiskFilter(Risk? r) {
    riskFilter = r;
    notifyListeners();
  }

  void setReasonFilter(String? r) {
    reasonFilter = r;
    notifyListeners();
  }

  void setFilter(CheckStatus? s) {
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
      if (riskFilter != null && riskOf(row) != riskFilter) return false;
      if (reasonFilter == 'orientation'
          ? row.orientation.isEmpty
          : reasonFilter != null && !row.reasons.contains(reasonFilter)) {
        return false;
      }
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
