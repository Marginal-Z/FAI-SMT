/// Rules, CAD template and About dialogs.
library;

import 'package:flutter/widgets.dart';
import 'icons.dart';

import '../app_state.dart';
import '../core/parsers.dart';
import '../core/settings.dart';
import '../l10n/strings.dart';
import 'theme.dart';
import 'widgets.dart';

const appVersion = '1.0.0';

List<String> _lines(String text) =>
    text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

Future<void> showRulesDialog(BuildContext context, AppState state, int initialTab) {
  final s = Strings.of(context);
  return showAppDialog(context, title: s.t('rules_title'), width: 620, body: (ctx) => _RulesBody(state: state, initialTab: initialTab));
}

class _RulesBody extends StatefulWidget {
  const _RulesBody({required this.state, required this.initialTab});

  final AppState state;
  final int initialTab;

  @override
  State<_RulesBody> createState() => _RulesBodyState();
}

class _RulesBodyState extends State<_RulesBody> {
  late int _tab = widget.initialTab;
  late final _keywords = TextEditingController();
  late final _prefixes = TextEditingController();
  late final _ignore = TextEditingController();
  late final _subs = TextEditingController();
  late final _program = TextEditingController();
  late bool _noRefs;
  late bool _qty;

  @override
  void initState() {
    super.initState();
    _fill(widget.state.settings.rules);
  }

  void _fill(CheckRules r) {
    _keywords.text = r.excludeKeywords.join('\n');
    _prefixes.text = r.excludePrefixes.join('\n');
    _ignore.text = r.ignoreRefPatterns.join('\n');
    _subs.text = r.substitutes.entries.map((e) => '${e.key}=${e.value.join(',')}').join('\n');
    _program.text = r.programKeywords.join('\n');
    _noRefs = r.excludeNoRefs;
    _qty = r.checkQty;
  }

  @override
  void dispose() {
    for (final c in [_keywords, _prefixes, _ignore, _subs, _program]) {
      c.dispose();
    }
    super.dispose();
  }

  CheckRules _collect() {
    final subs = <String, List<String>>{};
    for (final line in _lines(_subs.text)) {
      final i = line.indexOf('=');
      if (i <= 0) continue;
      final main = line.substring(0, i).trim().toUpperCase();
      final alts = line.substring(i + 1).split(RegExp(r'[,，;；\s]+')).map((e) => e.trim().toUpperCase()).where((e) => e.isNotEmpty).toList();
      if (alts.isNotEmpty) subs.putIfAbsent(main, () => []).addAll(alts);
    }
    return CheckRules(
      excludeKeywords: _lines(_keywords.text),
      excludePrefixes: _lines(_prefixes.text),
      ignoreRefPatterns: _lines(_ignore.text),
      substitutes: subs,
      programKeywords: _lines(_program.text),
      excludeNoRefs: _noRefs,
      checkQty: _qty,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    Widget label(String t) => Padding(padding: const EdgeInsets.only(bottom: 6, top: 4), child: Text(t, style: TextStyle(color: c.textDim, fontSize: 12.5)));
    final pages = [
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        label(s.t('rules_keywords')),
        TextInput(controller: _keywords, maxLines: 7),
        const SizedBox(height: 10),
        label(s.t('rules_prefixes')),
        TextInput(controller: _prefixes, maxLines: 4, mono: true),
        const SizedBox(height: 10),
        label(s.t('rules_program')),
        TextInput(controller: _program, maxLines: 3),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        label(s.t('rules_subs')),
        TextInput(controller: _subs, maxLines: 12, mono: true, hint: 'K1101-AAAA=K1101-BBBB,K1101-CCCC'),
        const SizedBox(height: 8),
        Text(s.t('rules_subs_note'), style: TextStyle(color: c.textFaint, fontSize: 12)),
      ]),
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CheckBox(value: _noRefs, label: s.t('rules_exclude_norefs'), onChanged: (v) => setState(() => _noRefs = v)),
        CheckBox(value: _qty, label: s.t('rules_check_qty'), onChanged: (v) => setState(() => _qty = v)),
        const SizedBox(height: 10),
        label(s.t('rules_ignore_refs')),
        TextInput(controller: _ignore, maxLines: 5, mono: true),
      ]),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 34,
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TabItem(label: s.t('btn_exclusion'), icon: Ic.prohibit, active: _tab == 0, dense: true, onTap: () => setState(() => _tab = 0)),
            TabItem(label: s.t('btn_substitutes'), icon: Ic.arrowsLeftRight, active: _tab == 1, dense: true, onTap: () => setState(() => _tab = 1)),
            TabItem(label: s.t('btn_general'), icon: Ic.gear, active: _tab == 2, dense: true, onTap: () => setState(() => _tab = 2)),
          ]),
        ),
        Flexible(
          child: SingleChildScrollView(padding: const EdgeInsets.all(14), child: pages[_tab]),
        ),
        HDivider(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            FlatButton(label: s.t('rules_reset'), icon: Ic.arrowCounterClockwise, onTap: () => setState(() => _fill(CheckRules()))),
            const Spacer(),
            FlatButton(label: s.t('dlg_cancel'), onTap: () => Navigator.of(context).pop()),
            const SizedBox(width: 8),
            FlatButton(
              label: s.t('dlg_save'),
              primary: true,
              onTap: () {
                widget.state.updateRules(_collect());
                Navigator.of(context).pop();
              },
            ),
          ]),
        ),
      ],
    );
  }
}

Future<void> showCadTemplateDialog(BuildContext context, AppState state) {
  final s = Strings.of(context);
  return showAppDialog(context, title: s.t('cad_title'), width: 760, body: (ctx) => _CadTemplateBody(state: state));
}

class _CadTemplateBody extends StatefulWidget {
  const _CadTemplateBody({required this.state});

  final AppState state;

  @override
  State<_CadTemplateBody> createState() => _CadTemplateBodyState();
}

class _CadTemplateBodyState extends State<_CadTemplateBody> {
  late List<CadField> _order;
  late Set<CadField> _on;
  late Map<CadField, TextEditingController> _headers;
  late CadFormat _format;
  late String _delim;
  late bool _writeHeader;
  late String _encoding;
  late int _decimals;
  late CoordUnit _unit;
  late bool _includeUnmatched;
  late bool _sideFromStation;
  final _ext = TextEditingController();
  final _top = TextEditingController();
  final _bottom = TextEditingController();
  int? _selected;

  @override
  void initState() {
    super.initState();
    final t = widget.state.settings.cad;
    _order = [...t.fields, ...CadField.values.where((f) => !t.fields.contains(f))];
    _on = t.fields.toSet();
    _headers = {for (final f in CadField.values) f: TextEditingController(text: t.headerOf(f))};
    for (final h in _headers.values) {
      h.addListener(() => setState(() {}));
    }
    _format = t.format;
    _delim = t.delimiter;
    _writeHeader = t.writeHeader;
    _encoding = t.encoding;
    _decimals = t.decimals;
    _unit = t.unit == CoordUnit.auto ? CoordUnit.mm : t.unit;
    _includeUnmatched = t.includeUnmatched;
    _sideFromStation = t.sideFromStation;
    _ext.text = t.extension;
    _top.text = t.topText;
    _bottom.text = t.bottomText;
    for (final c in [_ext, _top, _bottom]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [..._headers.values, _ext, _top, _bottom]) {
      c.dispose();
    }
    super.dispose();
  }

  CadTemplate _collect() => CadTemplate(
        fields: _order.where(_on.contains).toList(),
        headers: {
          for (final e in _headers.entries)
            if (e.value.text.trim() != CadTemplate.defaultHeaders[e.key]) e.key.name: e.value.text.trim()
        },
        format: _format,
        delimiter: _delim,
        writeHeader: _writeHeader,
        extension: _ext.text.trim().replaceAll('.', '').isEmpty ? 'csv' : _ext.text.trim().replaceAll('.', ''),
        encoding: _encoding,
        decimals: _decimals,
        unit: _unit,
        topText: _top.text.trim(),
        bottomText: _bottom.text.trim(),
        includeUnmatched: _includeUnmatched,
        sideFromStation: _sideFromStation,
      );

  void _move(int d) {
    final i = _selected;
    if (i == null) return;
    final j = i + d;
    if (j < 0 || j >= _order.length) return;
    setState(() {
      final f = _order.removeAt(i);
      _order.insert(j, f);
      _selected = j;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final t = _collect();
    final previewSep = t.format == CadFormat.xlsx ? '  |  ' : t.delimiter;
    final preview = [
      if (t.writeHeader) t.fields.map(t.headerOf).join(previewSep),
      t.fields.map((f) => switch (f) {
            CadField.ref => 'U5',
            CadField.x => 12.5.toStringAsFixed(t.decimals),
            CadField.y => 30.25.toStringAsFixed(t.decimals),
            CadField.rotation => '90',
            CadField.side => t.topText,
            CadField.partNo => 'K1101-1C302X-001A',
            CadField.description => 'IC C302XS BGA128',
            CadField.value => 'C302XS',
            CadField.footprint => 'BGA128',
            CadField.slot => '1-05',
            CadField.qty => '1',
            CadField.loadedPartNo => 'K1101-1C302X-001A',
          }).join(previewSep),
    ].join('\n').replaceAll('\t', '    ');

    Widget label(String text) => SizedBox(width: 92, child: Text(text, style: TextStyle(color: c.textDim, fontSize: 12.5)));
    Widget row(String text, Widget child) => Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [label(text), Flexible(child: child)]));

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Field list
                SizedBox(
                  width: 330,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text(s.t('cad_fields'), style: TextStyle(color: c.textDim, fontSize: 12.5))),
                      IconBtn(icon: Ic.caretUp, onTap: _selected == null ? null : () => _move(-1), tooltip: s.t('move_up')),
                      IconBtn(icon: Ic.caretDown, onTap: _selected == null ? null : () => _move(1), tooltip: s.t('move_down')),
                    ]),
                    const SizedBox(height: 6),
                    Container(
                      decoration: BoxDecoration(border: Border.all(color: c.borderStrong), borderRadius: BorderRadius.circular(3)),
                      child: Column(children: [
                        for (var i = 0; i < _order.length; i++)
                          Hoverable(
                            onTap: () => setState(() => _selected = i),
                            cursor: SystemMouseCursors.basic,
                            builder: (context, hover, _) => Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              color: _selected == i ? c.selected : hover ? c.hover : null,
                              child: Row(children: [
                                SizedBox(
                                  width: 120,
                                  child: CheckBox(
                                    value: _on.contains(_order[i]),
                                    label: s.t('field_${_order[i].name}'),
                                    onChanged: (v) => setState(() => v ? _on.add(_order[i]) : _on.remove(_order[i])),
                                  ),
                                ),
                                Expanded(child: TextInput(controller: _headers[_order[i]]!, mono: true)),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text(s.t('cad_header_text'), style: TextStyle(color: c.textFaint, fontSize: 11.5)),
                  ]),
                ),
                const SizedBox(width: 18),
                // Format options
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    row(s.t('cad_format'), Segmented<CadFormat>(value: _format, options: [(CadFormat.xlsx, s.t('fmt_xlsx')), (CadFormat.text, s.t('fmt_text'))], onChanged: (v) => setState(() => _format = v))),
                    if (_format == CadFormat.text) row(s.t('cad_delim'), Segmented<String>(value: _delim, options: [(',', s.t('delim_comma')), ('\t', s.t('delim_tab')), (' ', s.t('delim_space')), (';', s.t('delim_semicolon'))], onChanged: (v) => setState(() => _delim = v))),
                    if (_format == CadFormat.text) row(s.t('cad_ext'), TextInput(controller: _ext, width: 90, mono: true)),
                    if (_format == CadFormat.text) row(s.t('cad_encoding'), Segmented<String>(value: _encoding, options: const [('utf8', 'UTF-8'), ('utf8bom', 'UTF-8 BOM'), ('gbk', 'GBK')], onChanged: (v) => setState(() => _encoding = v))),
                    row(s.t('cad_unit'), Segmented<CoordUnit>(value: _unit, options: const [(CoordUnit.mm, 'mm'), (CoordUnit.mil, 'mil'), (CoordUnit.inch, 'inch')], onChanged: (v) => setState(() => _unit = v))),
                    row(s.t('cad_decimals'), Segmented<int>(value: _decimals, options: const [(0, '0'), (1, '1'), (2, '2'), (3, '3'), (4, '4')], onChanged: (v) => setState(() => _decimals = v))),
                    row(s.t('cad_top'), Row(children: [
                      TextInput(controller: _top, width: 80, mono: true),
                      const SizedBox(width: 12),
                      Text(s.t('cad_bottom'), style: TextStyle(color: c.textDim, fontSize: 12.5)),
                      const SizedBox(width: 8),
                      TextInput(controller: _bottom, width: 80, mono: true),
                    ])),
                    const SizedBox(height: 6),
                    CheckBox(value: _writeHeader, label: s.t('cad_write_header'), onChanged: (v) => setState(() => _writeHeader = v)),
                    CheckBox(value: _sideFromStation, label: s.t('cad_side_from_station'), onChanged: (v) => setState(() => _sideFromStation = v)),
                    CheckBox(value: _includeUnmatched, label: s.t('cad_include_unmatched'), onChanged: (v) => setState(() => _includeUnmatched = v)),
                    const SizedBox(height: 10),
                    Text(s.t('cad_preview'), style: TextStyle(color: c.textDim, fontSize: 12.5)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: c.input, border: Border.all(color: c.border), borderRadius: BorderRadius.circular(3)),
                      child: Text(preview, style: TextStyle(fontFamily: monoFontFamily, fontSize: 12, color: c.text)),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
        HDivider(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            FlatButton(
              label: s.t('rules_reset'),
              icon: Ic.arrowCounterClockwise,
              onTap: () {
                widget.state.updateCadTemplate(CadTemplate());
                Navigator.of(context).pop();
              },
            ),
            const Spacer(),
            FlatButton(label: s.t('dlg_cancel'), onTap: () => Navigator.of(context).pop()),
            const SizedBox(width: 8),
            FlatButton(
              label: s.t('dlg_save'),
              primary: true,
              onTap: () {
                widget.state.updateCadTemplate(_collect());
                Navigator.of(context).pop();
              },
            ),
          ]),
        ),
      ],
    );
  }
}

Future<void> showAboutDialog(BuildContext context, AppState state) {
  final s = Strings.of(context);
  return showAppDialog(context, title: s.t('btn_about'), width: 480, body: (ctx) {
    final c = AppTheme.of(context);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('SMT-FAI', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: c.text)),
          Text(s.t('about_version', {'v': appVersion}), style: TextStyle(color: c.textDim)),
          const SizedBox(height: 12),
          Text(s.t('about_text'), style: TextStyle(color: c.text)),
          const SizedBox(height: 12),
          Text(s.t('about_config'), style: TextStyle(color: c.textDim, fontSize: 12)),
          Text('${state.settingsDir}/settings.json', style: TextStyle(fontFamily: monoFontFamily, fontSize: 12, color: c.text)),
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerRight, child: FlatButton(label: s.t('dlg_close'), primary: true, onTap: () => Navigator.of(ctx).pop())),
        ],
      ),
    );
  });
}
