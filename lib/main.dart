import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path_provider/path_provider.dart';

import 'app_state.dart';
import 'core/settings.dart';
import 'l10n/strings.dart';
import 'ui/home.dart';
import 'ui/theme.dart';
import 'ui/ui_scale.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = (await getApplicationSupportDirectory()).path;
  final settings = await AppSettings.load(dir);
  final state = AppState(settings, dir);
  // First launch: walk the user through the main steps.
  if (!settings.tourDone) state.tourStep = 0;
  runApp(SmtFaiApp(state: state));
  if (settings.autoUpdate) state.checkForUpdates(silent: true);
}

bool get _isTouchPlatform => Platform.isAndroid || Platform.isIOS;

class SmtFaiApp extends StatelessWidget {
  const SmtFaiApp({super.key, required this.state, this.touch});

  final AppState state;

  /// Forces touch sizing (tests); defaults to the platform.
  final bool? touch;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final strings = Strings(state.language);
        return WidgetsApp(
          title: 'SMT-FAI',
          color: AppColors.darkTheme.accent,
          debugShowCheckedModeBanner: false,
          locale: Locale(state.language),
          supportedLocales: [for (final l in supportedLanguages) Locale(l)],
          localizationsDelegates: const [GlobalWidgetsLocalizations.delegate],
          builder: (context, child) {
            final dark = switch (state.theme) {
              ThemePref.dark => true,
              ThemePref.light => false,
              ThemePref.system => MediaQuery.platformBrightnessOf(context) == Brightness.dark,
            };
            final colors = state.settings.themeStyle == ThemeStyle.industrial
                ? (dark ? AppColors.industrialDark : AppColors.industrialLight)
                : (dark ? AppColors.darkTheme : AppColors.lightTheme);
            if (Platform.isAndroid) {
              SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
                statusBarColor: colors.chrome,
                statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
                systemNavigationBarColor: colors.chrome,
                systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
              ));
            }
            return AppTheme(
              colors: colors,
              child: MetricsScope(
                metrics: Metrics(touch: touch ?? _isTouchPlatform),
                child: StringsScope(
                  strings: strings,
                  child: DefaultTextStyle(
                    style: baseTextStyle(colors),
                    child: ColoredBox(
                      color: colors.chrome,
                      child: SafeArea(child: UiScale(setting: state.settings.uiScale, child: child!)),
                    ),
                  ),
                ),
              ),
            );
          },
          home: HomeWindow(state: state),
          pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) =>
              PageRouteBuilder<T>(settings: settings, pageBuilder: (context, _, _) => builder(context)),
        );
      },
    );
  }
}
