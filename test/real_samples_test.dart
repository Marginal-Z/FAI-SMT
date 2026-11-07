// The user's own files under samples/ (never committed): runs only where
// they exist. Guards against regressions found on real exports.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/bom.dart';
import 'package:smt_fai/core/bom_compare.dart';
import 'package:smt_fai/core/table_reader.dart';

BomDocument _read(String path, String id) => readBom(readTableBytes(File(path).readAsBytesSync(), path), file: path.split('/').last, id: id);

File? _first(String dir, String suffix) {
  final d = Directory('samples/$dir');
  if (!d.existsSync()) return null;
  return d.listSync().whereType<File>().where((f) => f.path.endsWith(suffix)).firstOrNull;
}

void main() {
  final bom = _first('BOM', '.xlsx'), a = _first('station', '-A.xlsx'), b = _first('station', '-B.xlsx');
  final skip = bom == null || a == null || b == null ? 'real sample files not present' : null;

  test('real T100 BOM against station lists A and B', () {
    final s = _read(bom!.path, 'S'), da = _read(a!.path, 'A'), db = _read(b!.path, 'B');
    // Slot numbers such as "1- 2" are not part of the description.
    for (final d in [da, db]) {
      expect(d.columns.where((c) => c.role == BomRole.description).map((c) => c.header), ['物料描述']);
    }
    final r = compareBoms(s, da, db);
    expect(r.complete, isTrue);
    // One real difference (an inductor's package) was confirmed on these files.
    expect(r.count(DiffStatus.different), lessThanOrEqualTo(1));
    expect(r.count(DiffStatus.same), greaterThanOrEqualTo(119));
  }, skip: skip);
}
