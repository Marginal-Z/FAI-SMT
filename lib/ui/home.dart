/// Main window: ribbon, docked panels, workspace tabs, status bar.
///
/// Layout adapts to width ([LayoutSize]): desktop docks both side panels;
/// landscape tablets dock the project panel and float the inspector; portrait
/// tablets open the project panel as a drawer and show results as cards.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'board_view.dart';
import 'cad_view.dart';
import 'check_view.dart';
import 'icons.dart';
import 'panels.dart';
import 'ribbon.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeWindow extends StatefulWidget {
  const HomeWindow({super.key, required this.state});

  final AppState state;

  @override
  State<HomeWindow> createState() => _HomeWindowState();
}

class _HomeWindowState extends State<HomeWindow> {
  bool _drawer = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final c = AppTheme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): () => runCheck(context, state),
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): () => exportReport(context, state),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () => exportCad(context, state),
      },
      child: Focus(
        autofocus: true,
        child: Container(
          color: c.window,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Ribbon(state: state),
              Expanded(
                child: LayoutBuilder(builder: (context, box) {
                  final size = LayoutSize.of(box.maxWidth);
                  final dockProject = state.showProject && size != LayoutSize.compact;
                  final dockInspector = state.showInspector && size == LayoutSize.wide;
                  final floatInspector = state.showInspector && !dockInspector && state.selected != null;
                  return Stack(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (dockProject) ...[
                            SizedBox(width: size == LayoutSize.wide ? 256 : 236, child: ProjectPanel(state: state)),
                            const VDivider(),
                          ],
                          Expanded(
                            child: _Workspace(
                              state: state,
                              size: size,
                              onOpenProject: size == LayoutSize.compact ? () => setState(() => _drawer = true) : null,
                            ),
                          ),
                          if (dockInspector) ...[
                            const VDivider(),
                            SizedBox(width: 280, child: InspectorPanel(state: state)),
                          ],
                        ],
                      ),
                      if (floatInspector)
                        Positioned.fill(
                          child: OverlayPanel(
                            width: 360,
                            onClose: () => state.select(null),
                            child: InspectorPanel(state: state, onClose: () => state.select(null)),
                          ),
                        ),
                      if (_drawer && size == LayoutSize.compact)
                        Positioned.fill(
                          child: OverlayPanel(
                            left: true,
                            width: 320,
                            onClose: () => setState(() => _drawer = false),
                            child: ProjectPanel(state: state),
                          ),
                        ),
                    ],
                  );
                }),
              ),
              _StatusBar(state: state),
            ],
          ),
        ),
      ),
    );
  }
}

class _Workspace extends StatelessWidget {
  const _Workspace({required this.state, required this.size, this.onOpenProject});

  final AppState state;
  final LayoutSize size;
  final VoidCallback? onOpenProject;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final s = Strings.of(context);
    final tabs = [
      (Workspace.check, s.t('ws_check'), Ic.table),
      (Workspace.board, s.t('ws_board'), Ic.cpu),
      (Workspace.cad, s.t('ws_cad'), Ic.codeSimple),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: m.docTabs,
          decoration: BoxDecoration(color: c.chrome, border: Border(bottom: BorderSide(color: c.border))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (onOpenProject != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(border: Border(right: BorderSide(color: c.border))),
                  child: Center(child: IconBtn(icon: Ic.sidebarSimple, tooltip: s.t('btn_files_panel'), onTap: onOpenProject)),
                ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final (w, label, icon) in tabs)
                        _DocTab(label: label, icon: icon, active: state.workspace == w, onTap: () => state.setWorkspace(w)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: switch (state.workspace) {
            Workspace.check => CheckView(state: state, cards: size == LayoutSize.compact),
            Workspace.board => BoardView(state: state),
            Workspace.cad => CadView(state: state, compact: size == LayoutSize.compact),
          },
        ),
      ],
    );
  }
}

/// Document-style tab (like open drawings in a CAD program).
class _DocTab extends StatelessWidget {
  const _DocTab({required this.label, required this.icon, required this.active, required this.onTap});

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        constraints: BoxConstraints(minHeight: m.docTabs),
        padding: EdgeInsets.symmetric(horizontal: m.touch ? 18 : 14),
        decoration: BoxDecoration(
          color: active ? c.panel : hover ? c.hover : null,
          border: Border(
            top: BorderSide(color: active ? c.accent : const Color(0x00000000), width: 2),
            right: BorderSide(color: c.border),
          ),
        ),
        child: Row(children: [
          Icon(icon, size: 15, color: active ? c.accent : c.textDim),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(fontSize: 12.5, color: active ? c.text : c.textDim, fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final m = Metrics.of(context);
    final s = Strings.of(context);
    final ng = state.report?.count(CheckCategory.ng);
    final wide = MediaQuery.sizeOf(context).width >= 1100 && !m.touch;
    return Container(
      height: m.statusBar,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: c.chrome, border: Border(top: BorderSide(color: c.border))),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.report == null ? c.textFaint : (ng ?? 0) > 0 ? c.ng : c.pass,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(s.t(state.statusKey, state.statusArgs),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textDim)),
          ),
          if (wide)
            Text('F5 ${s.t('btn_run')}    Ctrl+E ${s.t('btn_export_report')}    Ctrl+G ${s.t('btn_gen_cad')}',
                style: TextStyle(fontSize: 11.5, color: c.textFaint)),
        ],
      ),
    );
  }
}
