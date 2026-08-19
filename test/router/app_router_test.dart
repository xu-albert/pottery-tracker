import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pottery_tracker/features/auth/screens/sign_in_screen.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/splash_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/router/app_router.dart';

import '../helpers/firebase_mocks.dart';

ProviderContainer _container({
  required AuthStatus status,
  bool deviceLocked = false,
}) {
  return ProviderContainer(
    overrides: [
      authProvider.overrideWith(
        (ref) => AuthNotifier.withState(AuthState(status: status)),
      ),
      // The router consults the read-only lock, which is derived from sync
      // state and would otherwise pull in the database. Routing is what these
      // tests are about, so the lock is supplied directly.
      deviceLockedProvider.overrideWithValue(deviceLocked),
    ],
  );
}

/// Pumps the real [routerProvider] inside [container] and returns the
/// resulting [GoRouter] so tests can inspect where the redirect landed.
///
/// The destination screens are real widgets that read
/// `AppLocalizations.of(context)`, so this needs the full
/// localization delegate set, matching `test/helpers/test_helpers.dart`.
Future<GoRouter> _pumpRouter(
  WidgetTester tester,
  ProviderContainer container,
) async {
  final router = container.read(routerProvider);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
      ),
    ),
  );
  await tester.pump();
  return router;
}

void main() {
  setUpAll(setupFirebaseCoreMocks);

  group('splashCompleteProvider', () {
    test('defaults to false', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(splashCompleteProvider), isFalse);
    });
  });

  group('app entry transition', () {
    testWidgets('the app fades in rather than cutting from the splash', (
      tester,
    ) async {
      final container = _container(status: AuthStatus.unauthenticated);
      addTearDown(container.dispose);

      final router = container.read(routerProvider);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en')],
          ),
        ),
      );
      await tester.pump();

      // Sign-out still swaps routes under the overlay, and after launch it is
      // a plain navigation, so the destination keeps its own transition.
      expect(
        find.ancestor(
          of: find.byType(SignInScreen),
          matching: find.byType(FadeTransition),
        ),
        findsWidgets,
        reason: 'destination should fade in, not cut',
      );

      await tester.pumpAndSettle();
    });
  });

  group('router redirect', () {
    // These assert where the redirect lands, not that the destination renders.
    Future<String> pathFor(WidgetTester tester, AuthStatus status) async {
      final container = _container(status: status);
      addTearDown(container.dispose);
      final router = await _pumpRouter(tester, container);
      // The album subtree reaches for the database, Firebase Storage and the
      // sync stack, all of which `main()` provides before `runApp` and a test
      // does not. Its build failure is irrelevant here: the redirect has
      // already chosen the destination, which is what these tests assert.
      tester.takeException();
      return router.routerDelegate.currentConfiguration.uri.path;
    }

    testWidgets('stays put while auth is still resolving', (tester) async {
      // The splash overlay covers the app during this window, so the router has
      // no holding route to sit on — and the album underneath gets a head start
      // on its query instead of being built later.
      expect(await pathFor(tester, AuthStatus.unknown), '/');
    });

    testWidgets('sends a signed-out user to sign-in once auth resolves', (
      tester,
    ) async {
      expect(await pathFor(tester, AuthStatus.unauthenticated), '/sign-in');
    });

    testWidgets('keeps a signed-in user on the album', (tester) async {
      expect(await pathFor(tester, AuthStatus.authenticated), '/');
    });
  });

  group('read-only lock redirect', () {
    testWidgets('a locked device cannot reach a screen that writes', (
      tester,
    ) async {
      final container = _container(
        status: AuthStatus.authenticated,
        deviceLocked: true,
      );
      addTearDown(container.dispose);

      final router = await _pumpRouter(tester, container);
      await tester.pumpAndSettle();

      expect(
        router.state.matchedLocation,
        '/device-locked',
        reason:
            'the lock is enforced at the router so no writable route — the '
            'album, the create flow, the piece editor, the material screens — '
            'is reachable while another account owns this device',
      );
    });
  });
}
