/// App frame of the SMT-FAI design: header with the logo, the glass pill
/// navigation and round glass actions; footer with the status and the
/// keyboard shortcuts.
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/bom_compare.dart';
import '../l10n/strings.dart';
import 'design.dart';
import 'lucide.dart';
import 'theme.dart';
import 'tour.dart';
import 'widgets.dart';

/// Desktop header: the page name at the top left (back to the check from
/// Settings) and the round actions at the right.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final on = !state.settingsOpen;
    final nav = Hoverable(
      key: tourTargets.tabs,
      onTap: state.closeSettings,
      builder: (context, hover, _) => Container(
        height: 44,
        padding: const EdgeInsets.fromLTRB(6, 4, 16, 4),
        decoration: BoxDecoration(color: c.glass, borderRadius: c.r(999), boxShadow: c.shadowSm, border: c.cardBorder),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: on ? c.navOn : (hover ? c.hover : c.well), borderRadius: c.r(17)),
              child: LucideIcon(Lucide.clipboardCheck, size: 18, color: on ? c.navOnTx : c.navTx, stroke: 2),
            ),
            const SizedBox(width: 10),
            Text(s.t('mod_check'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: c.tx)),
          ],
        ),
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
            onTap: () => state.openSettings(SettingsSection.about),
          ),
          const SizedBox(width: 8),
        ],
        _LanguageButton(state: state),
        const SizedBox(width: 8),
        GlassButton(icon: Lucide.theme, tooltip: s.t('theme_now_${state.theme.name}'), onTap: state.cycleTheme),
        const SizedBox(width: 8),
        GlassButton(icon: Lucide.history, tooltip: s.t('set_history'), onTap: () => state.openSettings(SettingsSection.history)),
        const SizedBox(width: 8),
        GlassButton(key: tourTargets.help, icon: Lucide.help, tooltip: s.t('set_guide'), onTap: () => state.openSettings(SettingsSection.guide)),
        const SizedBox(width: 8),
        GlassButton(icon: Lucide.gear, tooltip: s.t('mod_settings'), onTap: () => state.openSettings()),
      ],
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
      child: Row(children: [nav, const Spacer(), actions]),
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
                      decoration: BoxDecoration(color: c.solid, borderRadius: c.r(18), boxShadow: c.shadow, border: c.cardBorder),
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
                                  borderRadius: c.r(12),
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
    final ng = (state.report?.count(CheckStatus.ng) ?? 0) + (state.report?.count(CheckStatus.review) ?? 0) + (state.report?.count(CheckStatus.unmatched) ?? 0);
    final files = state.loadedCount;
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
    // Industrial style: a grey status bar with a top rule.
    return Container(
      padding: c.industrial ? const EdgeInsets.fromLTRB(16, 7, 16, 7) : const EdgeInsets.fromLTRB(32, 16, 32, 16),
      decoration: c.industrial ? BoxDecoration(color: c.dark ? c.solid : const Color(0xFFF2F2F2), border: Border(top: BorderSide(color: c.dark ? c.lineStrong : const Color(0xFF8C8C8C)))) : null,
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
            shortcut('Ctrl+E', s.t('btn_export_excel')),
          ],
        ],
      ),
    );
  }
}

/// Phone top bar: the page title and round actions; language and the rest
/// live in Settings.
class PhoneHeader extends StatelessWidget {
  const PhoneHeader({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final title = state.settingsOpen ? s.t('mod_settings') : s.t('mod_check');
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: c.tx),
            ),
          ),
          if (state.updateAvailable) ...[
            GlassButton(
              icon: Lucide.download,
              size: 38,
              tooltip: s.t('upd_available', {'v': state.latestRelease!.version}),
              onTap: () => state.openSettings(SettingsSection.about),
            ),
            const SizedBox(width: 6),
          ],
          GlassButton(icon: Lucide.theme, size: 38, tooltip: s.t('theme_now_${state.theme.name}'), onTap: state.cycleTheme),
          const SizedBox(width: 6),
          GlassButton(icon: Lucide.history, size: 38, tooltip: s.t('set_history'), onTap: () => state.openSettings(SettingsSection.history)),
          const SizedBox(width: 6),
          GlassButton(key: tourTargets.help, icon: Lucide.help, size: 38, tooltip: s.t('set_guide'), onTap: () => state.openSettings(SettingsSection.guide)),
        ],
      ),
    );
  }
}

/// Height the phone tab bar covers at the bottom of the page, so lists can
/// scroll underneath it and still end above it.
const phoneTabBarInset = 92.0;

/// Phone tab bar in the "liquid glass" style: a floating capsule that blurs
/// and brightens what scrolls beneath it, with a light rim and a glass lens
/// under the current tab. Settings is the last tab.
class PhoneNavBar extends StatelessWidget {
  const PhoneNavBar({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final tabs = [
      (Lucide.clipboardCheck, s.t('mod_check'), !state.settingsOpen, state.closeSettings, tourTargets.checkTab),
      (Lucide.gear, s.t('mod_settings'), state.settingsOpen, () => state.openSettings(), null),
    ];
    final ind = c.industrial;
    final items = Row(
      children: [
        for (final (icon, label, on, onTap, key) in tabs)
          Expanded(
            child: Hoverable(
              key: key,
              onTap: onTap,
              builder: (context, hover, _) {
                final color = ind ? (on ? c.navOnTx : c.tx2) : (on ? c.blueTx : c.tx);
                final BoxDecoration deco;
                if (ind) {
                  deco = BoxDecoration(borderRadius: c.r(4), color: on ? c.navOn : (hover ? c.hover : null));
                } else if (on) {
                  deco = BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    color: c.dark ? const Color(0x24FFFFFF) : const Color(0x8CFFFFFF),
                    border: Border.all(color: c.dark ? const Color(0x33FFFFFF) : const Color(0xCCFFFFFF), width: 0.8),
                    boxShadow: [BoxShadow(color: Color.fromRGBO(0, 0, 0, c.dark ? 0.25 : 0.08), blurRadius: 10, offset: const Offset(0, 3))],
                  );
                } else {
                  deco = BoxDecoration(borderRadius: BorderRadius.circular(28), color: hover ? c.hover : null);
                }
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  height: ind ? 52 : 56,
                  decoration: deco,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      LucideIcon(icon, size: 22, color: color, stroke: on ? 2.2 : 1.8),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, fontWeight: on ? FontWeight.w600 : FontWeight.w500, color: color),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
    // Industrial style: a flat bar along the bottom edge with a top rule.
    if (ind) {
      return Container(
        key: tourTargets.tabs,
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        decoration: BoxDecoration(
          color: c.card,
          border: Border(top: BorderSide(color: c.lineStrong)),
        ),
        child: items,
      );
    }
    final radius = BorderRadius.circular(34);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Container(
        key: tourTargets.tabs,
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(color: Color.fromRGBO(0, 0, 0, c.dark ? 0.45 : 0.14), blurRadius: 30, offset: const Offset(0, 12)),
            BoxShadow(color: Color.fromRGBO(0, 0, 0, c.dark ? 0.3 : 0.06), blurRadius: 3, offset: const Offset(0, 1)),
          ],
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.compose(outer: ImageFilter.blur(sigmaX: 22, sigmaY: 22), inner: const ColorFilter.matrix(_saturate)),
            child: CustomPaint(
              painter: _GlassPainter(dark: c.dark, radius: 34),
              child: Padding(padding: const EdgeInsets.all(6), child: items),
            ),
          ),
        ),
      ),
    );
  }
}

/// Saturation 1.6: colours under the glass come through livelier.
const _saturate = <double>[
  1.47244, -0.42912, -0.04332, 0, 0, //
  -0.12756, 1.17088, -0.04332, 0, 0,
  -0.12756, -0.42912, 1.55668, 0, 0,
  0, 0, 0, 1, 0,
];

/// Glass body: a flat translucent fill and a thin light rim.
class _GlassPainter extends CustomPainter {
  _GlassPainter({required this.dark, required this.radius});

  final bool dark;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    canvas.drawRRect(rr, Paint()..color = dark ? const Color(0xB31C1C1F) : const Color(0xB3F8F8FA));
    canvas.drawRRect(
      rr.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = dark ? const Color(0x33FFFFFF) : const Color(0xCCFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_GlassPainter old) => old.dark != dark;
}
