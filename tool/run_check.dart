// ignore_for_file: avoid_print
// Runs the check on real files and prints a summary (development aid).
//
//   dart run tool/run_check.dart <bom> <stationA> [stationB] [coords]
import 'package:smt_fai/core/checker.dart';
import 'package:smt_fai/core/discrepancies.dart';
import 'package:smt_fai/core/exporters.dart';
import 'package:smt_fai/core/models.dart';
import 'package:smt_fai/core/parsers.dart';
import 'package:smt_fai/core/settings.dart';
import 'package:smt_fai/core/table_reader.dart';
import 'package:smt_fai/l10n/texts.dart';

Future<void> main(List<String> a) async {
  final s = Texts('zh');
  final bom = parseBom(await readTableFile(a[0]));
  print('BOM: ${bom.items.length} items, columns ${bom.columns}, issues ${bom.issues.map((i) => s.t(i.code, {'row': i.row, 'detail': i.detail}))}');
  final st = <StationItem>[];
  for (var i = 1; i < a.length && i <= 2; i++) {
    final r = parseStation(await readTableFile(a[i]), i == 1 ? StationSide.a : StationSide.b);
    print('Station ${i == 1 ? 'A' : 'B'}: ${r.items.length} rows, ${r.items.fold<int>(0, (n, e) => n + e.refs.length)} refs, columns ${r.columns}');
    for (final iss in r.issues) {
      print('   ! ${s.t(iss.code, {'row': iss.row, 'detail': iss.detail})}');
    }
    st.addAll(r.items);
  }
  final rep = runCheck(bom.items, st, CheckRules());
  for (final c in CheckCategory.values) {
    print('${c.name}: ${rep.count(c)}');
  }
  for (final r in rep.rows.where((r) => r.category != CheckCategory.pass)) {
    print('[${r.category.name}] ${r.partNo} ${r.description.length > 30 ? r.description.substring(0, 30) : r.description} | ${r.reasons.map((x) => s.t(x.code, x.args)).join('; ')}');
  }
  if (a.length > 3) {
    final c = parseCoordinates(await readTableFile(a[3]));
    print('Coords: ${c.items.length}, columns ${c.columns}, issues ${c.issues.length}');
    final cad = buildCad(c.items, rep, CadTemplate(), CheckRules());
    print('CAD rows ${cad.rows.length}; no coord ${cad.noCoordRefs}; not in BOM ${cad.notInBomRefs.length}; unknown side ${cad.unknownSide.length}');
    print(cad.previewLines(limit: 6).join('\n'));
    final layers = <String, Map<BoardSide, int>>{};
    for (final r in cad.rows) {
      final side = r.merged?.side?.name ?? '-';
      layers.putIfAbsent(side, () => {}).update(r.placement.side, (n) => n + 1, ifAbsent: () => 1);
    }
    print('station side -> coordinate layer: $layers');
    final ds = findDiscrepancies(bom: bom.items, stations: st, report: rep, rules: CheckRules(), placements: c.items, coordIssues: c.issues);
    for (final v in Severity.values) {
      print('${v.name}: ${ds.where((d) => d.severity == v).length}');
    }
    for (final d in ds.where((d) => d.severity != Severity.info).take(30)) {
      print('  [${d.severity.name}/${d.source.name}] ${d.subject}: ${s.t(d.code, d.args)}');
    }
  }
}
