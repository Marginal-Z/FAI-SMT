import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'core/settings.dart';
import 'l10n/strings.dart';
import 'ui/home.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = (await getApplicationSupportDirectory()).path;
  final settings = await AppSettings.load(dir);
  runApp(SmtFaiApp(state: AppState(settings, dir)));
}

class SmtFaiApp extends StatelessWidget {
  const SmtFaiApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final colors = state.dark ? AppColors.darkTheme : AppColors.lightTheme;
        final strings = Strings(state.language);
        return WidgetsApp(
          title: 'SMT-FAI',
          color: colors.accent,
          debugShowCheckedModeBanner: false,
          locale: Locale(state.language),
          supportedLocales: [for (final l in supportedLanguages) Locale(l)],
          localizationsDelegates: const [
            GlobalWidgetsLocalizations.delegate,
          ],
          builder: (context, child) => AppTheme(
            colors: colors,
            child: StringsScope(
              strings: strings,
              child: DefaultTextStyle(style: baseTextStyle(colors), child: child!),
            ),
          ),
          home: _Root(state: state),
          pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
              PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
        );
      },
    );
  }
}

class _Root extends StatelessWidget {
  const _Root({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) => HomeWindow(state: state);
}
