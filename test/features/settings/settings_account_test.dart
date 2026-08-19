import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoAlertDialog;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/features/settings/screens/settings_screen.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/services/auth_service.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../helpers/firebase_mocks.dart';

class _MockSyncService extends Mock implements SyncService {}

class _MockSyncQueue extends Mock implements SyncQueue {}

/// Stands in for the Firebase/Google session so the test never reaches a
/// platform channel.
class _FakeAuthService implements AuthService {
  int signOutCalls = 0;

  @override
  Future<void> signOut() async => signOutCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} not used in this test',
  );
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(super.initial) : super.withState();
}

void main() {
  setUpAll(setupFirebaseCoreMocks);

  late _MockSyncService syncService;
  late _MockSyncQueue queue;
  late _FakeAuthService authService;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    syncService = _MockSyncService();
    queue = _MockSyncQueue();
    authService = _FakeAuthService();
    when(() => queue.clear()).thenAnswer((_) async {});
    when(() => queue.pendingCount).thenAnswer((_) async => 0);
    when(() => queue.getAll()).thenAnswer((_) async => []);
    when(() => syncService.deleteLocalData()).thenAnswer((_) async {});
    when(
      () => syncService.getLastPulledAt(any()),
    ).thenAnswer((_) async => null);
    when(() => syncService.pushAllLocal(any())).thenAnswer((_) async {});
    when(() => syncService.pullAll(any())).thenAnswer((_) async {});
    when(() => syncService.retryMissingUploads(any())).thenAnswer((_) async {});
    when(() => syncService.setLocalDataOwner(any())).thenAnswer((_) async {});
    // The refusal marker is device-ownership state like the stamp above: the
    // notifier reads it on every claim, so a mock has to answer for it.
    when(() => syncService.getDeviceContested()).thenAnswer((_) async => false);
    when(() => syncService.setDeviceContested()).thenAnswer((_) async {});
    when(() => syncService.clearDeviceContested()).thenAnswer((_) async {});
    // Unowned by default: Settings is only reachable on a device this account
    // owns, since a contested one is locked read-only at the router.
    when(() => syncService.getLocalDataOwner()).thenAnswer((_) async => null);
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    Set<String> linkedProviders = const {'google.com', 'apple.com'},
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            (ref) => _FakeAuthNotifier(
              AuthState(
                status: AuthStatus.authenticated,
                uid: 'user-a',
                displayName: 'A',
                linkedProviders: linkedProviders,
              ),
            ),
          ),
          authServiceProvider.overrideWithValue(authService),
          syncServiceProvider.overrideWithValue(syncService),
          syncQueueProvider.overrideWithValue(queue),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en')],
          home: SettingsScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  group('sign-out confirmation', () {
    testWidgets('says plainly that this device\'s data will be deleted', (
      tester,
    ) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      final message = tester
          .widget<Text>(
            find
                .descendant(
                  of: find.byType(CupertinoAlertDialog),
                  matching: find.byType(Text),
                )
                .at(1),
          )
          .data!;
      expect(message, contains('deletes'));
      expect(message, contains('this device'));
      // Cancelling has to be offered, and the destructive action has to name
      // what it does rather than just saying "Sign Out".
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Sign Out & Erase'), findsOneWidget);
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(authService.signOutCalls, 0);
      verifyNever(() => syncService.deleteLocalData());
    });

    testWidgets('a tap on the barrier does not sign the user out', (
      tester,
    ) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();

      // Top-left corner is barrier, not dialog.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      verifyNever(() => syncService.deleteLocalData());
    });

    testWidgets('confirming wipes the local database', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign Out & Erase'));
      // Not pumpAndSettle: the tile shows a spinner while the wipe runs, so
      // the tree never goes quiet until it is done.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(authService.signOutCalls, 1);
      verify(() => syncService.deleteLocalData()).called(1);
      verify(() => queue.clear()).called(greaterThanOrEqualTo(1));
    });

    testWidgets('a failed wipe is reported instead of passing silently', (
      tester,
    ) async {
      when(
        () => syncService.deleteLocalData(),
      ).thenThrow(Exception('disk full'));
      await pumpSettings(tester);

      await tester.tap(find.text('Sign Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sign Out & Erase'));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      // The session still ends; the user is told the device is not clean yet.
      expect(authService.signOutCalls, 1);
      expect(find.textContaining('could not be deleted'), findsOneWidget);
    });
  });

  group('delete account tile', () {
    testWidgets('excludes itself and Sign Out while a delete is in flight', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Hold the delete open the way a real one is held open — cloud deletion
      // and the account delete are seconds of network.
      final inFlight = Completer<void>();
      when(
        () => syncService.deleteCloudData(any()),
      ).thenAnswer((_) => inFlight.future);
      when(() => syncService.getLocalDataOwner()).thenAnswer((_) async => null);

      await pumpSettings(tester);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      await tester.tap(find.text('Delete Account & Data'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete Everything'));
      // Not pumpAndSettle: the sync tile spins for the length of the delete,
      // so the tree never goes quiet. Pump past the dialog's dismissal instead.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(find.text('Delete Everything'), findsNothing);

      // A second tap must not reach a second confirmation. That call would
      // return early on the in-flight delete, but its `finally` clears the
      // in-flight flag and re-enables Sign Out.
      await tester.tap(find.text('Delete Account & Data'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Delete Everything'), findsNothing);

      // Sign Out has to stay inert: it ends the Firebase session, and a
      // session ended before the in-flight delete reaches the account
      // deletion leaves the cloud data gone and the account itself alive.
      await tester.tap(find.text('Sign Out'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Sign Out & Erase'), findsNothing);
    });
  });

  group('provider tiles', () {
    testWidgets('the only linked provider cannot be disconnected', (
      tester,
    ) async {
      await pumpSettings(tester, linkedProviders: const {'google.com'});

      final googleTile = tester.widget<ListTile>(
        find.ancestor(of: find.text('Google'), matching: find.byType(ListTile)),
      );
      expect(googleTile.onTap, isNull);
      expect(
        find.text('Your only sign-in method — connect another first'),
        findsOneWidget,
      );
    });

    testWidgets('a second linked provider re-enables disconnecting', (
      tester,
    ) async {
      await pumpSettings(
        tester,
        linkedProviders: const {'google.com', 'apple.com'},
      );

      final googleTile = tester.widget<ListTile>(
        find.ancestor(of: find.text('Google'), matching: find.byType(ListTile)),
      );
      expect(googleTile.onTap, isNotNull);
      expect(googleTile.subtitle, isNull);
    });
  });
}
