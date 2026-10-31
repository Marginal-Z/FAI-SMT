/// State of the compare page: the files of each mode with their recognised
/// columns, the result and the operator's edits.
library;

import 'package:flutter/foundation.dart';

import 'app_state.dart' show UserMessage;
import 'core/compare.dart';
import 'core/models.dart';
import 'core/parsers.dart';
import 'core/settings.dart';
import 'core/smart_table.dart';
import 'core/table_reader.dart';

enum CompareSlot { bomA, bomB, station, stationA, stationB }

/// Files each mode compares; all of them are required.
const compareSlots = {
  CompareMode.bomBom: [CompareSlot.bomA, CompareSlot.bomB],
  CompareMode.bomStation: [CompareSlot.bomA, CompareSlot.station],
  CompareMode.bomStationAB: [CompareSlot.bomA, CompareSlot.stationA, CompareSlot.stationB],
};

bool isBomSlot(CompareSlot s) => s == CompareSlot.bomA || s == CompareSlot.bomB;

/// Tabs of the compare page once a result exists.
enum CompareTab { preview, report, refs, columns }

/// One imported table: the sheets as read, the recognised (or adjusted)
/// layout and what was parsed from it.
class TableFile {
  TableFile({required this.name, required this.size, required this.grids, required this.layout});

  final String name;
  final int size;
  final List<Grid> grids;
  TableLayout layout;
  List<BomItem> bom = const [];
  List<StationItem> stations = const [];
  List<ParseIssue> issues = const [];

  /// Set when the adjusted columns no longer give a part number and designators.
  String? error;

  int get count => bom.isNotEmpty ? bom.length : stations.length;
}

class CompareSession extends ChangeNotifier {
  CompareSession(this._rules);

  final CheckRules Function() _rules;

  CompareMode mode = CompareMode.bomBom;
  final Map<CompareSlot, TableFile> files = {};
  CompareResult? result;
  CompareTab tab = CompareTab.preview;
  CheckCategory? filter;
  String search = '';

  List<CompareSlot> get slots => compareSlots[mode]!;
  bool get ready => slots.every((s) => files[s] != null && files[s]!.error == null);

  void setMode(CompareMode m) {
    if (m == mode) return;
    mode = m;
    result = null;
    filter = null;
    tab = CompareTab.preview;
    notifyListeners();
  }

  void setTab(CompareTab t) {
    tab = t;
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

  /// Reads and recognises a file for [slot]. Throws [UserMessage].
  void load(CompareSlot slot, String name, Uint8List bytes) {
    final List<Grid> grids;
    try {
      grids = readTableBytes(bytes, name);
    } on TableReadException catch (e) {
      throw UserMessage('err_${e.code}', {'detail': e.detail});
    }
    final bom = isBomSlot(slot);
    final layout = detectTable(grids, bom ? TableKind.bom : TableKind.station);
    if (layout == null) throw UserMessage(bom ? 'err_parse_no_header_bom' : 'err_parse_no_header_station');
    final f = TableFile(name: name, size: bytes.length, grids: grids, layout: layout);
    files[slot] = f;
    _align(slot);
    _parse(slot, f);
    result = null;
    notifyListeners();
  }

  void unload(CompareSlot slot) {
    files.remove(slot);
    result = null;
    notifyListeners();
  }

  void clear() {
    files.clear();
    result = null;
    filter = null;
    search = '';
    tab = CompareTab.preview;
    notifyListeners();
  }

  /// The user changes what column [col] of [slot] holds; the comparison
  /// runs again when it had run.
  void setRole(CompareSlot slot, int col, ColumnRole role) {
    final f = files[slot];
    if (f == null) return;
    f.layout = f.layout.withRole(col, role);
    _parse(slot, f);
    if (result != null) {
      if (ready) {
        run();
        return;
      }
      result = null;
    }
    notifyListeners();
  }

  /// Back to the recognised columns.
  void resetColumns(CompareSlot slot) {
    final f = files[slot];
    if (f == null) return;
    final layout = detectTable(f.grids, isBomSlot(slot) ? TableKind.bom : TableKind.station);
    if (layout != null) f.layout = layout;
    _align(slot);
    _parse(slot, f);
    if (result != null && ready) {
      run();
      return;
    }
    notifyListeners();
  }

  /// Lines up the part-number column with the file it is compared against.
  void _align(CompareSlot slot) {
    final f = files[slot]!;
    final partners = slot == CompareSlot.bomA ? slots.where((s) => s != slot) : [CompareSlot.bomA];
    for (final p in partners) {
      final other = files[p];
      if (other == null) continue;
      final (a, b) = alignPartColumns(f.layout, other.layout);
      if (!identical(a, f.layout) || !identical(b, other.layout)) {
        f.layout = a;
        other.layout = b;
        _parse(p, other);
      }
    }
  }

  void _parse(CompareSlot slot, TableFile f) {
    f.error = null;
    try {
      if (isBomSlot(slot)) {
        final r = parseBom(f.grids, layout: f.layout);
        f.bom = r.items;
        f.issues = r.issues;
      } else {
        final side = slot == CompareSlot.stationB ? StationSide.b : StationSide.a;
        final r = parseStation(f.grids, side, layout: f.layout);
        f.stations = r.items;
        f.issues = r.issues;
      }
    } on ParseException catch (e) {
      f.bom = const [];
      f.stations = const [];
      f.issues = const [];
      f.error = e.code;
    }
  }

  Map<String, String> get _fileNames => {for (final s in slots) if (files[s] != null) s.name: files[s]!.name};

  /// Runs the comparison of the current mode. Edits made to rows that come
  /// out the same are kept.
  void run() {
    for (final s in slots) {
      final f = files[s];
      if (f == null) throw UserMessage(isBomSlot(s) ? 'msg_need_bom' : 'msg_need_station');
      if (f.error != null) throw UserMessage('err_${f.error}');
    }
    final rules = _rules();
    final old = result;
    final bomA = files[CompareSlot.bomA]!;
    final CompareResult next;
    switch (mode) {
      case CompareMode.bomBom:
        final bomB = files[CompareSlot.bomB]!;
        bool both(ColumnRole r) => bomA.layout.col(r) != null && bomB.layout.col(r) != null;
        next = compareBoms(bomA.bom, bomB.bom, rules,
            issuesA: bomA.issues,
            issuesB: bomB.issues,
            files: _fileNames,
            compareDescriptions: both(ColumnRole.desc),
            compareAlternates: both(ColumnRole.alt));
      case CompareMode.bomStation:
        final st = files[CompareSlot.station]!;
        next = compareBomStations(bomA.bom, st.stations, rules,
            mode: mode, bomIssues: bomA.issues, stationAIssues: st.issues, files: _fileNames);
      case CompareMode.bomStationAB:
        final a = files[CompareSlot.stationA]!, b = files[CompareSlot.stationB]!;
        // List B is side B throughout, even with a side column of its own.
        final stB = [
          for (final s in b.stations)
            StationItem(partNo: s.partNo, side: StationSide.b, slot: s.slot, desc: s.desc, qty: s.qty, refs: s.refs, relatedTo: s.relatedTo, sourceRow: s.sourceRow),
        ];
        final stA = [
          for (final s in a.stations)
            StationItem(partNo: s.partNo, side: StationSide.a, slot: s.slot, desc: s.desc, qty: s.qty, refs: s.refs, relatedTo: s.relatedTo, sourceRow: s.sourceRow),
        ];
        next = compareBomStations(bomA.bom, [...stA, ...stB], rules,
            mode: mode, bomIssues: bomA.issues, stationAIssues: a.issues, stationBIssues: b.issues, files: _fileNames);
    }
    if (old != null && old.mode == next.mode) _carryEdits(old, next);
    result = next;
    notifyListeners();
  }

  /// Re-runs after the rules changed.
  void rerun() {
    if (result != null && ready) run();
  }

  static String _identity(ResultRow r) => r.originalCells.containsKey('pn') ? r.originalCells['pn']! : '${r.originalCells['pnA']}|${r.originalCells['pnB']}';

  void _carryEdits(CompareResult old, CompareResult next) {
    final edited = {for (final r in old.rows) if (r.edited) _identity(r): r};
    for (final r in next.rows) {
      final o = edited[_identity(r)];
      if (o == null || o.originalCategory != r.originalCategory) continue;
      r.category = o.category;
      r.note = o.note;
      for (final k in o.cells.keys) {
        if (o.cellEdited(k) && (o.originalCells[k] ?? '') == (r.originalCells[k] ?? '')) r.cells[k] = o.cells[k]!;
      }
    }
  }

  void setCell(ResultRow row, String key, String value) {
    row.cells[key] = value;
    notifyListeners();
  }

  void setCategory(ResultRow row, CheckCategory c) {
    row.category = c;
    notifyListeners();
  }

  void setNote(ResultRow row, String note) {
    row.note = note;
    notifyListeners();
  }

  void resetRow(ResultRow row) {
    row.reset();
    notifyListeners();
  }

  void resetAllEdits() {
    for (final r in result?.rows ?? const <ResultRow>[]) {
      r.reset();
    }
    notifyListeners();
  }

  /// Base name for exported files.
  String get exportBaseName {
    final n = files[CompareSlot.bomA]?.name ?? 'SMT-FAI';
    final dot = n.lastIndexOf('.');
    return '${dot > 0 ? n.substring(0, dot) : n}_${mode.name}';
  }
}
