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
import 'theme.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    Widget section(Glyph glyph, String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SurfaceCard(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                GlyphIcon(glyph, size: 20, color: c.accent),
                const SizedBox(width: 10),
                Text(title, style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.text)),
              ]),
              const SizedBox(height: 14),
              ...children,
            ]),
          ),
        );
    Widget row(String label, Widget control) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 13, color: c.textDim))),
            Flexible(child: Align(alignment: Alignment.centerLeft, child: control)),
          ]),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PageHeader(title: s.t('mod_settings'), subtitle: s.t('set_current', {'v': appVersion})),
      Expanded(
        child: Container(
          color: c.window,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  section(Glyph.sun, s.t('set_appearance'), [
                    row(
                      s.t('set_theme'),
                      Segmented<ThemePref>(
                        value: state.theme,
                        options: [
                          (ThemePref.light, s.t('btn_light')),
                          (ThemePref.dark, s.t('btn_dark')),
                          (ThemePref.system, s.t('btn_system')),
                        ],
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
                  ]),
                  section(Glyph.update, s.t('set_update'), [_UpdatePanel(state: state)]),
                  section(Glyph.info, s.t('set_about'), [
                    Text('SMT-FAI ${s.t('about_version', {'v': appVersion})}', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                    const SizedBox(height: 6),
                    Text(s.t('about_text'), style: TextStyle(fontSize: 12.5, color: c.textDim)),
                    const SizedBox(height: 10),
                    Text(s.t('about_config'), style: TextStyle(fontSize: 12, color: c.textFaint)),
                    Text('${state.settingsDir}${Platform.pathSeparator}settings.json',
                        style: TextStyle(fontFamily: monoFontFamily, fontSize: 12, color: c.textDim)),
                    const SizedBox(height: 10),
                    Text(s.t('set_licenses'), style: TextStyle(fontSize: 12, color: c.textFaint)),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
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
