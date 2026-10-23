/// Settings module: appearance, software update, about.
library;

import 'dart:io';

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/settings.dart';
import '../core/updater.dart';
import '../l10n/strings.dart';
import '../version.dart';
import 'glyphs.dart';
import 'rules_page.dart';
import 'theme.dart';
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
      (SettingsSection.rules, Glyph.rules, s.t('set_rules')),
      (SettingsSection.update, Glyph.update, s.t('set_update')),
      (SettingsSection.about, Glyph.info, s.t('set_about')),
    ];
    final narrow = MediaQuery.sizeOf(context).width < 900;

    final nav = narrow
        ? Container(
            height: 48,
            decoration: BoxDecoration(color: c.panel, border: Border(bottom: BorderSide(color: c.border))),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(children: [
                for (final (sec, glyph, label) in sections)
                  _NavItem(glyph: glyph, label: label, active: state.settingsSection == sec, onTap: () => state.setSettingsSection(sec)),
              ]),
            ),
          )
        : Container(
            width: 232,
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 14),
            decoration: BoxDecoration(color: c.panel, border: Border(right: BorderSide(color: c.border))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final (sec, glyph, label) in sections)
                _NavItem(glyph: glyph, label: label, active: state.settingsSection == sec, onTap: () => state.setSettingsSection(sec)),
            ]),
          );

    final content = switch (state.settingsSection) {
      SettingsSection.rules => RulesPage(state: state),
      SettingsSection.appearance => _Section(title: s.t('set_appearance'), child: _Appearance(state: state)),
      SettingsSection.update => _Section(title: s.t('set_update'), child: _UpdatePanel(state: state)),
      SettingsSection.about => _Section(title: s.t('set_about'), child: _About(state: state)),
    };

    return Container(
      color: c.window,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          height: m.menuBar + 10,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(color: c.chrome, border: Border(bottom: BorderSide(color: c.border))),
          child: Row(children: [
            Hoverable(
              onTap: state.closeSettings,
              builder: (context, hover, _) => Container(
                height: m.iconButton + 4,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(color: hover ? c.hover : null, borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  GlyphIcon(Glyph.back, size: 18, color: c.text),
                  const SizedBox(width: 6),
                  Text(s.t('btn_back'), style: TextStyle(fontSize: 13, color: c.text)),
                ]),
              ),
            ),
            Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 12), color: c.borderStrong),
            GlyphIcon(Glyph.settings, size: 18, color: c.accent),
            const SizedBox(width: 8),
            Text(s.t('mod_settings'), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
            const Spacer(),
            Text('SMT-FAI ${s.t('about_version', {'v': appVersion})}', style: TextStyle(fontSize: 12, color: c.textFaint)),
            const SizedBox(width: 6),
          ]),
        ),
        Expanded(
          child: narrow
              ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [nav, Expanded(child: content)])
              : Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [nav, Expanded(child: content)]),
        ),
      ]),
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
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            GlyphIcon(glyph, size: 18, filled: active, color: active ? c.accent : c.textDim),
            const SizedBox(width: 10),
            Text(label, style: TextStyle(fontSize: 13, color: active ? c.accent : c.text, fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
          ]),
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
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
            const SizedBox(height: 14),
            SurfaceCard(padding: const EdgeInsets.fromLTRB(22, 18, 22, 20), child: child),
          ]),
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
          child: Row(children: [
            SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 13, color: c.textDim))),
            Flexible(child: Align(alignment: Alignment.centerLeft, child: control)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row(
        s.t('set_theme'),
        Segmented<ThemePref>(
          value: state.theme,
          options: [(ThemePref.light, s.t('btn_light')), (ThemePref.dark, s.t('btn_dark')), (ThemePref.system, s.t('btn_system'))],
          onChanged: state.setTheme,
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
    ]);
  }
}

class _About extends StatelessWidget {
  const _About({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Image.asset('assets/icon/app_icon_64.png', width: 48, height: 48),
        const SizedBox(width: 14),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SMT-FAI', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: c.text)),
          Text(s.t('about_version', {'v': appVersion}), style: TextStyle(fontSize: 12.5, color: c.textDim)),
        ]),
      ]),
      const SizedBox(height: 14),
      Text(s.t('about_text'), style: TextStyle(fontSize: 12.5, color: c.textDim, height: 1.5)),
      const SizedBox(height: 12),
      Text(s.t('about_config'), style: TextStyle(fontSize: 12, color: c.textFaint)),
      Text('${state.settingsDir}${Platform.pathSeparator}settings.json', style: TextStyle(fontFamily: monoFontFamily, fontSize: 12, color: c.textDim)),
      const SizedBox(height: 12),
      Text(s.t('set_licenses'), style: TextStyle(fontSize: 12, color: c.textFaint)),
    ]);
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

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(child: Text(line, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: c.text))),
        FlatButton(label: s.t('btn_check_update'), compact: true, onTap: busy ? null : () => state.checkForUpdates()),
        if (state.updateAvailable) ...[
          const SizedBox(width: 8),
          FlatButton(label: s.t('btn_install_update'), compact: true, primary: true, onTap: busy ? null : state.downloadAndInstall),
        ],
      ]),
      if (status == UpdateStatus.downloading) ...[
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: SizedBox(
            height: 6,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (state.updateProgress > 0) Expanded(flex: (state.updateProgress * 1000).round().clamp(1, 1000), child: ColoredBox(color: c.accent)),
              if (state.updateProgress < 1)
                Expanded(flex: (1000 - state.updateProgress * 1000).round().clamp(1, 1000), child: ColoredBox(color: c.border)),
            ]),
          ),
        ),
      ],
      if (Platform.isAndroid && state.updateAvailable) ...[
        const SizedBox(height: 8),
        Text(s.t('upd_android_hint'), style: TextStyle(fontSize: 12, color: c.textFaint)),
      ],
      if (release != null && state.updateAvailable && release.notes.trim().isNotEmpty) ...[
        const SizedBox(height: 14),
        Text(s.t('upd_notes'), style: TextStyle(fontSize: 12, color: c.textDim, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 220),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: c.panelAlt, borderRadius: BorderRadius.circular(6), border: Border.all(color: c.border)),
          child: SingleChildScrollView(child: Text(release.notes.trim(), style: TextStyle(fontSize: 12.5, color: c.text, height: 1.5))),
        ),
      ],
      const SizedBox(height: 12),
      CheckBox(value: state.settings.autoUpdate, label: s.t('set_auto_update'), onChanged: state.setAutoUpdate),
      const SizedBox(height: 4),
      Text(s.t('set_update_source', {'repo': updateRepo}), style: TextStyle(fontSize: 12, color: c.textFaint)),
    ]);
  }
}
