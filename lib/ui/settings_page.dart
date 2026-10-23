/// Settings module: appearance, software update, about.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/footprints.dart';
import '../core/settings.dart';
import '../core/updater.dart';
import '../l10n/strings.dart';
import '../version.dart';
import 'board_view.dart';
import 'glyphs.dart';
import 'rules_page.dart';
import 'theme.dart';
import 'ui_scale.dart';
import 'widgets.dart';

/// Full-screen settings, opened from the title bar gear and closed with Back.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final s = Strings.of(context);
    final sections = [
      (SettingsSection.appearance, Glyph.appearance, s.t('set_appearance')),
      (SettingsSection.board, Glyph.palette, s.t('set_board_colors')),
      (SettingsSection.rules, Glyph.rules, s.t('set_rules')),
      (SettingsSection.update, Glyph.update, s.t('set_update')),
      (SettingsSection.about, Glyph.info, s.t('set_about')),
    ];
    final narrow = MediaQuery.sizeOf(context).width < 900;

    final nav = narrow
        ? Container(
            height: 48,
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final (sec, glyph, label) in sections)
                    _NavItem(glyph: glyph, label: label, active: state.settingsSection == sec, onTap: () => state.setSettingsSection(sec)),
                ],
              ),
            ),
          )
        : Container(
            width: 232,
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
            decoration: BoxDecoration(
              color: c.panel,
              border: Border(right: BorderSide(color: c.border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (sec, glyph, label) in sections)
                  _NavItem(glyph: glyph, label: label, active: state.settingsSection == sec, onTap: () => state.setSettingsSection(sec)),
              ],
            ),
          );

    final content = switch (state.settingsSection) {
      SettingsSection.rules => RulesPage(state: state),
      SettingsSection.appearance => _Section(
        title: s.t('set_appearance'),
        child: _Appearance(state: state),
      ),
      SettingsSection.board => _Section(
        title: s.t('set_board_colors'),
        child: _BoardColors(state: state),
      ),
      SettingsSection.update => _Section(
        title: s.t('set_update'),
        child: _UpdatePanel(state: state),
      ),
      SettingsSection.about => _Section(
        title: s.t('set_about'),
        child: _About(state: state),
      ),
    };

    return Container(
      color: c.window,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: m.menuBar + 10,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: c.chrome,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Hoverable(
                  onTap: state.closeSettings,
                  builder: (context, hover, _) => Container(
                    height: m.iconButton + 4,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(color: hover ? c.hover : null, borderRadius: BorderRadius.circular(6)),
                    child: Row(
                      children: [
                        GlyphIcon(Glyph.back, size: 18, color: c.text),
                        const SizedBox(width: 6),
                        Text(s.t('btn_back'), style: TextStyle(fontSize: 13, color: c.text)),
                      ],
                    ),
                  ),
                ),
                Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 12), color: c.borderStrong),
                GlyphIcon(Glyph.settings, size: 18, color: c.accent),
                const SizedBox(width: 8),
                Text(
                  s.t('mod_settings'),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text),
                ),
                const Spacer(),
                Text('SMT-FAI ${s.t('about_version', {'v': appVersion})}', style: TextStyle(fontSize: 12, color: c.textFaint)),
                const SizedBox(width: 6),
              ],
            ),
          ),
          Expanded(
            child: narrow
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      nav,
                      Expanded(child: content),
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      nav,
                      Expanded(child: content),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.glyph, required this.label, required this.active, required this.onTap});

  final Glyph glyph;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
      child: Hoverable(
        onTap: onTap,
        builder: (context, hover, _) => Container(
          height: m.touch ? 44 : 38,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active
                ? c.accent.withValues(alpha: c.dark ? 0.16 : 0.09)
                : hover
                ? c.hover
                : null,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GlyphIcon(glyph, size: 18, filled: active, color: active ? c.accent : c.textDim),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(fontSize: 13, color: active ? c.accent : c.text, fontWeight: active ? FontWeight.w700 : FontWeight.w400),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scrollable content column with one titled card.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text),
              ),
              const SizedBox(height: 14),
              SurfaceCard(padding: const EdgeInsets.fromLTRB(22, 18, 22, 20), child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _Appearance extends StatelessWidget {
  const _Appearance({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    Widget row(String label, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(fontSize: 13, color: c.textDim)),
          ),
          Flexible(
            child: Align(alignment: Alignment.centerLeft, child: control),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row(
          s.t('set_theme'),
          Segmented<ThemePref>(
            value: state.theme,
            options: [(ThemePref.light, s.t('btn_light')), (ThemePref.dark, s.t('btn_dark')), (ThemePref.system, s.t('btn_system'))],
            onChanged: state.setTheme,
          ),
        ),
        row(
          s.t('set_ui_scale'),
          DropdownSelect<double>(
            value: state.settings.uiScale,
            width: 180,
            options: [
              (0, s.t('ui_scale_auto')),
              for (final v in uiScaleSteps) (v, '${(v * 100).round()}%'),
            ],
            onChanged: state.setUiScale,
          ),
        ),
        row(
          s.t('set_language'),
          Segmented<String>(
            value: state.language,
            options: [for (final l in supportedLanguages) (l, languageNames[l]!)],
            onChanged: state.setLanguage,
          ),
        ),
      ],
    );
  }
}

class _About extends StatelessWidget {
  const _About({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Image.asset('assets/icon/app_icon_64.png', width: 48, height: 48),
            const SizedBox(width: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SMT-FAI',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.text),
                ),
                Text(s.t('about_version', {'v': appVersion}), style: TextStyle(fontSize: 12.5, color: c.textDim)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(s.t('about_text'), style: TextStyle(fontSize: 12.5, color: c.textDim, height: 1.5)),
        const SizedBox(height: 12),
        Text(s.t('about_config'), style: TextStyle(fontSize: 12, color: c.textFaint)),
        Text(
          '${state.settingsDir}${Platform.pathSeparator}settings.json',
          style: TextStyle(fontFamily: monoFontFamily, fontSize: 12, color: c.textDim),
        ),
        const SizedBox(height: 12),
        Text(s.t('set_licenses'), style: TextStyle(fontSize: 12, color: c.textFaint)),
      ],
    );
  }
}

class _UpdatePanel extends StatelessWidget {
  const _UpdatePanel({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final release = state.latestRelease;
    final status = state.updateStatus;
    final busy = status == UpdateStatus.checking || status == UpdateStatus.downloading || status == UpdateStatus.installing;

    final (Color dot, String line) = switch (status) {
      UpdateStatus.idle => (c.textFaint, s.t('set_current', {'v': appVersion})),
      UpdateStatus.checking => (c.accent, s.t('upd_checking')),
      UpdateStatus.upToDate => (c.pass, s.t('upd_latest')),
      UpdateStatus.available => (c.substitute, s.t('upd_available', {'v': release?.version ?? ''})),
      UpdateStatus.downloading => (c.accent, s.t('upd_downloading', {'p': (state.updateProgress * 100).toStringAsFixed(0)})),
      UpdateStatus.installing => (c.accent, s.t('upd_installing')),
      UpdateStatus.failed => (c.ng, s.t(state.updateError)),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                line,
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text),
              ),
            ),
            FlatButton(label: s.t('btn_check_update'), compact: true, onTap: busy ? null : () => state.checkForUpdates()),
            if (state.updateAvailable) ...[
              const SizedBox(width: 8),
              FlatButton(label: s.t('btn_install_update'), compact: true, primary: true, onTap: busy ? null : state.downloadAndInstall),
            ],
          ],
        ),
        if (status == UpdateStatus.downloading) ...[
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 6,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (state.updateProgress > 0)
                    Expanded(
                      flex: (state.updateProgress * 1000).round().clamp(1, 1000),
                      child: ColoredBox(color: c.accent),
                    ),
                  if (state.updateProgress < 1)
                    Expanded(
                      flex: (1000 - state.updateProgress * 1000).round().clamp(1, 1000),
                      child: ColoredBox(color: c.border),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (Platform.isAndroid && state.updateAvailable) ...[
          const SizedBox(height: 8),
          Text(s.t('upd_android_hint'), style: TextStyle(fontSize: 12, color: c.textFaint)),
        ],
        if (release != null && state.updateAvailable && release.notes.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(
            s.t('upd_notes'),
            style: TextStyle(fontSize: 12, color: c.textDim, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.panelAlt,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border),
            ),
            child: SingleChildScrollView(
              child: Text(release.notes.trim(), style: TextStyle(fontSize: 12.5, color: c.text, height: 1.5)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        CheckBox(value: state.settings.autoUpdate, label: s.t('set_auto_update'), onChanged: state.setAutoUpdate),
        const SizedBox(height: 4),
        Text(s.t('set_update_source', {'repo': updateRepo}), style: TextStyle(fontSize: 12, color: c.textFaint)),
      ],
    );
  }
}

const _kindLabels = [
  (PartKind.resistor, 'type_resistor'),
  (PartKind.capacitor, 'type_capacitor'),
  (PartKind.inductor, 'type_inductor'),
  (PartKind.diode, 'type_diode'),
  (PartKind.led, 'type_led'),
  (PartKind.transistor, 'type_transistor'),
  (PartKind.ic, 'type_ic'),
  (PartKind.crystal, 'type_crystal'),
  (PartKind.connector, 'type_connector'),
  (PartKind.testPoint, 'type_testpoint'),
  (PartKind.fiducial, 'type_fiducial'),
  (PartKind.other, 'type_others'),
];

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Board background and per-part colours of the PCB navigator.
class _BoardColors extends StatelessWidget {
  const _BoardColors({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final palette = PartPalette(state.settings.board);
    final style = state.settings.board;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          s.t('grp_render'),
          style: TextStyle(fontSize: 13, color: c.textDim, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Segmented<bool>(
              value: style.depth,
              options: [(false, s.t('render_flat')), (true, s.t('render_3d'))],
              onChanged: state.setBoardDepth,
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          s.t('board_bg'),
          style: TextStyle(fontSize: 13, color: c.textDim, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Segmented<BoardBackground>(
              value: style.background,
              options: [
                (BoardBackground.canvas, s.t('bg_canvas')),
                (BoardBackground.green, s.t('bg_green')),
                (BoardBackground.black, s.t('bg_black')),
                (BoardBackground.custom, s.t('bg_custom')),
              ],
              onChanged: (b) => state.setBoardBackground(b),
            ),
            if (style.background == BoardBackground.custom) ...[
              const SizedBox(width: 12),
              _Swatch(
                color: Color(style.customBackground),
                onTap: () async {
                  final picked = await pickColor(context, Color(style.customBackground));
                  if (picked != null) state.setBoardBackground(BoardBackground.custom, custom: picked.toARGB32());
                },
              ),
            ],
          ],
        ),
        const SizedBox(height: 18),
        Text(
          s.t('preview'),
          style: TextStyle(fontSize: 13, color: c.textDim, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        _Preview(palette: palette),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: Text(
                s.t('part_colors'),
                style: TextStyle(fontSize: 13, color: c.textDim, fontWeight: FontWeight.w600),
              ),
            ),
            FlatButton(label: s.t('reset_all'), compact: true, onTap: state.resetBoardStyle),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, box) {
            final cols = box.maxWidth > 640 ? 2 : 1;
            final w = (box.maxWidth - (cols - 1) * 16) / cols;
            return Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                for (final (kind, key) in _kindLabels)
                  SizedBox(
                    width: w,
                    child: _ColorRow(
                      label: s.t(key),
                      color: palette.body(kind),
                      custom: style.partColors.containsKey(kind.name),
                      onPick: () async {
                        final picked = await pickColor(context, palette.body(kind));
                        if (picked != null) state.setPartColor(kind.name, picked.toARGB32());
                      },
                      onReset: () => state.setPartColor(kind.name, null),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({required this.label, required this.color, required this.custom, required this.onPick, required this.onReset});

  final String label;
  final Color color;
  final bool custom;
  final VoidCallback onPick;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    return Container(
      height: 46,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          _Swatch(color: color, onTap: onPick),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(fontSize: 13, color: c.text)),
          ),
          Text(
            _hex(color),
            style: TextStyle(fontSize: 12, fontFamily: monoFontFamily, color: c.textDim),
          ),
          const SizedBox(width: 10),
          if (custom) FlatButton(label: s.t('reset_default'), compact: true, onTap: onReset) else const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color, required this.onTap, this.size = 28, this.selected = false});

  final Color color;
  final VoidCallback onTap;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? c.accent : (hover ? c.text : c.borderStrong), width: selected ? 2.5 : 1),
        ),
      ),
    );
  }
}

/// A strip of sample parts on the chosen board colour.
class _Preview extends StatelessWidget {
  const _Preview({required this.palette});

  final PartPalette palette;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final board = palette.board ?? c.window;
    Widget chip(PartKind k, double w, double h, {bool ends = false}) {
      final body = palette.body(k);
      return Container(
        width: w,
        height: h,
        margin: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(color: body, borderRadius: BorderRadius.circular(k == PartKind.ic ? 3 : 1.5)),
        child: ends
            ? Row(
                children: [
                  Container(width: w * 0.2, color: PartPalette.terminal),
                  const Spacer(),
                  Container(width: w * 0.2, color: PartPalette.terminal),
                ],
              )
            : null,
      );
    }

    return Container(
      height: 86,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: board,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.borderStrong),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            chip(PartKind.resistor, 34, 16, ends: true),
            chip(PartKind.capacitor, 34, 16, ends: true),
            chip(PartKind.inductor, 40, 32, ends: true),
            chip(PartKind.diode, 30, 15),
            chip(PartKind.led, 30, 15),
            chip(PartKind.transistor, 34, 20),
            chip(PartKind.ic, 50, 50),
            chip(PartKind.crystal, 40, 30),
            chip(PartKind.connector, 60, 22),
            chip(PartKind.testPoint, 18, 18),
            chip(PartKind.fiducial, 14, 14),
            chip(PartKind.other, 30, 18),
          ],
        ),
      ),
    );
  }
}

const _presets = [
  0xFF2E9E6A,
  0xFF1F7A50,
  0xFF5CBF8A,
  0xFF0E9F9F,
  0xFF3D78D8,
  0xFF2556A8,
  0xFF6FA0F0,
  0xFF4B5A8C,
  0xFFD98A3D,
  0xFFB86A22,
  0xFFF0B062,
  0xFFC94F4F,
  0xFFE07A6B,
  0xFFB59D6B,
  0xFFBF8A57,
  0xFFCDC4B1,
  0xFF2F343B,
  0xFF3B4048,
  0xFF5B6575,
  0xFF7C8592,
  0xFF98A0A9,
  0xFFB4BAC2,
  0xFFE9EBEE,
  0xFFFFFFFF,
  0xFF1E5E3B,
  0xFF154A2E,
  0xFF16181B,
  0xFF0F2A4A,
  0xFF4A1E5E,
  0xFF5E1E1E,
  0xFFF2F5F1,
  0xFF000000,
];

/// Colour picker: preset swatches plus a hex field. Returns null on cancel.
Future<Color?> pickColor(BuildContext context, Color initial) {
  final s = Strings.of(context);
  return showAppDialog<Color>(
    context,
    title: s.t('color_pick'),
    width: 420,
    body: (ctx) => _PickerBody(initial: initial),
  );
}

class _PickerBody extends StatefulWidget {
  const _PickerBody({required this.initial});

  final Color initial;

  @override
  State<_PickerBody> createState() => _PickerBodyState();
}

class _PickerBodyState extends State<_PickerBody> {
  late Color _color = widget.initial;
  late final _hexCtl = TextEditingController(text: _hex(widget.initial));

  @override
  void dispose() {
    _hexCtl.dispose();
    super.dispose();
  }

  void _set(Color col) => setState(() {
    _color = col;
    _hexCtl.text = _hex(col);
  });

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in _presets) _Swatch(color: Color(v), size: 38, selected: _color.toARGB32() == v, onTap: () => _set(Color(v))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 38,
                height: 30,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.borderStrong),
                ),
              ),
              const SizedBox(width: 10),
              Text(s.t('color_hex'), style: TextStyle(fontSize: 12.5, color: c.textDim)),
              const SizedBox(width: 8),
              TextInput(
                controller: _hexCtl,
                width: 120,
                mono: true,
                onChanged: (v) {
                  final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(v.trim());
                  if (m != null) setState(() => _color = Color(0xFF000000 | int.parse(m.group(1)!, radix: 16)));
                },
              ),
              const Spacer(),
              FlatButton(label: s.t('dlg_cancel'), compact: true, onTap: () => Navigator.of(context).pop()),
              const SizedBox(width: 8),
              FlatButton(label: s.t('dlg_ok'), compact: true, primary: true, onTap: () => Navigator.of(context).pop(_color)),
            ],
          ),
        ],
      ),
    );
  }
}
