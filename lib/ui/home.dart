/// Main window: header with the module navigation, the module page (or
/// Settings) and the footer, on the design's mesh background.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import 'actions.dart';
import 'board_view.dart';
import 'cad_view.dart';
import 'check_view.dart';
import 'files_page.dart';
import 'design.dart';
import 'settings_page.dart';
import 'shell.dart';
import 'theme.dart';
import 'tour.dart';

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
        child: Stack(
          children: [
            Positioned.fill(child: _body(c)),
            if (state.tourStep != null) Positioned.fill(child: TourOverlay(state: state)),
          ],
        ),
      ),
    );
  }

  Widget _body(AppColors c) {
    if (state.module == Module.board && state.boardFullscreen && !state.settingsOpen) {
      return MeshBackground(child: BoardView(state: state, immersive: true));
    }
    return MeshBackground(child: LayoutBuilder(builder: (context, box) => box.maxWidth < 600 ? _phone() : _desktop()));
  }

  Widget _page() => state.settingsOpen
      ? SettingsScreen(state: state)
      : LayoutBuilder(
          builder: (context, box) {
            final compact = LayoutSize.of(box.maxWidth) == LayoutSize.compact;
            return switch (state.module) {
              Module.files => FilesPage(state: state),
              Module.check => CheckView(state: state, cards: compact),
              Module.cad => CadView(state: state, compact: compact),
              Module.board => BoardView(state: state),
            };
          },
        );

  /// Phones: compact top bar, the page, bottom navigation.
  Widget _phone() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      PhoneHeader(state: state),
      Expanded(child: _page()),
      PhoneNavBar(state: state),
    ],
  );

  Widget _desktop() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppHeader(state: state),
        Expanded(child: _page()),
        AppFooter(state: state),
      ],
    );
  }
}
