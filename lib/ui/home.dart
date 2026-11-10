/// Main window: header, the BOM check page (or Settings) and the footer.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../app_state.dart';
import 'actions.dart';
import 'check_view.dart';
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
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (state.settingsOpen) state.closeSettings();
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
    return MeshBackground(child: Builder(builder: (context) => isPhoneLayout(context) ? _phone(context) : _desktop()));
  }

  Widget _page() => state.settingsOpen
      ? SettingsScreen(state: state)
      : LayoutBuilder(
          builder: (context, box) {
            // The comparison table needs room for part numbers and verdicts.
            final compact = box.maxWidth < 1000;
            return CheckView(state: state, cards: compact);
          },
        );

  /// Phones: compact top bar, the page running under the floating glass tab
  /// bar (pages keep [bottomInset] free at their end).
  Widget _phone(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PhoneHeader(state: state),
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: MediaQuery(
                  data: mq.copyWith(padding: mq.padding.copyWith(bottom: phoneTabBarInset)),
                  child: _page(),
                ),
              ),
              Positioned(left: 0, right: 0, bottom: 0, child: PhoneNavBar(state: state)),
            ],
          ),
        ),
      ],
    );
  }

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
