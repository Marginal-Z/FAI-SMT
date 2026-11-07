import 'package:flutter_test/flutter_test.dart';
import 'package:smt_fai/core/params.dart';

String kinds(String s) => extractParams(s).map((p) => p.toString()).join(' ');

void main() {
  test('values with units and prefixes', () {
    double v(String s) => extractParams(s).single.value!;
    expect(v('10K'), 10000);
    expect(v('10kΩ'), 10000);
    expect(v('10Kohm'), 10000);
    expect(v('4K7'), 4700);
    expect(v('4R7'), 4.7);
    expect(v('0R'), 0);
    expect(v('2M2'), 2.2e6);
    expect(v('100nF'), closeTo(1e-7, 1e-20));
    expect(v('0.1uF'), closeTo(1e-7, 1e-20));
    expect(v('0.1µF'), closeTo(1e-7, 1e-20));
    expect(v('2.2uH'), closeTo(2.2e-6, 1e-18));
    expect(v('16V'), 16);
    expect(v('500mA'), 0.5);
    expect(v('24MHz'), 24e6);
    expect(v('1/16W'), 0.0625);
    expect(v('±1%'), 1);
    expect(v('10ppm'), 10);
  });

  test('a whole description', () {
    expect(kinds('贴片电容 100nF 16V X7R 0402 ±10%'), 'capacitance:1e-7 voltage:16.0 dielectric:X7R size:0402 tolerance:10.0');
    expect(kinds('RES SMD 10K OHM 1% 1/16W 0402'), 'resistance:10000.0 tolerance:1.0 power:0.0625 size:0402');
    expect(kinds('AO3400 SOT-23'), 'package:SOT-23');
    expect(kinds('STM32F103C8T6 LQFP48'), 'package:LQFP-48');
  });

  test('numerically equal writings are the same', () {
    expect(compareParams('贴片电阻 10K ±1% 0402', 'Chip resistor 10kΩ 1% 0402').verdict, ParamVerdict.same);
    expect(compareParams('MLCC 0.1uF 16V X7R 0402', '贴片电容 100nF 16V X7R 0402').verdict, ParamVerdict.same);
    expect(compareParams('C0G 22pF', 'NPO 22pF').verdict, ParamVerdict.same);
    expect(compareParams('SOT23', 'SOT-23').verdict, ParamVerdict.same);
  });

  test('different values conflict; missing ones are incomplete', () {
    final c = compareParams('贴片电容 10uF 6.3V X5R 0603', '贴片电容 10uF 10V X5R 0603');
    expect(c.verdict, ParamVerdict.conflict);
    expect(c.conflicts.single.$1.text, '6.3V');
    expect(c.conflicts.single.$2.text, '10V');
    expect(compareParams('10K 0402', '10K 0603').verdict, ParamVerdict.conflict);
    expect(compareParams('10K 0402', '10K 1% 0402').verdict, ParamVerdict.incomplete);
  });

  test('part numbers and plain numbers are not parameters', () {
    expect(extractParams('K1102-1020K0-001A'), isEmpty);
    expect(extractParams('GRM155R71C104KA88D'), isEmpty);
    expect(extractParams('W25Q64JV'), isEmpty);
  });
}
