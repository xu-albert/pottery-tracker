import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pottery_tracker/app.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/splash_provider.dart';
import 'package:pottery_tracker/router/app_router.dart';
import 'package:pottery_tracker/widgets/vase_logo.dart';

import '../helpers/firebase_mocks.dart';

ProviderContainer _container({
  required AuthStatus status,
  required bool splashComplete,
}) {
  return ProviderContainer(
    overrides: [
      authProvider.overrideWith(
        (ref) => AuthNotifier.withState(AuthState(status: status)),
      ),
      splashCompleteProvider.overrideWith((ref) => splashComplete),
    ],
  );
}

/// Pumps the real [routerProvider] inside [container] and returns the
/// resulting [GoRouter] so tests can inspect where the redirect landed.
///
/// The destination screens (SignInScreen, SplashScreen, ...) are real
/// widgets that read `AppLocalizations.of(context)`, so this needs the full
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

  group('router redirect', () {
    testWidgets('holds on /splash while auth is unknown', (tester) async {
      final container = _container(
        status: AuthStatus.unknown,
        splashComplete: true,
      );
      addTearDown(container.dispose);

      final router = await _pumpRouter(tester, container);

      expect(router.routerDelegate.currentConfiguration.uri.path, '/splash');
    });

    testWidgets('holds on /splash while the animation is unfinished', (
      tester,
    ) async {
      final container = _container(
        status: AuthStatus.authenticated,
        splashComplete: false,
      );
      addTearDown(container.dispose);

      final router = await _pumpRouter(tester, container);

      expect(router.routerDelegate.currentConfiguration.uri.path, '/splash');
    });

    testWidgets('leaves /splash once both conditions are met', (tester) async {
      final container = _container(
        status: AuthStatus.unauthenticated,
        splashComplete: true,
      );
      addTearDown(container.dispose);

      final router = await _pumpRouter(tester, container);

      expect(router.routerDelegate.currentConfiguration.uri.path, '/sign-in');
    });

    testWidgets('preserves the in-flight splash animation state across a '
        'routerProvider rebuild', (tester) async {
      // Regression test for a bug where routerProvider (a plain Provider
      // that watches authProvider and splashCompleteProvider) minted a
      // brand-new GoRouter -- with a fresh default GlobalKey<NavigatorState>
      // -- every time either dependency changed. That discarded and
      // remounted the whole Navigator subtree, restarting SplashScreen's
      // AnimatedVaseLogo draw-on animation from zero.
      //
      // This test mounts the real, reactive `PotteryTrackerApp` (the same
      // widget main.dart uses, which does `ref.watch(routerProvider)` in
      // its build method) so that flipping a watched provider actually
      // triggers a routerProvider rebuild while the tree is mounted --
      // unlike the other tests in this file, which read the router once
      // via a fixed provider override and never let it change.
      final container = _container(
        status: AuthStatus.unknown,
        splashComplete: false,
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const PotteryTrackerApp(),
        ),
      );
      await tester.pump();

      // Advance partway into the 900ms draw-on animation.
      await tester.pump(const Duration(milliseconds: 400));

      final logoStateBefore = tester.state(find.byType(AnimatedVaseLogo));

      // Flip splashCompleteProvider while auth is still unknown. The
      // redirect destination doesn't change -- the router still parks on
      // /splash -- but this is exactly the trigger that used to make
      // routerProvider recompute and hand back a brand-new
      // GoRouter/Navigator mid-animation.
      container.read(splashCompleteProvider.notifier).state = true;
      await tester.pump();

      final logoStateAfter = tester.state(find.byType(AnimatedVaseLogo));

      expect(
        identical(logoStateBefore, logoStateAfter),
        isTrue,
        reason:
            'AnimatedVaseLogo State must survive a routerProvider '
            'rebuild, otherwise the draw-on animation restarts from '
            'zero on every launch',
      );
    });
  });
}
