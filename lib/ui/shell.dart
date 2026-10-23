/// App frame of the SMT-FAI design: header with the logo, the glass pill
/// navigation and round glass actions; footer with the status and the
/// keyboard shortcuts.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'design.dart';
import 'lucide.dart';
import 'theme.dart';
import 'tour.dart';
import 'widgets.dart';

const moduleLabels = {Module.files: 'mod_files', Module.check: 'mod_check', Module.cad: 'mod_cad', Module.board: 'mod_board'};

class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 960;

    final logo = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const GradientTile(icon: Lucide.cpu, colors: GradientTile.graphite, glow: Color(0x38000000), size: 34, radius: 10, iconSize: 18),
        const SizedBox(width: 11),
        Text(
          'SMT-FAI',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: -0.36, color: c.tx),
        ),
      ],
    );

    final nav = Container(
      key: tourTargets.tabs,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.glass, borderRadius: BorderRadius.circular(999), boxShadow: c.shadowSm),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final mod in Module.values) ...[
            if (mod != Module.values.first) const SizedBox(width: 2),
            Hoverable(
              key: tourTargets.module(mod),
              onTap: () => state.setModule(mod),
              builder: (context, hover, _) {
                final on = state.module == mod && !state.settingsOpen;
                return Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on
                        ? c.navOn
                        : hover
                        ? c.hover
                        : null,
                    borderRadius: BorderRadius.circular(17),
                  ),
                  child: Text(
                    s.t(moduleLabels[mod]!),
                    style: TextStyle(fontSize: 14, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: on ? c.navOnTx : c.navTx),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (state.updateAvailable) ...[
          PillButton(
            label: s.t('upd_available', {'v': state.latestRelease!.version}),
            icon: Lucide.download,
            kind: PillKind.glass,
            height: 36,
            color: c.blueTx,
            onTap: () => state.openSettings(SettingsSection.update),
          ),
          const SizedBox(width: 8),
        ],
        _LanguageButton(state: state),
        const SizedBox(width: 8),
        GlassButton(icon: Lucide.theme, tooltip: s.t('theme_now_${state.theme.name}'), onTap: state.cycleTheme),
        const SizedBox(width: 8),
        GlassButton(key: tourTargets.help, icon: Lucide.help, tooltip: s.t('set_guide'), onTap: () => state.openSettings(SettingsSection.guide)),
        const SizedBox(width: 8),
        GlassButton(icon: Lucide.settings, tooltip: s.t('mod_settings'), onTap: () => state.openSettings()),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
      child: narrow
          ? Column(
              children: [
                Row(children: [logo, const Spacer(), actions]),
                const SizedBox(height: 12),
                SingleChildScrollView(scrollDirection: Axis.horizontal, child: nav),
              ],
            )
          : Row(children: [logo, const Spacer(), nav, const Spacer(), actions]),
    );
  }
}

class _LanguageButton extends StatefulWidget {
  const _LanguageButton({required this.state});

  final AppState state;

  @override
  State<_LanguageButton> createState() => _LanguageButtonState();
}

class _LanguageButtonState extends State<_LanguageButton> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final state = widget.state;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (_) => Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _portal.hide),
            ),
            CompositedTransformFollower(
              link: _link,
              targetAnchor: Alignment.bottomRight,
              followerAnchor: Alignment.topRight,
              offset: const Offset(0, 8),
              child: Align(
                alignment: Alignment.topRight,
                child: AppTheme(
                  colors: c,
                  child: DefaultTextStyle(
                    style: baseTextStyle(c),
                    child: Container(
                      width: 168,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(color: c.solid, borderRadius: BorderRadius.circular(18), boxShadow: c.shadow),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final lang in supportedLanguages)
                            Hoverable(
                              onTap: () {
                                _portal.hide();
                                state.setLanguage(lang);
                              },
                              builder: (context, hover, _) => Container(
                                height: 36,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: state.language == lang
                                      ? c.blueTint
                                      : hover
                                      ? c.hover
                                      : null,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        languageNames[lang]!,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: state.language == lang ? FontWeight.w600 : FontWeight.w500,
                                          color: state.language == lang ? c.blueTx : c.tx,
                                        ),
                                      ),
                                    ),
                                    if (state.language == lang) LucideIcon(Lucide.check, size: 14, color: c.blueTx, stroke: 2.6),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        child: GlassButton(label: languageNames[state.language], trailing: Lucide.chevronDown, onTap: _portal.toggle),
      ),
    );
  }
}

/// Status line and keyboard shortcuts at the bottom of every page.
class AppFooter extends StatelessWidget {
  const AppFooter({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final ng = state.report?.count(CheckCategory.ng) ?? 0;
    final files = [state.bom, state.stationA, state.stationB, state.coords].where((f) => f != null).length;
    final wide = MediaQuery.sizeOf(context).width >= 900 && !Metrics.of(context).touch;
    final style = TextStyle(fontSize: 12, color: c.tx2);
    Widget shortcut(String key, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Kbd(key),
        const SizedBox(width: 6),
        Text(label, style: style),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 16),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.report == null
                  ? const Color(0xFF34C759)
                  : ng > 0
                  ? c.ngSolid
                  : const Color(0xFF34C759),
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(s.t(state.statusKey, state.statusArgs), maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
          Text(s.t('footer_files', {'n': files}), style: style),
          if (wide) ...[
            const SizedBox(width: 20),
            shortcut('F5', s.t('btn_run')),
            const SizedBox(width: 20),
            shortcut('Ctrl+E', s.t('btn_export_report')),
            const SizedBox(width: 20),
            shortcut('Ctrl+G', s.t('btn_gen_cad')),
          ],
        ],
      ),
    );
  }
}
