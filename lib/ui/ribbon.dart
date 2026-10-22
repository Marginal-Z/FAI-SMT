/// Top ribbon: menu tabs plus grouped command buttons.
library;

import 'package:flutter/widgets.dart';
import 'icons.dart';

import '../app_state.dart';
import '../core/parsers.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'dialogs.dart';
import 'theme.dart';
import 'widgets.dart';

class Ribbon extends StatelessWidget {
  const Ribbon({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
    final tabs = ['tab_home', 'tab_rules', 'tab_output', 'tab_view', 'tab_help'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Menu-tab strip
        Container(
          height: 34,
          color: c.chrome,
          child: Row(
            children: [
              const SizedBox(width: 10),
              const _AppMark(),
              const SizedBox(width: 8),
              Text(s.t('app_name'), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: c.text, letterSpacing: 0.3)),
              const SizedBox(width: 18),
              for (var i = 0; i < tabs.length; i++)
                _MenuTab(label: s.t(tabs[i]), active: state.ribbonTab == i, onTap: () => state.setRibbonTab(i)),
              const Spacer(),
              Text(s.t('app_subtitle'), style: TextStyle(fontSize: 12, color: c.textFaint)),
              const SizedBox(width: 12),
            ],
          ),
        ),
        // Command area
        Container(
          height: 96,
          decoration: BoxDecoration(color: c.ribbon, border: Border(bottom: BorderSide(color: c.border))),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: switch (state.ribbonTab) {
                0 => _home(context, s, c),
                1 => _rules(context, s),
                2 => _output(context, s),
                3 => _view(context, s),
                _ => _help(context, s),
              },
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _home(BuildContext context, Strings s, AppColors c) => [
        RibbonGroup(label: s.t('grp_import'), children: [
          RibbonButton(
            icon: Ic.treeStructure,
            label: s.t('btn_bom'),
            badge: state.bom != null ? c.pass : null,
            onTap: () => importFile(context, state, InputKind.bom),
          ),
          RibbonButton(
            icon: Ic.squaresFour,
            label: s.t('btn_station_a'),
            badge: state.stationA != null ? c.pass : null,
            onTap: () => importFile(context, state, InputKind.stationA),
          ),
          RibbonButton(
            icon: Ic.gridFour,
            label: s.t('btn_station_b'),
            badge: state.stationB != null ? c.pass : null,
            onTap: () => importFile(context, state, InputKind.stationB),
          ),
          RibbonButton(
            icon: Ic.crosshair,
            label: s.t('btn_coord'),
            badge: state.coords != null ? c.pass : null,
            onTap: () => importFile(context, state, InputKind.coords),
          ),
        ]),
        RibbonGroup(label: s.t('grp_check'), children: [
          RibbonButton(icon: Ic.listChecks, label: s.t('btn_run'), onTap: () => runCheck(context, state)),
          RibbonButton(icon: Ic.broom, label: s.t('btn_clear'), onTap: state.clearAll),
        ]),
        RibbonGroup(label: s.t('grp_export'), children: [
          RibbonButton(
            icon: Ic.fileXls,
            label: s.t('btn_export_report'),
            onTap: state.report == null ? null : () => exportReport(context, state),
          ),
          RibbonButton(
            icon: Ic.circuitry,
            label: s.t('btn_gen_cad'),
            onTap: state.report == null || state.coords == null ? null : () => exportCad(context, state),
          ),
        ]),
      ];

  List<Widget> _rules(BuildContext context, Strings s) => [
        RibbonGroup(label: s.t('grp_rules'), children: [
          RibbonButton(icon: Ic.prohibit, label: s.t('btn_exclusion'), onTap: () => showRulesDialog(context, state, 0)),
          RibbonButton(icon: Ic.arrowsLeftRight, label: s.t('btn_substitutes'), onTap: () => showRulesDialog(context, state, 1)),
          RibbonButton(icon: Ic.gear, label: s.t('btn_general'), onTap: () => showRulesDialog(context, state, 2)),
        ]),
        RibbonGroup(label: s.t('grp_coord_import'), children: [
          for (final (u, key, icon) in [
            (CoordUnit.auto, 'unit_auto', Ic.magicWand),
            (CoordUnit.mm, 'unit_mm', Ic.ruler),
            (CoordUnit.mil, 'unit_mil', Ic.ruler),
            (CoordUnit.inch, 'unit_inch', Ic.ruler),
          ])
            RibbonButton(
              icon: icon,
              label: s.t(key),
              active: state.settings.coordUnit == u,
              onTap: () {
                try {
                  state.setCoordUnit(u);
                } catch (e) {
                  showError(context, e);
                }
              },
            ),
        ]),
      ];

  List<Widget> _output(BuildContext context, Strings s) => [
        RibbonGroup(label: s.t('grp_cad'), children: [
          RibbonButton(icon: Ic.textColumns, label: s.t('btn_cad_template'), onTap: () => showCadTemplateDialog(context, state)),
          RibbonButton(icon: Ic.eye, label: s.t('ws_cad'), onTap: () => state.setWorkspace(Workspace.cad)),
          RibbonButton(
            icon: Ic.circuitry,
            label: s.t('btn_gen_cad'),
            onTap: state.report == null || state.coords == null ? null : () => exportCad(context, state),
          ),
        ]),
        RibbonGroup(label: s.t('grp_export'), children: [
          RibbonButton(
            icon: Ic.fileXls,
            label: s.t('btn_export_report'),
            onTap: state.report == null ? null : () => exportReport(context, state),
          ),
        ]),
      ];

  List<Widget> _view(BuildContext context, Strings s) => [
        RibbonGroup(label: s.t('grp_language'), children: [
          for (final lang in supportedLanguages)
            RibbonButton(
              icon: Ic.translate,
              label: languageNames[lang]!,
              active: state.language == lang,
              onTap: () => state.setLanguage(lang),
            ),
        ]),
        RibbonGroup(label: s.t('grp_theme'), children: [
          RibbonButton(icon: Ic.moon, label: s.t('btn_dark'), active: state.dark, onTap: () => state.setDark(true)),
          RibbonButton(icon: Ic.sun, label: s.t('btn_light'), active: !state.dark, onTap: () => state.setDark(false)),
        ]),
        RibbonGroup(label: s.t('grp_panels'), children: [
          RibbonButton(icon: Ic.sidebarSimple, label: s.t('btn_files_panel'), active: state.showProject, onTap: () => state.togglePanel(project: true)),
          RibbonButton(icon: Ic.listBullets, label: s.t('btn_inspector'), active: state.showInspector, onTap: () => state.togglePanel(inspector: true)),
        ]),
        RibbonGroup(label: s.t('grp_workspace'), children: [
          RibbonButton(icon: Ic.table, label: s.t('ws_check'), active: state.workspace == Workspace.check, onTap: () => state.setWorkspace(Workspace.check)),
          RibbonButton(icon: Ic.cpu, label: s.t('ws_board'), active: state.workspace == Workspace.board, onTap: () => state.setWorkspace(Workspace.board)),
          RibbonButton(icon: Ic.codeSimple, label: s.t('ws_cad'), active: state.workspace == Workspace.cad, onTap: () => state.setWorkspace(Workspace.cad)),
        ]),
      ];

  List<Widget> _help(BuildContext context, Strings s) => [
        RibbonGroup(label: s.t('grp_about'), children: [
          RibbonButton(icon: Ic.info, label: s.t('btn_about'), onTap: () => showAboutDialog(context, state)),
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
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
      decoration: BoxDecoration(border: Border(right: BorderSide(color: c.border))),
      child: Column(
        children: [
          Expanded(
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final ch in children) Padding(padding: const EdgeInsets.symmetric(horizontal: 1), child: ch),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(label, style: TextStyle(fontSize: 11, color: c.textFaint)),
          ),
        ],
      ),
    );
  }
}

class _MenuTab extends StatelessWidget {
  const _MenuTab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        margin: const EdgeInsets.only(top: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.ribbon : hover ? c.hover : null,
          border: active ? Border(top: BorderSide(color: c.accent, width: 2), left: BorderSide(color: c.border), right: BorderSide(color: c.border)) : null,
        ),
        child: Text(label, style: TextStyle(fontSize: 13, color: active ? c.text : c.textDim, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
      ),
    );
  }
}

/// Small square logo drawn in code: a chip outline with pins.
class _AppMark extends StatelessWidget {
  const _AppMark();

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return CustomPaint(size: const Size(18, 18), painter: _MarkPainter(c.accent));
  }
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = color;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(4, 4, 10, 10), const Radius.circular(1.5)), p);
    final pin = Paint()
      ..color = color
      ..strokeWidth = 1.4;
    for (final t in [6.5, 9.0, 11.5]) {
      canvas.drawLine(Offset(t, 0.5), Offset(t, 3), pin);
      canvas.drawLine(Offset(t, 15), Offset(t, 17.5), pin);
      canvas.drawLine(Offset(0.5, t), Offset(3, t), pin);
      canvas.drawLine(Offset(15, t), Offset(17.5, t), pin);
    }
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.color != color;
}
