// ignore_for_file: avoid_print
// Prints how a table file is recognised: header row and column roles.
//
//   dart run tool/detect_table.dart <file> [bom|station]
import 'package:smt_fai/core/smart_table.dart';
import 'package:smt_fai/core/table_reader.dart';

Future<void> main(List<String> args) async {
  final kind = args.length > 1 && args[1] == 'station' ? TableKind.station : TableKind.bom;
  final layout = detectTable(await readTableFile(args[0]), kind);
  if (layout == null) {
    print('not recognised');
    return;
  }
  print('sheet "${layout.sheet.name}" header row ${layout.headerRow + 1} score ${layout.score.toStringAsFixed(2)}');
  for (final c in layout.columns) {
    print('${c.letter.padRight(3)} ${c.role.name.padRight(8)} ${c.confidence.toStringAsFixed(2)}  ${c.header}  ${c.samples.join(' | ')}');
  }
}
