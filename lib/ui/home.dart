/// Main window: ribbon, docked panels, workspace tabs, status bar.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'icons.dart';

import '../app_state.dart';
import '../core/models.dart';
import '../l10n/strings.dart';
import 'actions.dart';
import 'board_view.dart';
import 'cad_view.dart';
import 'check_view.dart';
import 'panels.dart';
import 'ribbon.dart';
import 'theme.dart';
import 'widgets.dart';

class HomeWindow extends StatelessWidget {
  const HomeWindow({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = Strings.of(context);
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
                  final narrow = box.maxWidth < 1100;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.showProject) ...[
                        SizedBox(width: narrow ? 220 : 240, child: ProjectPanel(state: state)),
                        VDivider(),
                      ],
                      Expanded(child: _Workspace(state: state)),
                      if (state.showInspector && !narrow) ...[
                        VDivider(),
                        SizedBox(width: 260, child: InspectorPanel(state: state)),
                      ],
                    ],
                  );
                }),
              ),
              _StatusBar(state: state, strings: s),
            ],
          ),
        ),
      ),
    );
  }
}

class _Workspace extends StatelessWidget {
  const _Workspace({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
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
          height: 32,
          decoration: BoxDecoration(color: c.chrome, border: Border(bottom: BorderSide(color: c.border))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (w, label, icon) in tabs)
                _DocTab(label: label, icon: icon, active: state.workspace == w, onTap: () => state.setWorkspace(w)),
            ],
          ),
        ),
        Expanded(
          child: switch (state.workspace) {
            Workspace.check => CheckView(state: state),
            Workspace.board => BoardView(state: state),
            Workspace.cad => CadView(state: state),
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
    return Hoverable(
      onTap: onTap,
      builder: (context, hover, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: active ? c.panel : hover ? c.hover : null,
          border: Border(
            top: BorderSide(color: active ? c.accent : const Color(0x00000000), width: 2),
            right: BorderSide(color: c.border),
          ),
        ),
        child: Row(children: [
          Icon(icon, size: 15, color: active ? c.accent : c.textDim),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12.5, color: active ? c.text : c.textDim)),
        ]),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state, required this.strings});

  final AppState state;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    final s = strings;
    final ng = state.report?.count(CheckCategory.ng);
    return Container(
      height: 24,
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
          Text('F5 ${s.t('btn_run')}   Ctrl+E ${s.t('btn_export_report')}   Ctrl+G ${s.t('btn_gen_cad')}',
              style: TextStyle(fontSize: 11.5, color: c.textFaint)),
          const SizedBox(width: 16),
          Text(languageNames[state.language]!, style: TextStyle(fontSize: 12, color: c.textDim)),
        ],
      ),
    );
  }
}
