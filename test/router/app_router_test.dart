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
import 'package:pottery_tracker/services/auth_service.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/firebase_mocks.dart';

/// An [AuthNotifier] whose state the test drives, standing in for the moment
/// `_init` finishes resolving.
class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(super.initial) : super.withState();

  void set(AuthState next) => state = next;

  /// Ends the session the way the real one leaves it. The real one awaits
  /// `FirebaseAuth.instance.signOut()`, which never returns under the test
  /// harness, so a test tapping a sign-out button would hang before reaching
  /// anything worth asserting.
  @override
  Future<void> signOut() async {
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}

/// The bare [AuthService] the lock screen hands to `endForeignSession`.
class _StubAuthService implements AuthService {
  @override
  Future<void> signOut() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
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

/// Stands in for the real service so a router test needs no database.
///
/// It answers the device-state reads [SyncNotifier] makes as it is built, and
/// fails the wipe. Failing it is deliberate rather than incidental: an owed
/// wipe that succeeded would clear the flag and unlock the device, and the
/// state under test here is the one where it is still owed.
class _StubSyncService implements SyncService {
  _StubSyncService({required this.owner, required this.contested});

  final String? owner;
  final bool contested;

  @override
  Future<Set<String>> pendingPhotoUploadIds() async => {};

  @override
  Future<String?> getLocalDataOwner() async => owner;

  @override
  Future<bool> getDeviceContested() async => contested;

  @override
  Future<void> deleteLocalData() async {
    throw StateError('the wipe cannot finish, so it stays owed');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not used here');
}

/// Pumps the router the way `PotteryTrackerApp` mounts it — watched, not held.
///
/// `routerProvider` mints a fresh `GoRouter` whenever auth, the lock or the
/// request to leave it changes, so a test holding the first instance would
/// keep showing the answer from before the change it is about.
Future<void> _pumpWatchedRouter(
  WidgetTester tester,
  ProviderContainer container,
) async {
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

  group('the lock settles when the session is gone', () {
    // Both locked states are reachable with no session at all. A refused
    // account that force-quits the lock screen relaunches signed out, because
    // `signOut` clears the onboarding flag and `_init` then answers
    // `unauthenticated`; so does a sign-out whose wipe never finished. Pairing
    // that with the lock left the redirect nowhere to settle — signed-out sent
    // the user to sign-in, and the lock sent sign-in straight back — and
    // go_router answers a cycle by replacing the app with its error page,
    // which took away both ways out at once.
    const foreignPottery = 'another account owns this device';
    const owedWipe = 'a confirmed wipe is still owed';

    /// Seeds the device state on disk and builds the container off it through
    /// `deviceStateOverrides`, which is the same seeding `main` runs before
    /// `runApp`. Going through preferences rather than pinning the providers
    /// matters: `SyncNotifier` re-reads all three from disk on construction,
    /// so a lock forced straight onto the providers would quietly come undone
    /// at exactly the moment these tests are about.
    Future<ProviderContainer> signedOutWith(String reason) async {
      SharedPreferences.setMockInitialValues(
        reason == foreignPottery
            ? {
                SyncService.localDataOwnerKey: 'account-a',
                SyncService.deviceContestedKey: true,
              }
            : {SyncNotifier.pendingWipeKey: true},
      );
      final prefs = await SharedPreferences.getInstance();

      final syncService = _StubSyncService(
        owner: prefs.getString(SyncService.localDataOwnerKey),
        contested: prefs.getBool(SyncService.deviceContestedKey) ?? false,
      );
      return ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier.withState(
              const AuthState(status: AuthStatus.unauthenticated),
            ),
          ),
          ...deviceStateOverrides(prefs),
          // The owed-wipe lock resumes the wipe as it opens, which builds
          // the sync stack. The stub keeps the database out and lets that
          // retry fail, so the wipe stays owed and the device stays locked —
          // which is the situation these tests are about.
          syncServiceProvider.overrideWithValue(syncService),
          syncQueueProvider.overrideWithValue(SyncQueue()),
        ],
      );
    }

    for (final reason in const [foreignPottery, owedWipe]) {
      testWidgets('$reason: the lock is what the user is left on', (
        tester,
      ) async {
        final container = await signedOutWith(reason);
        addTearDown(container.dispose);
        expect(container.read(deviceLockedProvider), isTrue);

        final router = await _pumpRouter(tester, container);
        await tester.pumpAndSettle();

        expect(router.state.matchedLocation, '/device-locked');
        expect(
          find.byType(DeviceLockedScreen),
          findsOneWidget,
          reason:
              'the lock screen is the only surface offering either way out, '
              'so it has to be the screen actually on display — a redirect '
              'with no fixed point leaves go_router rendering its error page '
              'here instead',
        );
      });

      testWidgets('$reason: sign-in is shut until it is asked for', (
        tester,
      ) async {
        final container = await signedOutWith(reason);
        addTearDown(container.dispose);

        final router = await _pumpRouter(tester, container);
        await tester.pumpAndSettle();

        router.go('/sign-in');
        await tester.pumpAndSettle();

        expect(
          router.state.matchedLocation,
          '/device-locked',
          reason:
              'the lock screen carries the explanation and the erase, so a '
              'device nobody has asked to leave rests there rather than on a '
              'bare sign-in screen',
        );
      });

      testWidgets('$reason: no write surface opened up with it', (
        tester,
      ) async {
        final container = await signedOutWith(reason);
        addTearDown(container.dispose);

        final router = await _pumpRouter(tester, container);
        await tester.pumpAndSettle();

        // Letting sign-in through must not have let anything else through:
        // read-only is the entire point of the state, session or no session.
        for (final route in const [
          '/',
          '/create',
          '/piece/piece-a',
          '/settings',
          '/settings/clays',
          '/settings/glazes',
          '/settings/tags',
        ]) {
          router.go(route);
          await tester.pumpAndSettle();
          expect(
            router.state.matchedLocation,
            '/device-locked',
            reason: '$route must stay shut with no session either',
          );
        }
      });
    }

    testWidgets('$foreignPottery: asking to leave reaches sign-in', (
      tester,
    ) async {
      final container = await signedOutWith(foreignPottery);
      addTearDown(container.dispose);

      await _pumpWatchedRouter(tester, container);
      await tester.pumpAndSettle();
      expect(
        container.read(routerProvider).state.matchedLocation,
        '/device-locked',
      );

      // What the lock screen's button does. The redirect is what acts on it,
      // so this asserts where the request actually lands rather than that it
      // was recorded.
      container.read(lockExitRequestedProvider.notifier).state =
          DeviceLockReason.foreignLocalData;
      await tester.pumpAndSettle();

      expect(
        container.read(routerProvider).state.matchedLocation,
        '/sign-in',
        reason:
            'the owner signing back in is one of the two ways out, so the '
            'lock cannot hold that door shut once it is asked',
      );
      expect(find.byType(SignInScreen), findsOneWidget);
    });

    testWidgets('$owedWipe: asking cannot open a door it never offered', (
      tester,
    ) async {
      // The owed-wipe lock shows the erase alone, because finishing the wipe
      // is the only way out of it. The redirect names that reason rather than
      // trusting the screen not to offer the button, so a request that somehow
      // arrives against it changes nothing.
      final container = await signedOutWith(owedWipe);
      addTearDown(container.dispose);

      await _pumpWatchedRouter(tester, container);
      await tester.pumpAndSettle();

      container.read(lockExitRequestedProvider.notifier).state =
          DeviceLockReason.pendingWipe;
      await tester.pumpAndSettle();

      expect(
        container.read(routerProvider).state.matchedLocation,
        '/device-locked',
        reason:
            'the lock screen is the only surface that retries the owed wipe, '
            'so nothing may route the user past it',
      );
    });

    testWidgets('a request made against one lock cannot answer for another', (
      tester,
    ) async {
      // The reported sequence, end to end. B is refused and asks to leave; the
      // owner reclaims the device and the lock lifts; later a confirmed wipe
      // fails and locks the device again with no session. Held as a bare flag,
      // B's tap from earlier in the same process answered for that second lock
      // and sent the user to sign-in — past the retry and past the erase.
      SharedPreferences.setMockInitialValues({
        SyncService.localDataOwnerKey: 'account-a',
        SyncService.deviceContestedKey: true,
      });
      final prefs = await SharedPreferences.getInstance();

      final owner = StateProvider<String?>((ref) => 'account-a');
      final contested = StateProvider<bool>((ref) => true);
      final owedWipeFlag = StateProvider<bool>((ref) => false);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => AuthNotifier.withState(
              const AuthState(status: AuthStatus.unauthenticated),
            ),
          ),
          localDataOwnerProvider.overrideWith((ref) => ref.watch(owner)),
          deviceContestedProvider.overrideWith((ref) => ref.watch(contested)),
          pendingLocalWipeProvider.overrideWith(
            (ref) => ref.watch(owedWipeFlag),
          ),
          accountDeletionOwedProvider.overrideWith(
            (ref) => prefs.getString(SyncService.accountDeletionOwedKey),
          ),
          syncServiceProvider.overrideWithValue(
            _StubSyncService(owner: 'account-a', contested: true),
          ),
          syncQueueProvider.overrideWithValue(SyncQueue()),
        ],
      );
      addTearDown(container.dispose);

      await _pumpWatchedRouter(tester, container);
      await tester.pumpAndSettle();

      // B asks to leave the foreign-pottery lock.
      container.read(lockExitRequestedProvider.notifier).state =
          DeviceLockReason.foreignLocalData;
      await tester.pumpAndSettle();
      expect(container.read(routerProvider).state.matchedLocation, '/sign-in');

      // The owner reclaims the device: the stamp is theirs again and the
      // refusal is lifted, so the lock goes.
      container.read(contested.notifier).state = false;
      container.read(owner.notifier).state = null;
      await tester.pumpAndSettle();
      tester.takeException();
      expect(container.read(deviceLockedProvider), isFalse);

      // Later, a confirmed wipe fails and locks the device again.
      container.read(owedWipeFlag.notifier).state = true;
      await tester.pumpAndSettle();

      expect(
        container.read(routerProvider).state.matchedLocation,
        '/device-locked',
        reason:
            'the earlier tap belonged to a lock that is long gone, and this '
            'one has only one way out — the erase the lock screen offers',
      );
      expect(find.byType(DeviceLockedScreen), findsOneWidget);
    });

    testWidgets('$foreignPottery: the way out survives signing out', (
      tester,
    ) async {
      // The way out is the whole reason the lock screen has a button, and it
      // has to work from the state it is normally reached in: a refused
      // account is still signed in. Ending that session rebuilds the router at
      // its initial location, so anything the screen navigated to is gone by
      // the time the user could see it — which is why the redirect, not the
      // screen, is what performs this.
      SharedPreferences.setMockInitialValues({
        SyncService.localDataOwnerKey: 'account-a',
        SyncService.deviceContestedKey: true,
      });
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => _TestAuthNotifier(
              const AuthState(
                status: AuthStatus.authenticated,
                uid: 'account-b',
              ),
            ),
          ),
          ...deviceStateOverrides(prefs),
          authServiceProvider.overrideWithValue(_StubAuthService()),
          syncServiceProvider.overrideWithValue(
            _StubSyncService(owner: 'account-a', contested: true),
          ),
          syncQueueProvider.overrideWithValue(SyncQueue()),
        ],
      );
      addTearDown(container.dispose);

      // Watched rather than held, the way `PotteryTrackerApp` does it: signing
      // out mints a new `GoRouter`, and holding the first one would hide the
      // very rebuild this is about.
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

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(
        container.read(routerProvider).state.matchedLocation,
        '/sign-in',
        reason:
            'the owner signing back in is one of the only two ways out, so '
            'asking for it has to actually arrive somewhere',
      );
      expect(find.byType(SignInScreen), findsOneWidget);
      expect(
        container.read(deviceLockedProvider),
        isTrue,
        reason:
            'and it is a detour, not a release — only the owner reclaiming '
            'the device lifts the refusal',
      );
    });

    testWidgets('and the sign-in it reaches is not a way in', (tester) async {
      // The sign-in screen a locked device can reach must stay a dead end for
      // anyone who is not the owner: continuing without an account is the one
      // door into a writable session that no lock covers.
      final container = await signedOutWith(foreignPottery);
      addTearDown(container.dispose);

      await _pumpWatchedRouter(tester, container);
      await tester.pumpAndSettle();
      container.read(lockExitRequestedProvider.notifier).state =
          DeviceLockReason.foreignLocalData;
      await tester.pumpAndSettle();

      expect(find.byType(SignInScreen), findsOneWidget);
      expect(
        find.text('Skip for now'),
        findsNothing,
        reason: 'skipping would hand over the pottery the lock is protecting',
      );
    });

    test('an owed wipe closes that door too, with no stamp to close it', () {
      // The owed-wipe lock keeps the user off the sign-in screen entirely, so
      // this is the belt to that braces — and it is the case an owner stamp
      // cannot cover, because a wipe that failed after clearing the stamp
      // leaves one owed with no owner at all. If the routing above is ever
      // relaxed, the door stays shut on its own account.
      final container = ProviderContainer(
        overrides: [
          localDataOwnerProvider.overrideWith((ref) => null),
          deviceContestedProvider.overrideWith((ref) => false),
          pendingLocalWipeProvider.overrideWith((ref) => true),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(localDataOwnerProvider), isNull);
      expect(
        container.read(skipSignInAllowedProvider),
        isFalse,
        reason:
            'the library the user confirmed for destruction is still on this '
            'device, and skipping would open it',
      );
    });
  });
}
