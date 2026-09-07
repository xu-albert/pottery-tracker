import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// The smallest app that can host a screen shown *before* the real one.
///
/// The recovery and launch-failure screens run without a database, so they
/// cannot live inside `PotteryTrackerApp`, whose providers assume one. This
/// gives them the theme and strings and nothing else — no router, no
/// providers, no splash.
class PreLaunchApp extends StatelessWidget {
  const PreLaunchApp({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Potter Journal',
      theme: AppTheme.light,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: child,
    );
  }
}
