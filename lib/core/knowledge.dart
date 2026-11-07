/// General electronics-manufacturing knowledge used as hints when reading a
/// BOM: component makers, designator prefixes, and the words and units that
/// name each kind of item in several languages. Nothing here belongs to a
/// particular company, product or file.
library;

/// Component, connector and module makers, lower case, as commonly written.
const makers = {
  'murata', 'samsung', 'samsung electro-mechanics', 'semco', 'tdk', 'taiyo yuden', 'kyocera', 'avx', 'kyocera avx', 'kemet', 'vishay', 'yageo',
  'rohm', 'panasonic', 'koa', 'bourns', 'walsin', 'uniroyal', 'royalohm', 'fenghua', 'ffh', 'eyang', 'three-circle', 'cctc', 'sunlord', 'microgate',
  'chilisin', 'cyntec', 'coilcraft', 'wurth', 'würth', 'wurth elektronik', 'abracon', 'epson', 'ndk', 'txc', 'kds', 'siward', 'hosonic', 'yxc',
  'texas instruments', 'ti', 'analog devices', 'adi', 'maxim', 'stmicroelectronics', 'st', 'nxp', 'infineon', 'onsemi', 'on semi', 'on semiconductor',
  'microchip', 'atmel', 'renesas', 'toshiba', 'diodes', 'diodes inc', 'diodes incorporated', 'nexperia', 'littelfuse', 'semtech', 'richtek',
  'monolithic power', 'mps', 'silergy', 'sgmicro', 'sg micro', 'awinic', 'will semi', 'willsemi', 'goodix', 'gigadevice', 'winbond', 'macronix',
  'micron', 'sk hynix', 'hynix', 'kioxia', 'sandisk', 'nanya', 'longsys', 'realtek', 'mediatek', 'qualcomm', 'broadcom', 'espressif', 'nordic',
  'silicon labs', 'silabs', 'amlogic', 'rockchip', 'allwinner', 'hisilicon', 'ingenic', 'aos', 'alpha & omega', 'alpha&omega', 'vbsemi',
  'lrc', 'leshan', 'changjiang', 'jcet', 'cj', 'mccsemi', 'mcc', 'prisemi', 'brightking', 'ut', 'unisonic', 'everlight', 'kingbright', 'lite-on',
  'liteon', 'osram', 'nichia', 'cree', 'foshan nationstar', 'nationstar', 'molex', 'te connectivity', 'te', 'amphenol', 'jst', 'hirose', 'jae',
  'samtec', 'harwin', 'kinghelm', 'hrs', 'xkb', 'xunpu', 'boom', 'korean hroparts', 'hroparts', 'cui', 'omron', 'alps', 'c&k', 'e-switch',
  'nichicon', 'rubycon', 'chemi-con', 'nippon chemi-con', 'elna', 'lelon', 'capxon', 'aishi', 'jianghai',
};

/// Item kinds a BOM line can be.
enum ItemKind {
  resistor, capacitor, inductor, ferrite, diode, led, transistor, ic, crystal, connector, switchKind, relay, fuse, transformer, sensor,
  module, speaker, battery, testPoint, pcb, mechanical, packaging, consumable, unknown;

  /// Electronic parts placed at a designator.
  bool get placed => index <= ItemKind.testPoint.index;
}

/// Designator prefixes, longest first so `LED` wins over `L`.
const designatorKinds = <String, ItemKind>{
  'LED': ItemKind.led, 'RN': ItemKind.resistor, 'RP': ItemKind.resistor, 'VR': ItemKind.resistor, 'NTC': ItemKind.resistor, 'PTC': ItemKind.fuse,
  'FB': ItemKind.ferrite, 'BEAD': ItemKind.ferrite, 'TVS': ItemKind.diode, 'ZD': ItemKind.diode, 'IC': ItemKind.ic, 'CN': ItemKind.connector,
  'CON': ItemKind.connector, 'USB': ItemKind.connector, 'SW': ItemKind.switchKind, 'KEY': ItemKind.switchKind, 'TP': ItemKind.testPoint,
  'MK': ItemKind.sensor, 'MIC': ItemKind.sensor, 'BT': ItemKind.battery, 'BAT': ItemKind.battery, 'SPK': ItemKind.speaker, 'BZ': ItemKind.speaker,
  'XTAL': ItemKind.crystal, 'OSC': ItemKind.crystal, 'ANT': ItemKind.module, 'MOD': ItemKind.module, 'SH': ItemKind.mechanical,
  'R': ItemKind.resistor, 'C': ItemKind.capacitor, 'E': ItemKind.capacitor, 'L': ItemKind.inductor, 'D': ItemKind.diode, 'Q': ItemKind.transistor,
  'T': ItemKind.transformer, 'U': ItemKind.ic, 'N': ItemKind.ic, 'Y': ItemKind.crystal, 'X': ItemKind.crystal, 'J': ItemKind.connector,
  'P': ItemKind.connector, 'K': ItemKind.relay, 'F': ItemKind.fuse, 'S': ItemKind.switchKind, 'B': ItemKind.speaker, 'M': ItemKind.module,
};

/// Words naming an item kind (lower case; matched as substrings, so the
/// Chinese and Thai entries need no word breaks).
const kindWords = <ItemKind, List<String>>{
  ItemKind.resistor: ['resistor', 'res', 'resistance', 'widerstand', 'résistance', 'resistencia', '电阻', '排阻', '热敏', 'ตัวต้านทาน', '抵抗', 'thermistor'],
  ItemKind.capacitor: ['capacitor', 'cap', 'mlcc', 'kondensator', 'condensateur', 'condensador', '电容', '钽电容', '电解', 'ตัวเก็บประจุ', 'คาปาซิเตอร์', 'コンデンサ'],
  ItemKind.inductor: ['inductor', 'choke', 'coil', 'drossel', 'spule', 'inductance', 'bobine', '电感', '扼流', 'ตัวเหนี่ยวนำ', 'インダクタ'],
  ItemKind.ferrite: ['ferrite', 'bead', '磁珠', 'ferrit'],
  ItemKind.diode: ['diode', 'rectifier', 'schottky', 'zener', 'tvs', 'esd', '二极管', '稳压管', 'ไดโอด', 'ダイオード'],
  ItemKind.led: ['led', '发光二极管', '发光', '灯珠', 'แอลอีดี'],
  ItemKind.transistor: ['transistor', 'mosfet', 'mos管', 'mos', 'bjt', '三极管', '晶体管', '场效应', 'ทรานซิสเตอร์', 'トランジスタ'],
  ItemKind.ic: ['ic', 'integrated circuit', 'mcu', 'microcontroller', 'regulator', 'ldo', 'dc-dc', 'op amp', 'opamp', 'flash', 'eeprom', 'dram', 'ddr', 'emmc', 'soc', 'driver', 'controller', 'chip', '芯片', '集成电路', '主控', 'ไอซี'],
  ItemKind.crystal: ['crystal', 'oscillator', 'resonator', 'quarz', 'quartz', '晶振', '晶体', 'คริสตัล', '水晶'],
  ItemKind.connector: ['connector', 'header', 'socket', 'receptacle', 'plug', 'jack', 'terminal', 'fpc', 'ffc', 'usb', 'hdmi', 'steckverbinder', 'buchse', 'stecker', '连接器', '插座', '排针', '排母', '端子', '座子', 'คอนเนคเตอร์', 'コネクタ'],
  ItemKind.switchKind: ['switch', 'button', 'tact', 'taster', 'schalter', '开关', '按键', 'สวิตช์'],
  ItemKind.relay: ['relay', 'relais', '继电器', 'รีเลย์'],
  ItemKind.fuse: ['fuse', 'polyfuse', 'ptc', 'sicherung', '保险丝', '自恢复', 'ฟิวส์'],
  ItemKind.transformer: ['transformer', 'trafo', 'übertrager', '变压器', 'หม้อแปลง'],
  ItemKind.sensor: ['sensor', 'microphone', 'mic', 'thermistor', '传感器', '麦克风', 'เซนเซอร์'],
  ItemKind.module: ['module', 'antenna', 'modul', '模组', '模块', '天线', 'โมดูล'],
  ItemKind.speaker: ['speaker', 'buzzer', 'lautsprecher', 'summer', '喇叭', '蜂鸣器', 'ลำโพง'],
  ItemKind.battery: ['battery', 'coin cell', 'batterie', 'akku', '电池', 'แบตเตอรี่'],
  ItemKind.testPoint: ['test point', 'testpoint', 'testpunkt', '测试点'],
  ItemKind.pcb: ['pcb', 'pcba', 'printed circuit', 'leiterplatte', 'circuit board', 'main board', 'mainboard', '光板', '线路板', '主板', '电路板', 'แผงวงจร'],
  ItemKind.mechanical: ['shield', 'screw', 'nut', 'washer', 'bracket', 'housing', 'enclosure', 'heatsink', 'heat sink', 'standoff', 'spacer', 'gasket', 'foam', 'abschirmung', 'schraube', 'gehäuse', '屏蔽', '螺丝', '螺钉', '螺母', '支架', '外壳', '散热', '铜柱', '泡棉', '胶垫', 'ฝาครอบ', 'สกรู'],
  ItemKind.packaging: ['bag', 'box', 'carton', 'tray', 'reel', 'label', 'manual', 'esd bag', 'beutel', 'karton', 'etikett', 'verpackung', '袋', '包装', '纸箱', '彩盒', '标签', '说明书', '吸塑', 'ถุง', 'กล่อง', 'ฉลาก'],
  ItemKind.consumable: ['solder', 'paste', 'flux', 'glue', 'adhesive', 'tape', 'lot', 'lötpaste', 'kleber', '锡膏', '锡条', '锡线', '助焊', '胶水', '红胶', '胶带', 'ตะกั่ว'],
};

/// Value units that alone tell the kind of a passive part.
final unitKinds = <RegExp, ItemKind>{
  RegExp(r'\d(?:\.\d+)?\s?(?:[kmgr]?Ω|[km]?ohm|r\d|k\d|m\d)\b|\b\d+(?:\.\d+)?[kmr]\b', caseSensitive: false): ItemKind.resistor,
  RegExp(r'\d(?:\.\d+)?\s?[pnuμµm]f\b', caseSensitive: false): ItemKind.capacitor,
  RegExp(r'\d(?:\.\d+)?\s?[pnuμµm]h\b', caseSensitive: false): ItemKind.inductor,
  RegExp(r'\d(?:\.\d+)?\s?[km]?hz\b', caseSensitive: false): ItemKind.crystal,
};

/// Words marking a line or designator as not placed (DNP / NC / not fitted).
const dnpWords = ['dnp', 'dnf', 'dni', 'npop', 'no-pop', 'no pop', 'not fitted', 'not placed', 'not populated', 'nf', 'nc', 'n/c', 'nm', 'unpopulated', 'nicht bestückt', '不贴', '不上件', '空贴', '不焊', '预留', 'ไม่ติดตั้ง'];
