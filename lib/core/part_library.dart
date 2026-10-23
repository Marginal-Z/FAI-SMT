/// Library of part models for the PCB navigator: one entry per kind of
/// component found on SMT boards (chip passives, electrolytics, inductors,
/// diodes, LEDs, transistors, IC packages, crystals, connectors, switches,
/// acoustics, mechanical parts ...). Each model carries its colour group,
/// typical body size and height and its real body colour; the drawing is
/// in ui/part_render.dart.
library;

import 'footprints.dart';

class PartModel {
  const PartModel(this.id, this.kind, this.width, this.height, this.bodyHeight, this.realColor, {this.keywords = ''});

  /// Stable id, also the text key suffix (`pm_<id>`) and settings value.
  final String id;

  /// Colour group in the navigator legend and palette.
  final PartKind kind;

  /// Typical body length (X), width (Y) and height above the board, mm.
  final double width;
  final double height;
  final double bodyHeight;

  /// Body colour of the real part (ARGB), used by the "real colours" mode.
  final int realColor;

  /// Package names and words that select this model, for the library page.
  final String keywords;
}

const partLibrary = <PartModel>[
  // Resistors
  PartModel('chip_resistor', PartKind.resistor, 1.0, 0.5, 0.35, 0xFF1F2124, keywords: 'R 0201 0402 0603 0805 1206 电阻 RES'),
  PartModel('res_array', PartKind.resistor, 2.0, 1.0, 0.45, 0xFF1F2124, keywords: 'RN RP 排阻 ARRAY 0402X4'),
  PartModel('thermistor', PartKind.resistor, 1.0, 0.5, 0.5, 0xFF2A2D31, keywords: 'NTC PTC RT 热敏'),
  PartModel('varistor', PartKind.resistor, 1.6, 0.8, 0.8, 0xFF5E7187, keywords: 'RV ZNR VDR 压敏 VARISTOR'),
  PartModel('melf', PartKind.resistor, 3.6, 1.4, 1.4, 0xFF8DB3D6, keywords: 'MELF MINIMELF 0204'),
  // Capacitors
  PartModel('mlcc', PartKind.capacitor, 1.0, 0.5, 0.5, 0xFFC29B6E, keywords: 'C 0201 0402 0603 0805 1206 电容 MLCC'),
  PartModel('tantalum', PartKind.capacitor, 3.5, 2.8, 1.9, 0xFFE3A21F, keywords: 'TC 钽 TANT TAJ 3216 3528 6032 7343'),
  PartModel('polymer', PartKind.capacitor, 3.5, 2.8, 1.9, 0xFF2B2D31, keywords: '聚合物 POLYMER POSCAP'),
  PartModel('elcap', PartKind.capacitor, 6.6, 6.6, 5.4, 0xFFC7CDD3, keywords: 'EC CE 电解 ELEC 铝电解'),
  // Inductors and magnetics
  PartModel('chip_inductor', PartKind.inductor, 1.6, 0.8, 0.8, 0xFF4B4F55, keywords: 'L 0402 0603 0805 叠层 贴片电感'),
  PartModel('bead', PartKind.inductor, 1.0, 0.5, 0.5, 0xFF3A3D42, keywords: 'FB 磁珠 BEAD'),
  PartModel('power_inductor', PartKind.inductor, 4.0, 4.0, 2.0, 0xFF4E535A, keywords: '一体 功率电感 2520 4040 MOLDED'),
  PartModel('drum_inductor', PartKind.inductor, 5.4, 5.2, 3.0, 0xFF2C2E31, keywords: '绕线 工字 CD54 CD32 SDR'),
  PartModel('cm_choke', PartKind.inductor, 3.2, 2.5, 2.0, 0xFF2C2E31, keywords: '共模 CMC COMMON MODE'),
  PartModel('transformer', PartKind.inductor, 10.0, 10.0, 6.0, 0xFF2C2E31, keywords: 'T 变压器 TRANSFORMER'),
  // Diodes and LEDs
  PartModel('diode_sod', PartKind.diode, 2.7, 1.6, 1.1, 0xFF26292D, keywords: 'D SOD-123 SOD-323 SOD-523 二极管 TVS ZENER'),
  PartModel('diode_sma', PartKind.diode, 4.3, 2.6, 2.2, 0xFF26292D, keywords: 'SMA SMB SMC DO-214'),
  PartModel('diode_melf', PartKind.diode, 3.5, 1.5, 1.5, 0xFFB5432F, keywords: 'LL-34 LL34 MINIMELF 玻封'),
  PartModel('led_chip', PartKind.led, 1.6, 0.8, 0.6, 0xFFEFEEE9, keywords: 'LED 0402 0603 0805'),
  PartModel('led_plcc', PartKind.led, 3.5, 2.8, 1.9, 0xFFF2F1ED, keywords: 'LED 2835 3528 5050 3030 PLCC RGB WS2812'),
  // Transistors and power packages
  PartModel('sot23', PartKind.transistor, 2.9, 1.3, 1.0, 0xFF232528, keywords: 'Q SOT-23 SOT-323 SC-70 三极管 MOS'),
  PartModel('sot23_6', PartKind.transistor, 2.9, 1.6, 1.1, 0xFF232528, keywords: 'SOT-23-5 SOT-23-6 SOT-363 SC-70-6'),
  PartModel('sot89', PartKind.transistor, 4.5, 2.5, 1.5, 0xFF232528, keywords: 'SOT-89'),
  PartModel('sot223', PartKind.transistor, 6.5, 3.5, 1.7, 0xFF232528, keywords: 'SOT-223'),
  PartModel('dpak', PartKind.transistor, 6.6, 6.1, 2.3, 0xFF232528, keywords: 'TO-252 DPAK'),
  PartModel('d2pak', PartKind.transistor, 10.2, 9.2, 4.5, 0xFF232528, keywords: 'TO-263 D2PAK'),
  PartModel('power_dfn', PartKind.transistor, 5.0, 6.0, 1.0, 0xFF232528, keywords: 'PDFN DFN5X6 POWERPAK SO-8FL'),
  // ICs
  PartModel('soic', PartKind.ic, 4.9, 3.9, 1.5, 0xFF232528, keywords: 'U SOIC SOP TSSOP MSOP SSOP ESOP'),
  PartModel('qfp', PartKind.ic, 7.0, 7.0, 1.4, 0xFF232528, keywords: 'LQFP TQFP QFP'),
  PartModel('qfn', PartKind.ic, 4.0, 4.0, 0.85, 0xFF232528, keywords: 'QFN DFN SON WSON LGA'),
  PartModel('bga', PartKind.ic, 10.0, 10.0, 1.2, 0xFF232528, keywords: 'BGA FBGA EMMC DDR LPDDR UFS'),
  PartModel('wlcsp', PartKind.ic, 2.0, 2.0, 0.5, 0xFF2B3443, keywords: 'WLCSP CSP'),
  PartModel('module', PartKind.ic, 18.0, 12.0, 2.5, 0xFFC7CCD2, keywords: '模块 MODULE WIFI BT ESP 4G'),
  // Frequency
  PartModel('crystal_smd', PartKind.crystal, 3.2, 2.5, 0.8, 0xFFC9CED4, keywords: 'Y X 晶振 3225 2520 2016 XTAL'),
  PartModel('oscillator', PartKind.crystal, 3.2, 2.5, 1.0, 0xFFC9CED4, keywords: '有源晶振 OSC TCXO 振荡器'),
  PartModel('hc49', PartKind.crystal, 11.5, 4.7, 3.6, 0xFFC9CED4, keywords: '49S HC-49 HC49SMD'),
  // Connectors
  PartModel('fpc', PartKind.connector, 9.0, 4.0, 1.5, 0xFFE3D8BF, keywords: 'FPC FFC 0.5MM 翻盖'),
  PartModel('btb', PartKind.connector, 6.0, 2.5, 0.8, 0xFFE9E3D3, keywords: 'BTB 板对板 BOARD TO BOARD'),
  PartModel('wire_to_board', PartKind.connector, 8.0, 4.5, 4.5, 0xFFF1EBDC, keywords: 'J CN CON JST PH ZH SH GH 1.25 WAFER 插座'),
  PartModel('pin_header', PartKind.connector, 10.2, 2.5, 2.5, 0xFF1F2023, keywords: 'HEADER 排针 排母 2.54 2.0MM'),
  PartModel('usb_c', PartKind.connector, 8.9, 7.3, 3.2, 0xFFC3C8CE, keywords: 'TYPE-C USB-C USBC'),
  PartModel('micro_usb', PartKind.connector, 7.5, 5.0, 2.5, 0xFFC3C8CE, keywords: 'MICRO USB MICRO-B'),
  PartModel('usb_a', PartKind.connector, 14.0, 13.1, 6.5, 0xFFC3C8CE, keywords: 'USB-A USB HDMI'),
  PartModel('sim', PartKind.connector, 15.0, 14.0, 1.5, 0xFFC3C8CE, keywords: 'SIM 卡座'),
  PartModel('sd_card', PartKind.connector, 14.0, 15.0, 1.8, 0xFFC3C8CE, keywords: 'TF SD MICROSD 卡座'),
  PartModel('rj45', PartKind.connector, 16.0, 21.0, 13.0, 0xFFC3C8CE, keywords: 'RJ45 网口'),
  PartModel('dc_jack', PartKind.connector, 9.0, 14.0, 6.5, 0xFF1F2023, keywords: 'DC 电源座 DC-005'),
  PartModel('spring', PartKind.connector, 2.0, 1.5, 1.5, 0xFFD9B35A, keywords: '弹片 SPRING POGO 顶针'),
  // Switches, acoustics, relays, batteries
  PartModel('tact_switch', PartKind.electromech, 6.0, 6.0, 3.5, 0xFFC3C8CE, keywords: 'SW KEY 轻触 按键 TACT'),
  PartModel('side_switch', PartKind.electromech, 4.0, 3.5, 1.6, 0xFFE3D8BF, keywords: '侧按 SIDE KEY'),
  PartModel('slide_switch', PartKind.electromech, 6.7, 2.6, 1.5, 0xFF1F2023, keywords: '拨动 SLIDE 拨码 DIP'),
  PartModel('buzzer', PartKind.electromech, 9.0, 9.0, 4.0, 0xFF1F2023, keywords: 'BZ BUZ 蜂鸣器 BUZZER'),
  PartModel('mic', PartKind.electromech, 3.5, 2.65, 1.0, 0xFFC9CED4, keywords: 'MIC MK 麦克风 MEMS'),
  PartModel('relay', PartKind.electromech, 10.0, 6.0, 5.0, 0xFF1F2023, keywords: 'K RLY 继电器 RELAY'),
  PartModel('coin_cell', PartKind.electromech, 20.0, 20.0, 4.0, 0xFFC9CED4, keywords: 'BAT BT 电池 CR2032'),
  // Mechanical
  PartModel('shield', PartKind.mechanical, 10.0, 10.0, 1.0, 0xFFC9CED4, keywords: '屏蔽框 屏蔽罩 SHIELD'),
  PartModel('heatsink', PartKind.mechanical, 10.0, 10.0, 5.0, 0xFFB9BFC7, keywords: '散热片 HEATSINK'),
  PartModel('mount_hole', PartKind.mechanical, 3.0, 3.0, 0, 0xFFC0844A, keywords: 'MH H 孔 HOLE 螺丝'),
  PartModel('test_point', PartKind.testPoint, 1.2, 1.2, 0.05, 0xFFD9B35A, keywords: 'TP P 测试点 POINT PAD'),
  PartModel('fiducial', PartKind.fiducial, 1.0, 1.0, 0, 0xFFC0844A, keywords: 'MARK FID 光学点'),
  // Others
  PartModel('fuse', PartKind.other, 1.6, 0.8, 0.6, 0xFFE9E5DA, keywords: 'F FU 保险丝 FUSE'),
  PartModel('antenna', PartKind.other, 3.2, 1.6, 1.1, 0xFFEDEBE4, keywords: 'ANT E 天线 ANTENNA'),
  PartModel('generic', PartKind.other, 2.0, 1.2, 0.8, 0xFF8E959D, keywords: ''),
];

final Map<String, PartModel> _byId = {for (final m in partLibrary) m.id: m};

PartModel partModel(String id) => _byId[id] ?? _byId['generic']!;

bool isPartModel(String id) => _byId.containsKey(id);

bool _any(String text, List<String> words) => words.any(text.contains);

/// Picks the model for a part from its colour group, designator prefix and
/// footprint / description text (upper case).
String modelIdFor(PartKind kind, String prefix, String text, {double width = 0, double height = 0, bool exact = false}) {
  switch (kind) {
    case PartKind.resistor:
      if (prefix == 'RN' || prefix == 'RP' || _any(text, ['排阻', 'ARRAY'])) return 'res_array';
      if (prefix == 'RV' || _any(text, ['压敏', 'VARISTOR', 'ZNR', 'VDR'])) return 'varistor';
      if (prefix == 'NTC' || prefix == 'PTC' || prefix == 'RT' || _any(text, ['热敏', 'NTC', 'PTC'])) return 'thermistor';
      if (text.contains('MELF')) return 'melf';
      return 'chip_resistor';
    case PartKind.capacitor:
      if (prefix == 'EC' || prefix == 'CE' || _any(text, ['电解', 'ELEC', 'ALUM'])) return 'elcap';
      if (_any(text, ['聚合物', 'POLYMER', 'POSCAP'])) return 'polymer';
      if (prefix == 'TC' || _any(text, ['钽', 'TANT', 'TAJ'])) return 'tantalum';
      return 'mlcc';
    case PartKind.inductor:
      if (prefix == 'T' || _any(text, ['变压器', 'TRANSFORMER'])) return 'transformer';
      if (prefix == 'FB' || _any(text, ['磁珠', 'BEAD'])) return 'bead';
      if (_any(text, ['共模', 'CMC', 'COMMON MODE'])) return 'cm_choke';
      if (_any(text, ['绕线', '工字', 'CD54', 'CD32', 'SDR', 'WIREWOUND'])) return 'drum_inductor';
      if (exact && width <= 2.0) return 'chip_inductor';
      return 'power_inductor';
    case PartKind.diode:
      if (RegExp(r'DO-?214|SM[ABC]\b').hasMatch(text)) return 'diode_sma';
      if (_any(text, ['LL-34', 'LL34', 'MELF', '玻封'])) return 'diode_melf';
      return 'diode_sod';
    case PartKind.led:
      if (RegExp(r'PLCC|2835|3528|5050|3030|5730|RGB|WS2812').hasMatch(text)) return 'led_plcc';
      return 'led_chip';
    case PartKind.transistor:
      if (RegExp(r'SOT-?223').hasMatch(text)) return 'sot223';
      if (RegExp(r'SOT-?89').hasMatch(text)) return 'sot89';
      if (RegExp(r'TO-?263|D2PAK').hasMatch(text)) return 'd2pak';
      if (RegExp(r'TO-?252|DPAK').hasMatch(text)) return 'dpak';
      if (RegExp(r'PDFN|DFN5|POWERPAK|SO-?8FL|QFN').hasMatch(text)) return 'power_dfn';
      if (RegExp(r'SOT-?23-?[56]|SOT-?26|SOT-?363|SOT-?563|SC-?70-?6').hasMatch(text)) return 'sot23_6';
      return 'sot23';
    case PartKind.ic:
      if (_any(text, ['模块', 'MODULE', 'WIFI', 'ESP32', 'ESP8266'])) return 'module';
      if (_any(text, ['WLCSP', 'CSP'])) return 'wlcsp';
      if (_any(text, ['BGA', 'EMMC', 'DDR', 'UFS'])) return 'bga';
      if (RegExp(r'[LT]?QFP').hasMatch(text)) return 'qfp';
      if (RegExp(r'SOT-?23-?[56]|SOT-?26|SC-?70').hasMatch(text)) return 'sot23_6';
      if (RegExp(r'QFN|DFN|SON|LGA').hasMatch(text)) return 'qfn';
      if (RegExp(r'SOIC|SOP|SSOP|MSOP|ESOP').hasMatch(text)) return 'soic';
      return (width - height).abs() < 0.2 ? 'qfn' : 'soic';
    case PartKind.crystal:
      if (_any(text, ['有源', 'OSC', '振荡', 'TCXO'])) return 'oscillator';
      if (_any(text, ['49S', 'HC-49', 'HC49'])) return 'hc49';
      return 'crystal_smd';
    case PartKind.connector:
      if (_any(text, ['TYPE-C', 'TYPEC', 'USB-C', 'USBC'])) return 'usb_c';
      if (text.contains('MICRO') && text.contains('USB')) return 'micro_usb';
      if (_any(text, ['TF', 'MICROSD', 'SD卡', 'SD CARD'])) return 'sd_card';
      if (text.contains('SIM')) return 'sim';
      if (_any(text, ['USB', 'HDMI'])) return 'usb_a';
      if (_any(text, ['RJ45', '网口'])) return 'rj45';
      if (_any(text, ['FPC', 'FFC', '翻盖'])) return 'fpc';
      if (_any(text, ['BTB', '板对板', 'BOARD TO BOARD'])) return 'btb';
      if (_any(text, ['DC-0', '电源座', 'DC JACK'])) return 'dc_jack';
      if (_any(text, ['弹片', 'SPRING', 'POGO', '顶针'])) return 'spring';
      if (_any(text, ['HEADER', '排针', '排母', '2.54'])) return 'pin_header';
      return 'wire_to_board';
    case PartKind.electromech:
      if (_any(text, ['蜂鸣', 'BUZZ']) || prefix == 'BZ' || prefix == 'BUZ') return 'buzzer';
      if (_any(text, ['麦克', 'MIC']) || prefix == 'MIC' || prefix == 'MK') return 'mic';
      if (_any(text, ['继电器', 'RELAY']) || prefix == 'K' || prefix == 'RLY') return 'relay';
      if (_any(text, ['电池', 'BATT', 'CR20', 'CR12']) || prefix == 'BAT' || prefix == 'BT') return 'coin_cell';
      if (_any(text, ['拨动', 'SLIDE', '拨码', 'DIP'])) return 'slide_switch';
      if (_any(text, ['侧按', 'SIDE'])) return 'side_switch';
      return 'tact_switch';
    case PartKind.mechanical:
      if (_any(text, ['散热', 'HEATSINK'])) return 'heatsink';
      if (_any(text, ['屏蔽', 'SHIELD'])) return 'shield';
      return 'mount_hole';
    case PartKind.testPoint:
      return 'test_point';
    case PartKind.fiducial:
      return 'fiducial';
    case PartKind.other:
      if (prefix == 'F' || prefix == 'FU' || _any(text, ['保险丝', 'FUSE'])) return 'fuse';
      if (prefix == 'ANT' || _any(text, ['天线', 'ANTENNA'])) return 'antenna';
      return 'generic';
  }
}

/// A user's choice of model for parts the automatic recognition gets wrong.
/// [field] is `ref`, `partNo` or `footprint`; [value] is matched exactly.
class PartModelRule {
  const PartModelRule(this.field, this.value, this.model);

  final String field;
  final String value;
  final String model;

  Map<String, dynamic> toJson() => {'field': field, 'value': value, 'model': model};

  factory PartModelRule.fromJson(Map<String, dynamic> j) =>
      PartModelRule(j['field'] as String? ?? 'footprint', j['value'] as String? ?? '', j['model'] as String? ?? 'generic');
}

/// The model a rule assigns to a part, most specific rule first.
String? ruleModel(List<PartModelRule> rules, {required String ref, required String partNo, required String footprint}) {
  for (final (field, value) in [('ref', ref), ('partNo', partNo), ('footprint', footprint)]) {
    if (value.isEmpty) continue;
    for (final r in rules) {
      if (r.field == field && r.value == value && isPartModel(r.model)) return r.model;
    }
  }
  return null;
}
