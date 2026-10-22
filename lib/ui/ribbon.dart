/// Title bar (module tabs, language menu, theme, about) and the ribbon whose
/// commands belong to the active module.
library;

import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/parsers.dart';
import '../core/settings.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'dialogs.dart';
import 'glyphs.dart';
import 'logo.dart';
import 'theme.dart';
import 'widgets.dart';

const moduleLabels = {
  Module.files: 'mod_files',
  Module.check: 'mod_check',
  Module.rules: 'mod_rules',
  Module.board: 'mod_board',
  Module.cad: 'mod_cad',
};

class TitleBar extends StatelessWidget {
  const TitleBar({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final s = Strings.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return Container(
      height: m.menuBar + 4,
      decoration: BoxDecoration(color: c.chrome, border: Border(bottom: BorderSide(color: c.border))),
      child: Row(
        children: [
          const SizedBox(width: 14),
          const AppLogo(size: 22),
          const SizedBox(width: 9),
          Text('SMT-FAI', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: c.text, letterSpacing: 0.6)),
          Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 14), color: c.borderStrong),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final mod in Module.values)
                  _ModuleTab(label: s.t(moduleLabels[mod]!), active: state.module == mod, onTap: () => state.setModule(mod)),
              ]),
            ),
          ),
          if (width >= 1360) ...[
            Text(s.t('app_subtitle'), style: TextStyle(fontSize: 12, color: c.textFaint)),
            const SizedBox(width: 16),
          ],
          LanguageMenu(state: state),
          const SizedBox(width: 4),
          _TitleIcon(
            glyph: switch (state.theme) {
              ThemePref.system => Glyph.system,
              ThemePref.light => Glyph.sun,
              ThemePref.dark => Glyph.moon,
            },
            tooltip: s.t('theme_now_${state.theme.name}'),
            onTap: state.cycleTheme,
          ),
          _TitleIcon(glyph: Glyph.info, tooltip: s.t('btn_about'), onTap: () => showAboutDialog(context, state)),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ModuleTab extends StatelessWidget {
  const _ModuleTab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        height: m.menuBar + 4,
        padding: EdgeInsets.symmetric(horizontal: m.touch ? 18 : 15),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: hover && !active ? c.hover : null,
          border: Border(bottom: BorderSide(color: active ? c.accent : const Color(0x00000000), width: 2)),
        ),
        child: Text(label,
            style: TextStyle(
              fontSize: 13,
              color: active ? c.text : c.textDim,
              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              letterSpacing: 0.2,
            )),
      ),
    );
  }
}

class _TitleIcon extends StatelessWidget {
  const _TitleIcon({required this.glyph, required this.tooltip, required this.onTap});

  final Glyph glyph;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final size = Metrics.of(context).iconButton + 4;
    return Hoverable(
      onTap: onTap,
      tooltip: tooltip,
      builder: (context, hover, pressed) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: pressed ? c.pressed : hover ? c.hover : null, borderRadius: BorderRadius.circular(6)),
        child: GlyphIcon(glyph, size: 19, color: c.textDim),
      ),
    );
  }
}

/// Collapsed language picker: globe + current language, opens a small menu.
class LanguageMenu extends StatefulWidget {
  const LanguageMenu({super.key, required this.state});

  final AppState state;

  @override
  State<LanguageMenu> createState() => _LanguageMenuState();
}

class _LanguageMenuState extends State<LanguageMenu> {
  final _portal = OverlayPortalController();
  final _link = LayerLink();

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final state = widget.state;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _portal,
        overlayChildBuilder: (overlayContext) => Stack(children: [
          Positioned.fill(child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: _portal.hide)),
          CompositedTransformFollower(
            link: _link,
            targetAnchor: Alignment.bottomRight,
            followerAnchor: Alignment.topRight,
            offset: const Offset(0, 6),
            child: Align(
              alignment: Alignment.topRight,
              child: AppTheme(
                colors: c,
                child: DefaultTextStyle(
                  style: baseTextStyle(c),
                  child: Container(
                    width: 176,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: c.panel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.borderStrong),
                      boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, 6))],
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final lang in supportedLanguages)
                        Hoverable(
                          onTap: () {
                            _portal.hide();
                            state.setLanguage(lang);
                          },
                          builder: (context, hover, _) => Container(
                            height: m.touch ? 44 : 34,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(color: hover ? c.hover : null, borderRadius: BorderRadius.circular(5)),
                            child: Row(children: [
                              Expanded(
                                child: Text(languageNames[lang]!,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: c.text,
                                      fontWeight: state.language == lang ? FontWeight.w700 : FontWeight.w400,
                                    )),
                              ),
                              if (state.language == lang) CustomPaint(size: const Size(14, 14), painter: _TickPainter(c.accent)),
                            ]),
                          ),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ]),
        child: Hoverable(
          onTap: _portal.toggle,
          builder: (context, hover, _) => Container(
            height: m.iconButton + 4,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: hover ? c.hover : null,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              GlyphIcon(Glyph.globe, size: 16, color: c.textDim),
              const SizedBox(width: 7),
              Text(languageNames[state.language]!, style: TextStyle(fontSize: 12.5, color: c.text, fontWeight: FontWeight.w500)),
              const SizedBox(width: 6),
              CustomPaint(size: const Size(9, 9), painter: _CaretPainter(c.textDim)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  _CaretPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.15, size.height * 0.35)
        ..lineTo(size.width * 0.5, size.height * 0.7)
        ..lineTo(size.width * 0.85, size.height * 0.35),
      p,
    );
  }

  @override
  bool shouldRepaint(_CaretPainter old) => old.color != color;
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(size.width * 0.15, size.height * 0.52)
        ..lineTo(size.width * 0.4, size.height * 0.76)
        ..lineTo(size.width * 0.88, size.height * 0.24),
      p,
    );
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}

/// Command ribbon for the active module.
class Ribbon extends StatelessWidget {
  const Ribbon({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final s = Strings.of(context);
    return Container(
      height: m.ribbon,
      decoration: BoxDecoration(color: c.ribbon, border: Border(bottom: BorderSide(color: c.border))),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: switch (state.module) {
            Module.files => _files(context, s, c),
            Module.check => _check(context, s),
            Module.rules => _rules(context, s),
            Module.board => _board(context, s),
            Module.cad => _cad(context, s),
          },
        ),
      ),
    );
  }

  List<Widget> _files(BuildContext context, Strings s, AppColors c) => [
        RibbonGroup(label: s.t('grp_import'), children: [
          RibbonButton(
              glyph: Glyph.bom, label: s.t('btn_bom'), badge: state.bom != null ? c.pass : null, onTap: () => importFile(context, state, InputKind.bom)),
          RibbonButton(
              glyph: Glyph.stationA,
              label: s.t('btn_station_a'),
              badge: state.stationA != null ? c.pass : null,
              onTap: () => importFile(context, state, InputKind.stationA)),
          RibbonButton(
              glyph: Glyph.stationB,
              label: s.t('btn_station_b'),
              badge: state.stationB != null ? c.pass : null,
              onTap: () => importFile(context, state, InputKind.stationB)),
          RibbonButton(
              glyph: Glyph.coords,
              label: s.t('btn_coord'),
              badge: state.coords != null ? c.pass : null,
              onTap: () => importFile(context, state, InputKind.coords)),
        ]),
        RibbonGroup(label: s.t('grp_coord_import'), children: [
          RibbonButton(
            glyph: Glyph.unitAuto,
            label: s.t('unit_auto'),
            active: state.settings.coordUnit == CoordUnit.auto,
            onTap: () => _setUnit(context, CoordUnit.auto),
          ),
          Column(mainAxisSize: MainAxisSize.min, children: [
            for (final u in [CoordUnit.mm, CoordUnit.mil, CoordUnit.inch])
              RibbonOption(label: s.t('unit_${u.name}'), selected: state.settings.coordUnit == u, onTap: () => _setUnit(context, u)),
          ]),
        ]),
        RibbonGroup(label: s.t('grp_project'), children: [
          RibbonButton(glyph: Glyph.clear, label: s.t('btn_clear'), onTap: state.clearAll),
          RibbonButton(glyph: Glyph.runCheck, label: s.t('btn_run'), primary: true, onTap: () => runCheck(context, state)),
        ]),
      ];

  void _setUnit(BuildContext context, CoordUnit u) {
    try {
      state.setCoordUnit(u);
    } catch (e) {
      showError(context, e);
    }
  }

  List<Widget> _check(BuildContext context, Strings s) => [
        RibbonGroup(label: s.t('grp_check'), children: [
          RibbonButton(glyph: Glyph.runCheck, label: s.t('btn_run'), primary: true, onTap: () => runCheck(context, state)),
        ]),
        RibbonGroup(label: s.t('grp_export'), children: [
          RibbonButton(glyph: Glyph.report, label: s.t('btn_export_report'), onTap: state.report == null ? null : () => exportReport(context, state)),
        ]),
      ];

  List<Widget> _rules(BuildContext context, Strings s) => [
        RibbonGroup(label: s.t('grp_rules'), children: [
          RibbonButton(
              glyph: Glyph.exclusion,
              label: s.t('btn_exclusion'),
              active: state.rulesSection == RulesSection.exclusion,
              onTap: () => state.openRules(RulesSection.exclusion)),
          RibbonButton(
              glyph: Glyph.alternates,
              label: s.t('btn_substitutes'),
              active: state.rulesSection == RulesSection.alternates,
              onTap: () => state.openRules(RulesSection.alternates)),
          RibbonButton(
              glyph: Glyph.general,
              label: s.t('btn_general'),
              active: state.rulesSection == RulesSection.general,
              onTap: () => state.openRules(RulesSection.general)),
        ]),
      ];

  List<Widget> _board(BuildContext context, Strings s) => [
        RibbonGroup(label: s.t('grp_side'), children: [
          RibbonButton(
              glyph: Glyph.layersBoth,
              label: s.t('side_both'),
              active: state.boardSide == BoardSideFilter.both,
              onTap: () => state.setBoardSide(BoardSideFilter.both)),
          RibbonButton(
              glyph: Glyph.layerTop,
              label: s.t('side_top'),
              active: state.boardSide == BoardSideFilter.top,
              onTap: () => state.setBoardSide(BoardSideFilter.top)),
          RibbonButton(
              glyph: Glyph.layerBottom,
              label: s.t('side_bottom'),
              active: state.boardSide == BoardSideFilter.bottom,
              onTap: () => state.setBoardSide(BoardSideFilter.bottom)),
        ]),
        RibbonGroup(label: s.t('grp_view'), children: [
          RibbonButton(glyph: Glyph.fit, label: s.t('board_fit'), onTap: state.fitBoard),
        ]),
      ];

  List<Widget> _cad(BuildContext context, Strings s) => [
        RibbonGroup(label: s.t('grp_cad'), children: [
          RibbonButton(glyph: Glyph.cadFormat, label: s.t('btn_cad_template'), onTap: () => showCadTemplateDialog(context, state)),
        ]),
        RibbonGroup(label: s.t('grp_export'), children: [
          RibbonButton(
            glyph: Glyph.cad,
            label: s.t('btn_gen_cad'),
            primary: true,
            onTap: state.report == null || state.coords == null ? null : () => exportCad(context, state),
          ),
          RibbonButton(glyph: Glyph.report, label: s.t('btn_export_report'), onTap: state.report == null ? null : () => exportReport(context, state)),
        ]),
      ];
}

class RibbonGroup extends StatelessWidget {
  const RibbonGroup({super.key, required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 7, 6, 0),
      decoration: BoxDecoration(border: Border(right: BorderSide(color: c.border))),
      child: Column(
        children: [
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final ch in children) Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: ch),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(label, style: TextStyle(fontSize: 11, color: c.textFaint, letterSpacing: 0.4)),
          ),
        ],
      ),
    );
  }
}

/// Large ribbon button: glyph above label, like CAD / image-editor ribbons.
class RibbonButton extends StatelessWidget {
  const RibbonButton({super.key, required this.glyph, required this.label, this.onTap, this.active = false, this.primary = false, this.badge});

  final Glyph glyph;
  final String label;
  final VoidCallback? onTap;
  final bool active;

  /// The module's main action: label in the accent colour.
  final bool primary;

  /// Small status dot (e.g. file loaded).
  final Color? badge;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final enabled = onTap != null;
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, pressed) => Container(
        constraints: BoxConstraints(minWidth: m.touch ? 76 : 64),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 7),
        decoration: BoxDecoration(
          color: active
              ? c.accent.withValues(alpha: c.dark ? 0.14 : 0.08)
              : pressed
                  ? c.pressed
                  : hover
                      ? c.hover
                      : null,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                GlyphIcon(
                  glyph,
                  size: 26,
                  filled: active,
                  disabled: !enabled,
                  color: active || primary
                      ? c.accent
                      : hover
                          ? c.text
                          : c.textDim,
                ),
                if (badge != null)
                  Positioned(
                    right: -3,
                    top: -1,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(color: badge, shape: BoxShape.circle, border: Border.all(color: c.ribbon, width: 2)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 12,
                  color: !enabled
                      ? c.textFaint
                      : active || primary
                          ? c.accent
                          : hover
                              ? c.text
                              : c.textDim,
                  fontWeight: active || primary ? FontWeight.w600 : FontWeight.w400,
                )),
          ],
        ),
      ),
    );
  }
}

/// Small ribbon option (radio item), stacked three to a column.
class RibbonOption extends StatelessWidget {
  const RibbonOption({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        width: 84,
        height: m.touch ? 24 : 22,
        margin: const EdgeInsets.only(bottom: 1),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: selected
              ? c.accent.withValues(alpha: c.dark ? 0.14 : 0.08)
              : hover
                  ? c.hover
                  : null,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(children: [
          Container(
            width: 12,
            height: 12,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: selected ? c.accent : c.textFaint, width: 1.2)),
            child: selected ? Container(width: 6, height: 6, decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle)) : null,
          ),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12, color: selected ? c.accent : hover ? c.text : c.textDim, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}
