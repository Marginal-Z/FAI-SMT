// ignore_for_file: avoid_print
// Prints the first rows of every sheet of a table file, as the app reads it.
//
//   dart run tool/dump_table.dart <file> [rows]
import 'package:smt_fai/core/table_reader.dart';

Future<void> main(List<String> args) async {
  final limit = args.length > 1 ? int.parse(args[1]) : 25;
  for (final g in await readTableFile(args[0])) {
    print('=== sheet "${g.name}" rows=${g.rows.length}');
    for (var i = 0; i < g.rows.length && i < limit; i++) {
      print('$i: ${g.rows[i].join(' | ')}');
    }
  }
}
