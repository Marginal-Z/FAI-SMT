/// Check history: every finished check is kept under the settings folder
/// with copies of its input files (and their SHA-256), the options it ran
/// with, its counts, a line list for searching and the full Excel report as
/// it was then, so a result can be traced long after the files changed.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'bom_compare.dart';

/// One input file of a check: `A`, `B` or `C` as the files are named to the
/// user.
class HistoryFile {
  const HistoryFile({required this.role, required this.name, required this.size, required this.sha256});

  final String role;
  final String name;
  final int size;
  final String sha256;

  /// Stored copy, inside the entry's folder.
  String get stored => 'input_$role${p.extension(name)}';

  Map<String, dynamic> toJson() => {'role': role, 'name': name, 'size': size, 'sha256': sha256};

  factory HistoryFile.fromJson(Map<String, dynamic> j) => HistoryFile(role: '${j['role']}', name: '${j['name']}', size: (j['size'] as num?)?.toInt() ?? 0, sha256: '${j['sha256'] ?? ''}');
}

class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.at,
    required this.mode,
    required this.models,
    required this.files,
    required this.counts,
    required this.skipped,
    required this.complete,
    required this.appVersion,
  });

  final String id;
  final DateTime at;
  final String mode;
  final List<String> models;
  final List<HistoryFile> files;

  /// Lines per result (`pass`, `ng`, …).
  final Map<String, int> counts;
  final List<String> skipped;
  final bool complete;
  final String appVersion;

  int get lines => counts.values.fold(0, (a, b) => a + b);

  Map<String, dynamic> toJson() => {
    'id': id,
    'at': at.toIso8601String(),
    'mode': mode,
    'models': models,
    'files': [for (final f in files) f.toJson()],
    'counts': counts,
    'skipped': skipped,
    'complete': complete,
    'appVersion': appVersion,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    id: '${j['id']}',
    at: DateTime.tryParse('${j['at']}') ?? DateTime.fromMillisecondsSinceEpoch(0),
    mode: '${j['mode'] ?? 'local'}',
    models: [for (final m in (j['models'] as List? ?? const [])) '$m'],
    files: [for (final f in (j['files'] as List? ?? const [])) HistoryFile.fromJson((f as Map).cast())],
    counts: {for (final e in ((j['counts'] as Map?) ?? const {}).entries) '${e.key}': (e.value as num).toInt()},
    skipped: [for (final m in (j['skipped'] as List? ?? const [])) '$m'],
    complete: j['complete'] != false,
    appVersion: '${j['appVersion'] ?? ''}',
  );
}

/// A result line as kept for searching and reading back.
class HistoryLine {
  const HistoryLine({required this.partNo, required this.status, required this.reasons, this.otherPartNo = '', this.description = ''});

  final String partNo;

  /// The counterpart's number when it differs (substitutes, split lines).
  final String otherPartNo;
  final CheckStatus status;
  final List<String> reasons;
  final String description;

  Map<String, dynamic> toJson() => {'p': partNo, if (otherPartNo.isNotEmpty) 'o': otherPartNo, 's': status.name, 'r': reasons, 'd': description};

  factory HistoryLine.fromJson(Map<String, dynamic> j) => HistoryLine(
    partNo: '${j['p']}',
    otherPartNo: '${j['o'] ?? ''}',
    status: CheckStatus.values.firstWhere((s) => s.name == j['s'], orElse: () => CheckStatus.review),
    reasons: [for (final r in (j['r'] as List? ?? const [])) '$r'],
    description: '${j['d'] ?? ''}',
  );

  factory HistoryLine.of(CompareRow r) {
    final others = {for (final q in r.mergedParts) q.partNo}..remove(r.partNo);
    return HistoryLine(
      partNo: r.partNo,
      otherPartNo: others.join(','),
      status: r.status,
      reasons: r.reasons,
      description: r.single?.description ?? r.merged?.description ?? '',
    );
  }

  bool matches(String q) => partNo.toLowerCase().contains(q) || otherPartNo.toLowerCase().contains(q) || description.toLowerCase().contains(q);
}

class HistoryStore {
  HistoryStore(this.dir);

  /// `<settings>/history`; one folder per check.
  final String dir;

  String _folder(String id) => p.join(dir, id);

  /// A new id from the time of the check: sortable and readable.
  static String newId(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${at.year}${two(at.month)}${two(at.day)}-${two(at.hour)}${two(at.minute)}${two(at.second)}-${at.millisecond.toString().padLeft(3, '0')}';
  }

  /// Keeps a check under [id] (an existing entry is replaced, so a check
  /// refined by the local model or the cloud stays one entry).
  Future<HistoryEntry> save({
    required String id,
    required CompareReport report,
    required List<(String role, String name, Uint8List bytes)> files,
    required Uint8List workbook,
    String appVersion = '',
  }) async {
    final folder = Directory(_folder(id));
    await folder.create(recursive: true);
    final kept = <HistoryFile>[];
    for (final (role, name, bytes) in files) {
      final f = HistoryFile(role: role, name: name, size: bytes.length, sha256: sha256.convert(bytes).toString());
      await File(p.join(folder.path, f.stored)).writeAsBytes(bytes, flush: true);
      kept.add(f);
    }
    final entry = HistoryEntry(
      id: id,
      at: report.at,
      mode: report.mode,
      models: report.models,
      files: kept,
      counts: {for (final st in CheckStatus.values) st.name: report.count(st)},
      skipped: report.skipped,
      complete: report.complete,
      appVersion: appVersion,
    );
    await File(p.join(folder.path, 'report.xlsx')).writeAsBytes(workbook, flush: true);
    await File(p.join(folder.path, 'lines.json')).writeAsString(jsonEncode([for (final r in report.rows) HistoryLine.of(r).toJson()]));
    // Written last: an entry without it is unfinished and not listed.
    await File(p.join(folder.path, 'entry.json')).writeAsString(const JsonEncoder.withIndent('  ').convert(entry.toJson()));
    return entry;
  }

  /// All entries, newest first. Unreadable folders are skipped.
  Future<List<HistoryEntry>> list() async {
    final root = Directory(dir);
    if (!await root.exists()) return const [];
    final out = <HistoryEntry>[];
    await for (final d in root.list()) {
      if (d is! Directory) continue;
      try {
        final f = File(p.join(d.path, 'entry.json'));
        if (await f.exists()) out.add(HistoryEntry.fromJson(jsonDecode(await f.readAsString()) as Map<String, dynamic>));
      } catch (_) {
        // A damaged entry is left on disk but not listed.
      }
    }
    out.sort((a, b) => b.at.compareTo(a.at));
    return out;
  }

  Future<List<HistoryLine>> lines(String id) async {
    final f = File(p.join(_folder(id), 'lines.json'));
    if (!await f.exists()) return const [];
    return [for (final j in jsonDecode(await f.readAsString()) as List) HistoryLine.fromJson((j as Map).cast())];
  }

  Future<Uint8List> workbook(String id) => File(p.join(_folder(id), 'report.xlsx')).readAsBytes();

  /// The stored copy of an input file; null when it is gone or no longer
  /// matches its recorded hash.
  Future<Uint8List?> input(String id, HistoryFile f) async {
    final file = File(p.join(_folder(id), f.stored));
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString() == f.sha256 ? bytes : null;
  }

  /// Entries whose file names or lines match [query] (case-insensitive),
  /// with the matching lines.
  Future<List<(HistoryEntry, List<HistoryLine>)>> search(String query, {List<HistoryEntry>? entries}) async {
    final q = query.trim().toLowerCase();
    final all = entries ?? await list();
    if (q.isEmpty) return [for (final e in all) (e, const <HistoryLine>[])];
    final out = <(HistoryEntry, List<HistoryLine>)>[];
    for (final e in all) {
      final byName = e.files.any((f) => f.name.toLowerCase().contains(q));
      final hits = (await lines(e.id)).where((l) => l.matches(q)).toList();
      if (byName || hits.isNotEmpty) out.add((e, hits));
    }
    return out;
  }

  Future<void> delete(String id) async {
    final d = Directory(_folder(id));
    if (await d.exists()) await d.delete(recursive: true);
  }

  /// Disk space the history takes.
  Future<int> bytes() async {
    final root = Directory(dir);
    if (!await root.exists()) return 0;
    var n = 0;
    await for (final f in root.list(recursive: true)) {
      if (f is File) n += await f.length();
    }
    return n;
  }
}
