/// Settings: a list of pages (appearance, navigator colours, rules, part
/// library, user guide, about with software update).
library;

import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/footprints.dart';
import '../core/settings.dart';
import '../core/updater.dart';
import '../l10n/strings.dart';
import '../version.dart';
import 'board_view.dart';
import 'design.dart';
import 'guide_page.dart';
import 'library_page.dart';
import 'lucide.dart';
import 'rules_page.dart';
import 'theme.dart';
import 'ui_scale.dart';
import 'widgets.dart';

/// Settings, like the settings of a desktop or phone OS: a list of pages in
/// grouped rows; a row opens its page, whose back button returns to the list.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = Strings.of(context);
    final phone = isPhoneLayout(context);
    final section = state.settingsSection;
    final pad = EdgeInsets.fromLTRB(phone ? 14 : 24, phone ? 4 : 6, phone ? 14 : 24, 0);
    if (section == null) return Padding(padding: pad, child: _SettingsList(state: state));

    final title = s.t(_titles[section]!);
    final content = switch (section) {
      SettingsSection.rules => RulesPage(state: state),
      SettingsSection.library => PartLibraryPage(state: state),
      SettingsSection.guide => GuidePage(state: state),
      SettingsSection.appearance => _Section(child: _Appearance(state: state)),
      SettingsSection.board => _Section(child: _BoardColors(state: state)),
      SettingsSection.about => _Section(child: _About(state: state)),
    };
    return Padding(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Second-level page: back to the list, and the page title.
          Row(
            children: [
              PillButton(
                label: s.t('mod_settings'),
                icon: Lucide.chevronLeft,
                kind: PillKind.glass,
                height: 36,
                fontSize: 14,
                iconSize: 16,
                padding: const EdgeInsets.fromLTRB(10, 0, 16, 0),
                onTap: () => state.setSettingsSection(null),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppTheme.of(context).tx),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: content is _Section ? DCard(clip: true, radius: 24, child: content) : content,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _titles = {
  SettingsSection.appearance: 'set_appearance',
  SettingsSection.board: 'set_board_colors',
  SettingsSection.library: 'set_library',
  SettingsSection.rules: 'set_rules',
  SettingsSection.guide: 'set_guide',
  SettingsSection.about: 'set_about',
};

/// The settings list: grouped rows with an icon, a title, a hint and an
/// arrow to the page.
class _SettingsList extends StatelessWidget {
  const _SettingsList({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final phone = isPhoneLayout(context);
    final groups = [
      [
        (SettingsSection.appearance, Lucide.brush, const Color(0xFF5E5CE6), s.t('set_appearance_hint'), null),
        (SettingsSection.board, Lucide.palette, const Color(0xFFFF9F0A), s.t('set_board_hint'), null),
      ],
      [
        (SettingsSection.rules, Lucide.shield, const Color(0xFF34C759), s.t('set_rules_hint'), null),
        (SettingsSection.library, Lucide.library, const Color(0xFF0A84FF), s.t('set_library_hint'), null),
      ],
      [
        (SettingsSection.guide, Lucide.book, const Color(0xFF30B0C7), s.t('set_guide_hint'), null),
        (
          SettingsSection.about,
          Lucide.info,
          const Color(0xFF8E8E93),
          s.t('about_version', {'v': appVersion}),
          state.updateAvailable ? s.t('upd_available', {'v': state.latestRelease!.version}) : null,
        ),
      ],
    ];
    Widget row(SettingsSection sec, Lucide icon, Color color, String hint, String? badge, bool last) => Hoverable(
      onTap: () => state.setSettingsSection(sec),
      builder: (context, hover, _) => Container(
        color: hover ? c.hover : null,
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: color, borderRadius: c.r(9)),
              child: LucideIcon(icon, size: 17, color: const Color(0xFFFFFFFF), stroke: 2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.t(_titles[sec]!), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.tx)),
                  const SizedBox(height: 2),
                  Text(hint, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: c.tx2)),
                ],
              ),
            ),
            if (badge != null) ...[
              DBadge(text: badge, background: c.blueTint, color: c.blueTx),
              const SizedBox(width: 8),
            ],
            LucideIcon(Lucide.chevronRight, size: 16, color: c.tx3, stroke: 2.2),
          ],
        ),
      ),
    );
    return ListView(
      padding: EdgeInsets.only(bottom: bottomInset(context) + 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!phone)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
                    child: Row(
                      children: [
                        PillButton(
                          label: s.t('btn_back'),
                          icon: Lucide.chevronLeft,
                          kind: PillKind.glass,
                          height: 36,
                          fontSize: 14,
                          iconSize: 16,
                          padding: const EdgeInsets.fromLTRB(10, 0, 16, 0),
                          onTap: state.closeSettings,
                        ),
                        const SizedBox(width: 14),
                        Text(
                          s.t('mod_settings'),
                          style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: c.tx),
                        ),
                      ],
                    ),
                  ),
                for (final group in groups) ...[
                  DCard(
                    radius: 20,
                    clip: true,
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < group.length; i++) ...[
                          if (i > 0) Padding(padding: const EdgeInsets.only(left: 62), child: Container(height: 1, color: c.line)),
                          row(group[i].$1, group[i].$2, group[i].$3, group[i].$4, group[i].$5, i == group.length - 1),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Scrollable content of a short settings page.
class _Section extends StatelessWidget {
  const _Section({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final phone = isPhoneLayout(context);
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(phone ? 18 : 28, phone ? 18 : 24, phone ? 18 : 28, (phone ? 24 : 28) + bottomInset(context)),
      child: child,
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
    // Phones put the label above its control.
    final phone = isPhoneLayout(context);
    Widget row(String label, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: phone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 13, color: c.textDim)),
                const SizedBox(height: 8),
                control,
              ],
            )
          : Row(
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
          s.t('set_theme_style'),
          Segmented<ThemeStyle>(
            value: state.settings.themeStyle,
            options: [(ThemeStyle.modern, s.t('style_modern')), (ThemeStyle.industrial, s.t('style_industrial'))],
            onChanged: state.setThemeStyle,
          ),
        ),
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
            options: [(0, s.t('ui_scale_auto')), for (final v in uiScaleSteps) (v, '${(v * 100).round()}%')],
            onChanged: state.setUiScale,
          ),
        ),
        row(
          s.t('set_language'),
          Segmented<String>(value: state.language, options: [for (final l in supportedLanguages) (l, languageNames[l]!)], onChanged: state.setLanguage),
        ),
      ],
    );
  }
}

/// About: the app, its version and platform, software update, links and
/// the open-source components it uses.
class _About extends StatelessWidget {
  const _About({required this.state});

  final AppState state;

  static const _site = 'https://marginal-z.github.io/FAI-SMT/';

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final phone = isPhoneLayout(context);
    final platform = switch (Abi.current()) {
      Abi.windowsX64 => 'Windows x64',
      Abi.windowsArm64 => 'Windows ARM64',
      Abi.linuxX64 => 'Linux x64',
      Abi.linuxArm64 => 'Linux ARM64',
      Abi.androidArm64 => 'Android ARM64',
      Abi.androidArm => 'Android ARMv7',
      Abi.androidX64 => 'Android x86_64',
      final abi => abi.toString(),
    };
    Widget chip(String text, {bool accent = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(color: accent ? c.blueTint : c.well, borderRadius: c.r(999)),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: accent ? c.blueTx : c.tx2),
      ),
    );
    final hero = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: c.r(phone ? 16 : 20),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 8))],
          ),
          child: ClipRRect(
            borderRadius: c.r(phone ? 16 : 20),
            child: Image.asset('assets/icon/app_icon.png', width: phone ? 60 : 76, height: phone ? 60 : 76, filterQuality: FilterQuality.medium),
          ),
        ),
        SizedBox(width: phone ? 14 : 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SMT-FAI',
                style: TextStyle(fontSize: phone ? 22 : 28, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: c.tx),
              ),
              const SizedBox(height: 6),
              Text(s.t('about_tagline'), style: TextStyle(fontSize: 13.5, height: 1.45, color: c.tx2)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [chip(s.t('about_version', {'v': appVersion}), accent: true), chip(platform), chip(s.t('about_release'))],
              ),
            ],
          ),
        ),
      ],
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hero,
        const SizedBox(height: 26),
        _Group(
          title: s.t('about_update'),
          child: Padding(padding: const EdgeInsets.all(16), child: _UpdatePanel(state: state)),
        ),
        const SizedBox(height: 20),
        _Group(
          title: s.t('about_info'),
          rows: [
            _InfoRow(label: s.t('about_version_label'), value: appVersion),
            _InfoRow(label: s.t('about_platform'), value: platform),
            _InfoRow(label: s.t('about_config'), value: '${state.settingsDir}${Platform.pathSeparator}settings.json', mono: true, copy: true),
            _InfoRow(label: s.t('about_source_label'), value: 'GitHub Releases · $updateRepo'),
          ],
        ),
        const SizedBox(height: 20),
        _Group(
          title: s.t('about_links'),
          rows: [
            _InfoRow(label: s.t('about_site'), value: _site, link: true),
            _InfoRow(label: s.t('about_tutorial'), value: '$_site#tutorial', link: true),
            _InfoRow(label: s.t('about_changelog'), value: 'https://github.com/$updateRepo/releases', link: true),
            _InfoRow(label: s.t('about_github'), value: 'https://github.com/$updateRepo', link: true),
          ],
        ),
        const SizedBox(height: 20),
        _Group(
          title: s.t('about_licenses'),
          rows: const [
            _InfoRow(label: 'Flutter', value: 'BSD-3-Clause'),
            _InfoRow(label: 'Inter', value: 'SIL Open Font License 1.1'),
            _InfoRow(label: 'Lucide', value: 'ISC'),
            _InfoRow(label: 'Phosphor Icons', value: 'MIT'),
            _InfoRow(label: 'Fluent UI System Icons', value: 'MIT'),
            _InfoRow(label: 'excel · archive · xml · file_picker · desktop_drop', value: 'MIT / BSD'),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          s.t('about_footer', {'y': DateTime.now().year}),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, height: 1.6, color: c.tx3),
        ),
      ],
    );
  }
}

/// A titled group of rows on a light well, like the settings list.
class _Group extends StatelessWidget {
  const _Group({required this.title, this.rows = const [], this.child});

  final String title;
  final List<Widget> rows;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.tx2)),
        ),
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: c.well, borderRadius: c.r(16)),
          child:
              child ??
              Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) Padding(padding: const EdgeInsets.only(left: 16), child: Container(height: 1, color: c.line)),
                    rows[i],
                  ],
                ],
              ),
        ),
      ],
    );
  }
}

/// Label and value; links open in the browser, paths can be copied.
class _InfoRow extends StatefulWidget {
  const _InfoRow({required this.label, required this.value, this.mono = false, this.copy = false, this.link = false});

  final String label;
  final String value;
  final bool mono;
  final bool copy;
  final bool link;

  @override
  State<_InfoRow> createState() => _InfoRowState();
}

class _InfoRowState extends State<_InfoRow> {
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.value));
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (mounted) setState(() => _copied = false);
  }

  /// Opens [url] in the default browser; where that is not possible (the
  /// Android build has no browser hook) the link is copied instead.
  Future<void> _open() async {
    try {
      if (Platform.isWindows) {
        await Process.start('cmd', ['/c', 'start', '', widget.value], mode: ProcessStartMode.detached);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [widget.value], mode: ProcessStartMode.detached);
      } else if (Platform.isMacOS) {
        await Process.start('open', [widget.value], mode: ProcessStartMode.detached);
      } else {
        await _copy();
      }
    } catch (_) {
      await _copy();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final action = widget.link ? _open : (widget.copy ? _copy : null);
    final icon = _copied ? Lucide.check : (widget.link ? Lucide.externalLink : Lucide.copy);
    return Hoverable(
      onTap: action,
      cursor: action == null ? SystemMouseCursors.basic : SystemMouseCursors.click,
      tooltip: action == null ? null : (_copied ? s.t('about_copied') : (widget.link ? s.t('about_open') : s.t('about_copy'))),
      builder: (context, hover, _) => Container(
        color: hover ? c.hover : null,
        padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 150,
              child: Text(widget.label, style: TextStyle(fontSize: 13.5, color: c.tx2)),
            ),
            Expanded(
              child: Text(
                widget.value,
                style: TextStyle(
                  fontSize: widget.mono ? 12.5 : 13.5,
                  fontFamily: widget.mono ? monoFontFamily : null,
                  fontWeight: FontWeight.w500,
                  color: widget.link ? c.blueTx : c.tx,
                ),
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: 10),
              LucideIcon(icon, size: 15, color: _copied ? c.okTx : c.tx3, stroke: 2.2),
            ],
          ],
        ),
      ),
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
            borderRadius: c.r(3),
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
              borderRadius: c.r(6),
              border: Border.all(color: c.border),
            ),
            child: SingleChildScrollView(
              child: Text(release.notes.trim(), style: TextStyle(fontSize: 12.5, color: c.text, height: 1.5)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        CheckBox(value: state.settings.autoUpdate, label: s.t('set_auto_update'), onChanged: state.setAutoUpdate),
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
  (PartKind.electromech, 'type_electromech'),
  (PartKind.mechanical, 'type_mechanical'),
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
            Segmented<bool>(value: style.depth, options: [(false, s.t('render_flat')), (true, s.t('render_3d'))], onChanged: state.setBoardDepth),
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
          borderRadius: c.r(6),
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
    final board = palette.board ?? c.well;
    Widget chip(PartKind k, double w, double h, {bool ends = false}) {
      final body = palette.body(k);
      return Container(
        width: w,
        height: h,
        margin: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(color: body, borderRadius: c.r(k == PartKind.ic ? 3 : 1.5)),
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
        borderRadius: c.r(20),
        border: Border.all(color: c.line),
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
            children: [for (final v in _presets) _Swatch(color: Color(v), size: 38, selected: _color.toARGB32() == v, onTap: () => _set(Color(v)))],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 38,
                height: 30,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: c.r(6),
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
