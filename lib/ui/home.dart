/// Main window: title bar with module tabs, the module's ribbon, the module
/// page and the status bar. Each ribbon tab owns exactly one page.
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
import 'files_page.dart';
import 'ribbon.dart';
import 'settings_page.dart';
import 'theme.dart';

class HomeWindow extends StatelessWidget {
  const HomeWindow({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final c = AppTheme.of(context);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f5): () => runCheck(context, state),
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): () => exportReport(context, state),
        const SingleActivator(LogicalKeyboardKey.keyG, control: true): () => exportCad(context, state),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (state.boardFullscreen) {
            state.setBoardFullscreen(false);
          } else if (state.settingsOpen) {
            state.closeSettings();
          }
        },
        const SingleActivator(LogicalKeyboardKey.f11): () {
          if (state.module == Module.board) state.setBoardFullscreen(!state.boardFullscreen);
        },
      },
      child: Focus(
        autofocus: true,
        child: state.settingsOpen
            ? SettingsScreen(state: state)
            : state.module == Module.board && state.boardFullscreen
            ? BoardView(state: state, immersive: true)
            : Container(
                color: c.window,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TitleBar(state: state),
                    Ribbon(state: state),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          final compact = LayoutSize.of(box.maxWidth) == LayoutSize.compact;
                          return switch (state.module) {
                            Module.files => FilesPage(state: state),
                            Module.check => CheckView(state: state, cards: compact),
                            Module.cad => CadView(state: state, compact: compact),
                            Module.board => BoardView(state: state),
                          };
                        },
                      ),
                    ),
                    _StatusBar(state: state),
                  ],
                ),
              ),
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
    final files = [state.bom, state.stationA, state.stationB, state.coords].where((f) => f != null).length;
    return Container(
      height: m.statusBar,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.chrome,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: state.report == null
                  ? c.textFaint
                  : (ng ?? 0) > 0
                  ? c.ng
                  : c.pass,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.t(state.statusKey, state.statusArgs),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: c.textDim),
            ),
          ),
          Text('${s.t('mod_files')} $files/4', style: TextStyle(fontSize: 11.5, color: c.textFaint)),
          if (wide) ...[
            const SizedBox(width: 18),
            Text(
              'F5 ${s.t('btn_run')}    Ctrl+E ${s.t('btn_export_report')}    Ctrl+G ${s.t('btn_gen_cad')}',
              style: TextStyle(fontSize: 11.5, color: c.textFaint),
            ),
          ],
        ],
      ),
    );
  }
}
