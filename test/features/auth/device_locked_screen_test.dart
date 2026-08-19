import 'package:flutter/cupertino.dart' show CupertinoAlertDialog;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/features/auth/screens/device_locked_screen.dart';
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

class _FakeAuthService implements AuthService {
  int signOutCalls = 0;

  @override
  Future<void> signOut() async => signOutCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} not used here');
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
    // The device belongs to somebody else — that is why the lock is up.
    when(
      () => syncService.getLocalDataOwner(),
    ).thenAnswer((_) async => 'the-owner');
    when(() => syncService.setLocalDataOwner(any())).thenAnswer((_) async {});
    // The refusal marker is device-ownership state like the stamp above: the
    // notifier reads it on every claim, so a mock has to answer for it.
    when(() => syncService.getDeviceContested()).thenAnswer((_) async => false);
    when(() => syncService.setDeviceContested()).thenAnswer((_) async {});
    when(() => syncService.clearDeviceContested()).thenAnswer((_) async {});
  });

  /// [owedWipe] picks which of the two locks the screen is standing in for.
  /// Both are seeded through the persisted state the lock is really derived
  /// from, so the screen's own branch is what decides what is drawn.
  Future<void> pumpLocked(WidgetTester tester, {bool owedWipe = false}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            (ref) => _FakeAuthNotifier(
              const AuthState(status: AuthStatus.authenticated, uid: 'someone'),
            ),
          ),
          authServiceProvider.overrideWithValue(authService),
          syncServiceProvider.overrideWithValue(syncService),
          syncQueueProvider.overrideWithValue(queue),
          localDataOwnerProvider.overrideWith((ref) => 'the-owner'),
          pendingLocalWipeProvider.overrideWith((ref) => owedWipe),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: [Locale('en')],
          home: DeviceLockedScreen(),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('offers exactly the two ways out, and says why', (tester) async {
    await pumpLocked(tester);

    expect(find.text('This device belongs to another account'), findsOneWidget);
    expect(find.textContaining('read-only'), findsOneWidget);
    expect(find.text('Sign In As Another Account'), findsOneWidget);
    expect(find.text('Erase This Device'), findsOneWidget);
  });

  testWidgets('leaving deletes nothing — the pottery is not this account\'s', (
    tester,
  ) async {
    await pumpLocked(tester);

    await tester.tap(find.text('Sign In As Another Account'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(authService.signOutCalls, 1);
    verifyNever(() => syncService.deleteLocalData());
  });

  testWidgets('erasing asks first, and cancelling deletes nothing', (
    tester,
  ) async {
    await pumpLocked(tester);

    await tester.tap(find.text('Erase This Device'));
    await tester.pumpAndSettle();

    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    verifyNever(() => syncService.deleteLocalData());
    expect(authService.signOutCalls, 0);
  });

  testWidgets('confirming the erase wipes the device', (tester) async {
    await pumpLocked(tester);

    await tester.tap(find.text('Erase This Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    verify(() => syncService.deleteLocalData()).called(1);
  });

  testWidgets('an erase that fails says so rather than closing on silence', (
    tester,
  ) async {
    when(() => syncService.deleteLocalData()).thenThrow(Exception('disk full'));
    await pumpLocked(tester);

    await tester.tap(find.text('Erase This Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    // The dialog closing with nothing said would read as a successful erase.
    expect(find.textContaining('Could not erase'), findsOneWidget);
  });

  group('an owed wipe', () {
    testWidgets('is described as the unfinished erase it is', (tester) async {
      await pumpLocked(tester, owedWipe: true);

      expect(find.text('Backup paused'), findsOneWidget);
      expect(
        find.textContaining("The previous account's data still has to be"),
        findsOneWidget,
      );
      expect(
        find.text('This device belongs to another account'),
        findsNothing,
        reason:
            "the pottery here is the signed-in user's own, and telling them "
            'it belongs to a stranger is simply false',
      );
    });

    testWidgets('offers the erase that finishes it, and nothing else', (
      tester,
    ) async {
      await pumpLocked(tester, owedWipe: true);

      expect(find.text('Erase This Device'), findsOneWidget);
      expect(
        find.text('Sign In As Another Account'),
        findsNothing,
        reason:
            'that action deliberately keeps the local data, which is the '
            'opposite of what this user already confirmed they wanted',
      );
    });

    testWidgets('the erase is the primary action', (tester) async {
      await pumpLocked(tester, owedWipe: true);

      expect(
        find.ancestor(
          of: find.text('Erase This Device'),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
        reason: 'the only way out must not be the one that reads as optional',
      );
    });
  });
}
