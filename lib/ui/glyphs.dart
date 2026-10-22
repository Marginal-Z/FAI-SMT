/// Command icons for the ribbon and title bar: Fluent UI System Icons
/// (Microsoft, MIT — assets/fonts/FluentSystemIcons-LICENSE.txt), the set
/// Office uses for its ribbons. Regular outline normally, filled when active.
library;

import 'package:flutter/widgets.dart';

import 'theme.dart';

enum Glyph {
  bom,
  stationA,
  stationB,
  coords,
  unitAuto,
  unit,
  clear,
  runCheck,
  report,
  exclusion,
  alternates,
  program,
  general,
  layersBoth,
  layerTop,
  layerBottom,
  fit,
  cadFormat,
  cad,
  globe,
  sun,
  moon,
  system,
  info,
  mirror,
  rotateLeft,
  rotateRight,
  settings,
  update,
  download,
  materials,
  discrepancies,
}

const _regular = 'FluentSystemIcons-Regular';
const _filled = 'FluentSystemIcons-Filled';

const Map<Glyph, (IconData, IconData)> _glyphs = {
  Glyph.bom: (IconData(63407, fontFamily: _regular), IconData(63431, fontFamily: _filled)), // text_bullet_list_tree
  Glyph.stationA: (IconData(60504, fontFamily: _regular), IconData(60498, fontFamily: _filled)), // table_stack_above
  Glyph.stationB: (IconData(60508, fontFamily: _regular), IconData(60502, fontFamily: _filled)), // table_stack_below
  Glyph.coords: (IconData(60002, fontFamily: _regular), IconData(60010, fontFamily: _filled)), // scan_object
  Glyph.unitAuto: (IconData(60984, fontFamily: _regular), IconData(60984, fontFamily: _filled)), // wand
  Glyph.unit: (IconData(63101, fontFamily: _regular), IconData(63111, fontFamily: _filled)), // ruler
  Glyph.clear: (IconData(58853, fontFamily: _regular), IconData(58866, fontFamily: _filled)), // eraser
  Glyph.runCheck: (IconData(58206, fontFamily: _regular), IconData(58227, fontFamily: _filled)), // clipboard_task
  Glyph.report: (IconData(984359, fontFamily: _regular), IconData(984480, fontFamily: _filled)), // document_arrow_down
  Glyph.exclusion: (IconData(58671, fontFamily: _regular), IconData(58683, fontFamily: _filled)), // document_prohibited
  Glyph.alternates: (IconData(61838, fontFamily: _regular), IconData(61838, fontFamily: _filled)), // arrow_swap
  Glyph.program: (IconData(58905, fontFamily: _regular), IconData(58918, fontFamily: _filled)), // flash
  Glyph.general: (IconData(62856, fontFamily: _regular), IconData(62866, fontFamily: _filled)), // options
  Glyph.layersBoth: (IconData(62668, fontFamily: _regular), IconData(62678, fontFamily: _filled)), // layer
  Glyph.layerTop: (IconData(59823, fontFamily: _regular), IconData(59841, fontFamily: _filled)), // position_to_front
  Glyph.layerBottom: (IconData(59821, fontFamily: _regular), IconData(59839, fontFamily: _filled)), // position_to_back
  Glyph.fit: (IconData(61069, fontFamily: _regular), IconData(61069, fontFamily: _filled)), // zoom_fit
  Glyph.cadFormat: (IconData(63351, fontFamily: _regular), IconData(63375, fontFamily: _filled)), // table_settings
  Glyph.cad: (IconData(62300, fontFamily: _regular), IconData(62300, fontFamily: _filled)), // developer_board
  Glyph.globe: (IconData(62555, fontFamily: _regular), IconData(62559, fontFamily: _filled)), // globe
  Glyph.sun: (IconData(63650, fontFamily: _regular), IconData(63674, fontFamily: _filled)), // weather_sunny
  Glyph.moon: (IconData(63614, fontFamily: _regular), IconData(63638, fontFamily: _filled)), // weather_moon
  Glyph.system: (IconData(62268, fontFamily: _regular), IconData(62268, fontFamily: _filled)), // dark_theme
  Glyph.info: (IconData(62628, fontFamily: _regular), IconData(62635, fontFamily: _filled)), // info
  Glyph.mirror: (IconData(58925, fontFamily: _regular), IconData(58938, fontFamily: _filled)), // flip_horizontal
  Glyph.rotateLeft: (IconData(61832, fontFamily: _regular), IconData(61832, fontFamily: _filled)), // arrow_rotate_counterclockwise
  Glyph.rotateRight: (IconData(61830, fontFamily: _regular), IconData(61830, fontFamily: _filled)), // arrow_rotate_clockwise
  Glyph.settings: (IconData(63146, fontFamily: _regular), IconData(63155, fontFamily: _filled)), // settings
  Glyph.update: (IconData(61841, fontFamily: _regular), IconData(61841, fontFamily: _filled)), // arrow_sync
  Glyph.download: (IconData(61777, fontFamily: _regular), IconData(61777, fontFamily: _filled)), // arrow_download
  Glyph.materials: (IconData(62702, fontFamily: _regular), IconData(62712, fontFamily: _filled)), // list
  Glyph.discrepancies: (IconData(63594, fontFamily: _regular), IconData(63618, fontFamily: _filled)), // warning
};

class GlyphIcon extends StatelessWidget {
  const GlyphIcon(this.glyph, {super.key, this.size = 24, this.color, this.filled = false, this.disabled = false});

  final Glyph glyph;
  final double size;
  final Color? color;
  final bool filled;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final (regular, solid) = _glyphs[glyph]!;
    return Icon(filled ? solid : regular, size: size, color: disabled ? c.textFaint : (color ?? c.text));
  }
}
