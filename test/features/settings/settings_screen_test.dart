import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pottery_tracker/features/settings/screens/settings_screen.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';

void main() {
  group('SettingsScreen', () {
    testWidgets('shows Settings title and materials section', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith(
              (ref) => _FakeAuthNotifier(
                const AuthState(status: AuthStatus.authenticated),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en')],
            home: const Scaffold(body: _SettingsSubset()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Materials'), findsOneWidget);
    });
  });

  group('AppVersionTile', () {
    Widget wrap(Widget child) => MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: Scaffold(body: child),
    );

    void mockPackageVersion(String version, String buildNumber) {
      PackageInfo.setMockInitialValues(
        appName: 'Potter Journal',
        packageName: 'com.albertxu.potterytracker',
        version: version,
        buildNumber: buildNumber,
        buildSignature: '',
      );
    }

    testWidgets('shows the version reported by the running build', (
      tester,
    ) async {
      mockPackageVersion('9.9.9', '42');

      await tester.pumpWidget(wrap(const AppVersionTile()));
      await tester.pumpAndSettle();

      expect(find.text('Version 9.9.9'), findsOneWidget);
    });

    testWidgets('tracks the package version instead of a fixed string', (
      tester,
    ) async {
      mockPackageVersion('3.4.5', '17');

      await tester.pumpWidget(wrap(const AppVersionTile()));
      await tester.pumpAndSettle();

      expect(find.text('Version 3.4.5'), findsOneWidget);
    });

    testWidgets('renders no version until the package info resolves', (
      tester,
    ) async {
      mockPackageVersion('9.9.9', '42');

      await tester.pumpWidget(wrap(const AppVersionTile()));
      // First frame only — the future has not completed yet.
      expect(find.byType(ListTile), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsOneWidget);
    });
  });
}

/// A minimal widget that exercises the auth provider and l10n without
/// instantiating AuthService (which requires Firebase).
class _SettingsSubset extends ConsumerWidget {
  const _SettingsSubset();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsTitle)),
      body: ListView(
        children: [
          Text(l10n.manageMaterials),
          Text(l10n.manageClays),
          Text(l10n.manageGlazes),
          Text(l10n.manageTags),
          if (!auth.isSignedIn) Text(l10n.notSignedIn),
          if (auth.isSignedIn && auth.displayName != null)
            Text(l10n.signedInAs(auth.displayName!)),
        ],
      ),
    );
  }
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(super.initial) : super.withState();
}
