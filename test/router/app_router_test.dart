import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pottery_tracker/features/auth/screens/device_locked_screen.dart';
import 'package:pottery_tracker/features/auth/screens/sign_in_screen.dart';
import 'package:pottery_tracker/features/shell/screens/shell_screen.dart';
import 'package:pottery_tracker/features/shell/screens/starting_screen.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/splash_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/router/app_router.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/firebase_mocks.dart';

/// An [AuthNotifier] whose state the test drives, standing in for the moment
/// `_init` finishes resolving.
class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(super.initial) : super.withState();

  void set(AuthState next) => state = next;
}

ProviderContainer _container({
  required AuthStatus status,
  bool deviceLocked = false,
  bool deviceStamped = false,
}) {
  return ProviderContainer(
    overrides: [
      authProvider.overrideWith(
        (ref) => AuthNotifier.withState(AuthState(status: status)),
      ),
      // The router consults the read-only lock and whether the device is
      // claimed at all; both are derived from persisted state and would
      // otherwise pull in the database. Routing is what these tests are
      // about, so they are supplied directly.
      deviceLockedProvider.overrideWithValue(deviceLocked),
      deviceStampedProvider.overrideWithValue(deviceStamped),
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

  setUp(() => SharedPreferences.setMockInitialValues({}));

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
      // On a device nobody has claimed there is nothing the album could be
      // wrong about, so it gets a head start on its query under the splash
      // instead of being built later.
      expect(await pathFor(tester, AuthStatus.unknown), '/');
    });

    testWidgets('holds instead, on a device an account already claims', (
      tester,
    ) async {
      final container = _container(
        status: AuthStatus.unknown,
        deviceStamped: true,
      );
      addTearDown(container.dispose);
      final router = await _pumpRouter(tester, container);

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        '/starting',
        reason:
            'a session-less state is both the owner offline and a refused '
            'account relaunching, so until auth answers the album must not '
            'mount and run the owner\'s query on a device that may be refused',
      );
      expect(find.byType(StartingScreen), findsOneWidget);
      expect(
        find.byType(DeviceLockedScreen),
        findsNothing,
        reason:
            'and the owner opening the app offline must not be told their own '
            'pottery belongs to somebody else while the answer is still '
            'unknown',
      );
    });

    testWidgets('the hold lets go as soon as auth resolves', (tester) async {
      final auth = _TestAuthNotifier(
        const AuthState(status: AuthStatus.unknown),
      );
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith((ref) => auth),
          deviceLockedProvider.overrideWithValue(false),
          deviceStampedProvider.overrideWithValue(true),
        ],
      );
      addTearDown(container.dispose);

      // `routerProvider` mints a fresh `GoRouter` when auth changes, so this
      // watches it the way `PotteryTrackerApp` does.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) => MaterialApp.router(
              routerConfig: ref.watch(routerProvider),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en')],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        container
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        '/starting',
      );

      auth.set(const AuthState(status: AuthStatus.authenticated, uid: 'a'));
      await tester.pump();
      // The album subtree reaches for the database and the sync stack, which a
      // test does not provide; its build failure is beside the point here.
      tester.takeException();

      expect(
        container
            .read(routerProvider)
            .routerDelegate
            .currentConfiguration
            .uri
            .path,
        '/',
        reason: 'the hold is for the unknown window only, not a second lock',
      );
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

    testWidgets('every route that can write is turned back at the lock', (
      tester,
    ) async {
      final container = _container(
        status: AuthStatus.authenticated,
        deviceLocked: true,
      );
      addTearDown(container.dispose);

      final router = await _pumpRouter(tester, container);
      await tester.pumpAndSettle();

      // Landing on the lock is not enough on its own: the ruling is that a
      // refused account cannot reach a write surface *at all*, so each one is
      // asked for by name. Anything a future route adds has to be added here.
      const writable = <String>[
        '/', // the album, which archives and deletes
        '/create', // the create flow
        '/piece/piece-a', // the piece editor
        '/settings', // sign-out, erase, delete account
        '/settings/clays',
        '/settings/glazes',
        '/settings/tags',
      ];

      for (final route in writable) {
        router.go(route);
        await tester.pumpAndSettle();

        expect(
          router.state.matchedLocation,
          '/device-locked',
          reason: '$route must not be reachable on a contested device',
        );
        expect(
          find.byType(DeviceLockedScreen),
          findsOneWidget,
          reason: 'and the lock screen is what the user is left looking at',
        );
      }
    });

    testWidgets('a refusal is recorded even though the shell never mounts', (
      tester,
    ) async {
      // The primary refusal: the device is stamped for A, B signs in, and the
      // stamp sends B straight to the lock screen. Nothing mounts the shell on
      // that route, so `SyncNotifier` is never built and no claim is ever
      // attempted — the refusal has to be recorded from the lock decision
      // itself or it is not recorded at all.
      SharedPreferences.setMockInitialValues({
        SyncService.localDataOwnerKey: 'account-a',
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier.withState(
              const AuthState(
                status: AuthStatus.authenticated,
                uid: 'account-b',
              ),
            ),
          ),
          localDataOwnerProvider.overrideWith((ref) => 'account-a'),
        ],
      );
      addTearDown(container.dispose);

      final router = await _pumpRouter(tester, container);
      await tester.pumpAndSettle();

      expect(router.state.matchedLocation, '/device-locked');
      expect(
        find.byType(ShellScreen),
        findsNothing,
        reason:
            'the shell is what constructs SyncNotifier, and it never mounts '
            'on the lock screen — so nothing on the sync path can be relied '
            'on to record the refusal',
      );

      // The recorder records off the build, so give it its turn.
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(SyncService.deviceContestedKey), isTrue);

      // Force-quit and relaunch offline: `AuthNotifier._init` cannot verify
      // the token, so it comes back session-less. Seeded from preferences
      // exactly as `main` seeds it.
      final relaunched = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier.withState(
              const AuthState(status: AuthStatus.authenticated),
            ),
          ),
          localDataOwnerProvider.overrideWith(
            (ref) => prefs.getString(SyncService.localDataOwnerKey),
          ),
          deviceContestedProvider.overrideWith(
            (ref) => prefs.getBool(SyncService.deviceContestedKey) ?? false,
          ),
        ],
      );
      addTearDown(relaunched.dispose);

      expect(
        relaunched.read(deviceLockedProvider),
        isTrue,
        reason:
            'otherwise killing the app from the lock screen is a way back '
            "onto the owner's writable album",
      );
    });

    testWidgets('the owner reclaiming the device clears the refusal', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        SyncService.localDataOwnerKey: 'account-a',
        SyncService.deviceContestedKey: true,
      });

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier.withState(
              const AuthState(
                status: AuthStatus.authenticated,
                uid: 'account-a',
              ),
            ),
          ),
          localDataOwnerProvider.overrideWith((ref) => 'account-a'),
          deviceContestedProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      await _pumpRouter(tester, container);
      tester.takeException();

      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool(SyncService.deviceContestedKey),
        isNull,
        reason:
            'a stale refusal would lock the owner out of their own device on '
            'the next offline launch, which is what ruling 2 forbids',
      );
      expect(container.read(deviceLockedProvider), isFalse);
    });

    testWidgets('the owner signing back in gives the device back', (
      tester,
    ) async {
      // The first of the two ways out. The lock is derived state, so it is
      // driven here the way the app drives it: it flips, and the router has to
      // let go of the lock screen without being told again.
      final locked = StateProvider<bool>((ref) => true);
      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier.withState(
              const AuthState(status: AuthStatus.authenticated),
            ),
          ),
          deviceLockedProvider.overrideWith((ref) => ref.watch(locked)),
        ],
      );
      addTearDown(container.dispose);

      // `routerProvider` mints a fresh `GoRouter` whenever the lock changes, so
      // this watches it the way `PotteryTrackerApp` does rather than holding
      // the first instance — otherwise the release could never be observed.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: Consumer(
            builder: (context, ref, _) => MaterialApp.router(
              routerConfig: ref.watch(routerProvider),
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('en')],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).state.matchedLocation,
        '/device-locked',
      );
      expect(find.byType(DeviceLockedScreen), findsOneWidget);

      container.read(locked.notifier).state = false;
      await tester.pump();
      // The album subtree reaches for the database and the sync stack, which a
      // test does not provide; its build failure is beside the point here,
      // which is that the redirect no longer holds the user on the lock.
      tester.takeException();

      expect(
        container.read(routerProvider).state.matchedLocation,
        '/',
        reason:
            'signing back in as the owner is one of the only two ways out, so '
            'the lock releasing has to hand the app back on its own',
      );
    });
  });
}
