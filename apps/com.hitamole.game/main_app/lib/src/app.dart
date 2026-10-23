import 'package:main_app_package/src/data/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_scope.dart';
import 'core/theme.dart';
import 'data/settings_controller.dart';
import 'data/stats_repository.dart';
import 'l10n/strings.dart';
import 'services/sound_service.dart';
import 'ui/screens/splash_screen.dart';

class HitAMoleApp extends StatelessWidget {
  final SettingsController settings;
  final StatsRepository stats;
  final SoundService sound;

  const HitAMoleApp({
    required this.settings,
    required this.stats,
    required this.sound,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AppScope(
      settings: settings,
      stats: stats,
      sound: sound,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final value = settings.value;
          return MaterialApp(
            title: 'Hit a Mole',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: value.themeMode,
            locale: value.language.locale,
            supportedLocales: AppStrings.supportedLocales,
            localizationsDelegates: const <LocalizationsDelegate<Object>>[
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const SplashScreen(),
          );
        },
      ),
    );
  }
}
