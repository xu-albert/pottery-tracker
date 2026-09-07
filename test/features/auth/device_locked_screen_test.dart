import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoAlertDialog;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  });

  /// [owedWipe] picks which of the two locks the screen is standing in for.
  /// Both are seeded through the persisted state the lock is really derived
  /// from, so the screen's own branch is what decides what is drawn — and the
  /// owed wipe is seeded on disk too, because opening the screen retries it
  /// and re-reads the flag from there.
  Future<void> pumpLocked(
    WidgetTester tester, {
    bool owedWipe = false,
    bool accountOwed = false,
    bool staleSyncBlocking = false,
  }) async {
    if (owedWipe || accountOwed) {
      SharedPreferences.setMockInitialValues({
        if (owedWipe) SyncNotifier.pendingWipeKey: true,
        if (accountOwed) SyncService.accountDeletionOwedKey: 'someone',
      });
    }
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
          staleSyncBlockingWipeProvider.overrideWith(
            (ref) => staleSyncBlocking,
          ),
          accountDeletionOwedProvider.overrideWith(
            (ref) => accountOwed ? 'someone' : null,
          ),
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

    expect(find.text('This device is locked'), findsOneWidget);
    expect(find.textContaining('read-only'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Erase This Device'), findsOneWidget);
  });

  testWidgets('leaving deletes nothing — the pottery is not this account\'s', (
    tester,
  ) async {
    await pumpLocked(tester);

    await tester.tap(find.text('Sign In'));
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
    expect(
      find.textContaining('Nothing was deleted'),
      findsOneWidget,
      reason: 'true here: the wipe threw before it removed anything',
    );

    // The failed wipe leaves one owed, and the owed-wipe reason outranks the
    // stamp — so the screen changes underneath the message, dropping the
    // "sign in as the owner" way out. Deliberate (B did confirm the
    // destruction, and the owed wipe is retried at the owner's next auth
    // transition), and asserted so a change to that precedence is visible.
    await tester.pump();
    expect(find.text('This device still has to be erased'), findsOneWidget);
    expect(find.text('Sign In'), findsNothing);
  });

  testWidgets('an erase that left photo files behind never says "nothing"', (
    tester,
  ) async {
    // The rows, the queue, the watermarks and the stamp are all gone by the
    // time this is thrown; only the photographs are not.
    when(
      () => syncService.deleteLocalData(),
    ).thenThrow(LocalPhotoWipeException(Exception('photos directory is busy')));
    await pumpLocked(tester);

    await tester.tap(find.text('Erase This Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.textContaining('could not be removed'), findsOneWidget);
    expect(
      find.textContaining('Nothing was deleted'),
      findsNothing,
      reason: 'the library really was erased; only the photo files survived',
    );

    // The erase stays owed, and the screen underneath now says so too — the
    // two statements agree instead of contradicting each other.
    await tester.pump();
    expect(find.text('This device still has to be erased'), findsOneWidget);
    expect(find.text('Erase This Device'), findsOneWidget);
  });

  testWidgets('an erase that could not replace the key never says "nothing"', (
    tester,
  ) async {
    // Everything the confirmation promised is gone by the time this is
    // thrown; what is owed is the rotation that secures the device for
    // whoever uses it next.
    when(
      () => syncService.deleteLocalData(),
    ).thenThrow(LocalKeyRotationException(Exception('the key store is full')));
    await pumpLocked(tester);

    await tester.tap(find.text('Erase This Device'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Erase'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.textContaining('could not be replaced'), findsOneWidget);
    expect(
      find.textContaining('Nothing was deleted'),
      findsNothing,
      reason: 'everything really was erased; only the re-keying was not done',
    );

    await tester.pump();
    expect(find.text('This device still has to be erased'), findsOneWidget);
  });

  group("ruling 4: the explanation wraps, however long it runs", () {
    // This guard used to live on the Settings sync tile and went with it when
    // both blocked reasons started locking the router. The explanation moved
    // here, so the assertion follows it: the recovery instruction is the whole
    // point of that paragraph, and an ellipsis through it leaves the user with
    // no stated way out of a state they cannot otherwise leave.
    const narrowPhone = Size(390, 1400);

    void expectWraps(WidgetTester tester, Finder text) {
      expect(text, findsOneWidget);
      expect(
        tester.renderObject<RenderParagraph>(text).didExceedMaxLines,
        isFalse,
        reason: 'ruling 4: blocked-state explanations wrap without a limit',
      );
    }

    testWidgets('the foreign-pottery explanation is not truncated', (
      tester,
    ) async {
      tester.view.physicalSize = narrowPhone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpLocked(tester);
      expectWraps(tester, find.textContaining('kept read-only'));
    });

    testWidgets('nor is the owed-wipe explanation and its account notice', (
      tester,
    ) async {
      // The longest the screen ever gets: the owed-wipe explanation plus the
      // surviving-account paragraph, which names two sequential steps. A
      // device that stays on this lock is one whose wipe keeps failing — a
      // wipe that succeeds clears the flag and the lock with it.
      when(
        () => syncService.deleteLocalData(),
      ).thenThrow(Exception('disk full'));
      tester.view.physicalSize = narrowPhone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpLocked(tester, owedWipe: true, accountOwed: true);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expectWraps(tester, find.textContaining('An erase was started'));
      expectWraps(
        tester,
        find.textContaining('account itself was not deleted'),
      );
    });
  });

  group('an owed wipe', () {
    // A device sitting on this lock is one whose wipe keeps failing — a wipe
    // that succeeds clears the flag and the lock with it — so that is the
    // state these run in, except where a test says otherwise.
    setUp(() {
      when(
        () => syncService.deleteLocalData(),
      ).thenThrow(Exception('disk full'));
    });

    testWidgets('tries again once the sync that was blocking it ends', (
      tester,
    ) async {
      // A wipe that lands while a sync outlives it keeps the owed flag, and
      // this screen opens while that sync is still running — so the attempt it
      // makes on mount is refused for the same reason. That used to be the
      // only attempt there was, and the device sat locked long after the sync
      // had unwound, with the erase button as the one way off it.
      var attempts = 0;
      when(() => syncService.deleteLocalData()).thenAnswer((_) async {
        attempts++;
        throw Exception('disk full');
      });

      await pumpLocked(tester, owedWipe: true);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      final onMount = attempts;
      expect(onMount, greaterThan(0), reason: 'the screen does try on mount');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(DeviceLockedScreen)),
      );
      // A sync takes hold and then finishes. Driven in both directions from
      // the test, because the transition is the signal — the screen must not
      // depend on which frame it happened to mount on.
      container.read(staleSyncBlockingWipeProvider.notifier).state = true;
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(attempts, onMount, reason: 'nothing to try while it still holds');

      container.read(staleSyncBlockingWipeProvider.notifier).state = false;
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        attempts,
        greaterThan(onMount),
        reason:
            'the blocker is gone, so the wipe the user confirmed gets another '
            'attempt without them having to ask for it again',
      );
    });

    /// Holds every `deleteLocalData` call open on its own gate, so a test
    /// can act while an attempt is running and then let it fail.
    List<Completer<void>> gateEveryAttempt() {
      final gates = <Completer<void>>[];
      when(() => syncService.deleteLocalData()).thenAnswer((_) async {
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        throw Exception('disk full');
      });
      return gates;
    }

    Future<void> pumpABit(WidgetTester tester) async {
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    testWidgets('a sync that ends during an attempt still earns another', (
      tester,
    ) async {
      // The likeliest timing, not a corner: the attempt made on mount is the
      // one the stale sync refuses, and that sync unwinds while the attempt
      // is still running. The attempt captured the blocked condition when it
      // started, so it keeps the flag — and a signal dropped here never comes
      // again, leaving the device locked until the user re-confirms.
      final gates = gateEveryAttempt();

      await pumpLocked(tester, owedWipe: true, staleSyncBlocking: true);
      await pumpABit(tester);
      expect(gates, hasLength(1), reason: 'the mount attempt is running');

      final container = ProviderScope.containerOf(
        tester.element(find.byType(DeviceLockedScreen)),
      );
      container.read(staleSyncBlockingWipeProvider.notifier).state = false;
      await pumpABit(tester);
      expect(
        gates,
        hasLength(1),
        reason: 'one attempt at a time; the signal waits for it',
      );

      gates[0].complete();
      await pumpABit(tester);
      expect(
        gates,
        hasLength(2),
        reason:
            'the blocker ended while the first attempt ran, so that attempt '
            'could not have seen it; a further one has to follow',
      );

      gates[1].complete();
      await pumpABit(tester);
      expect(
        gates,
        hasLength(2),
        reason: 'nothing arrived during the follow-up, so it settles',
      );
    });

    testWidgets('several syncs ending during one attempt earn exactly one', (
      tester,
    ) async {
      final gates = gateEveryAttempt();

      await pumpLocked(tester, owedWipe: true, staleSyncBlocking: true);
      await pumpABit(tester);
      expect(gates, hasLength(1));

      final container = ProviderScope.containerOf(
        tester.element(find.byType(DeviceLockedScreen)),
      );
      final blocking = container.read(staleSyncBlockingWipeProvider.notifier);
      blocking.state = false;
      for (var i = 0; i < 3; i++) {
        blocking.state = true;
        blocking.state = false;
      }
      await pumpABit(tester);
      expect(gates, hasLength(1));

      gates[0].complete();
      await pumpABit(tester);
      expect(
        gates,
        hasLength(2),
        reason: 'four signals during one attempt owe one follow-up, not four',
      );

      gates[1].complete();
      await pumpABit(tester);
      expect(
        gates,
        hasLength(2),
        reason: 'and the follow-up settles rather than re-arming itself',
      );
    });

    testWidgets('is described as the unfinished erase it is', (tester) async {
      await pumpLocked(tester, owedWipe: true);

      expect(find.text('This device still has to be erased'), findsOneWidget);
      expect(
        find.textContaining('An erase was started on this device'),
        findsOneWidget,
      );
      expect(
        find.text('This device is locked'),
        findsNothing,
        reason:
            'an unfinished erase is a different situation from pottery '
            'waiting for its account, and needs its own words',
      );
    });

    testWidgets('offers the erase that finishes it, and nothing else', (
      tester,
    ) async {
      await pumpLocked(tester, owedWipe: true);

      expect(find.text('Erase This Device'), findsOneWidget);
      expect(
        find.text('Sign In'),
        findsNothing,
        reason:
            'that action deliberately keeps the local data, which is the '
            'opposite of what this user already confirmed they wanted',
      );
    });

    testWidgets('retries the wipe on its own when the screen opens', (
      tester,
    ) async {
      // The flag locks the router on the first frame, so the shell never
      // mounts and the auth transition that used to carry the retry never
      // runs. Opening the lock is the only trigger left.
      await pumpLocked(tester, owedWipe: true);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      verify(() => syncService.deleteLocalData()).called(1);
      expect(
        find.byType(CupertinoAlertDialog),
        findsNothing,
        reason: 'the user already confirmed this erase; it does not re-ask',
      );
    });

    testWidgets('a transient failure heals without the user tapping', (
      tester,
    ) async {
      // The retry succeeds this time — the photo file that was locked is not
      // any more — so the lock lets go on its own.
      when(() => syncService.deleteLocalData()).thenAnswer((_) async {});

      await pumpLocked(tester, owedWipe: true);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        find.text('This device still has to be erased'),
        findsNothing,
        reason:
            'the wipe is no longer owed, so the reason that raised this lock '
            'is gone and the router has nothing left to hold',
      );
    });

    testWidgets('a wipe that is not owed is not retried behind the user', (
      tester,
    ) async {
      // The foreign-pottery lock is somebody else's library. Nothing may be
      // deleted there without the confirmation the erase button asks for.
      await pumpLocked(tester);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      verifyNever(() => syncService.deleteLocalData());
    });

    testWidgets('says the account survived, on the screen it redirects to', (
      tester,
    ) async {
      // A "Delete Account & Data" whose local wipe failed raises this lock and
      // redirects here, taking the message about the surviving account with
      // it. The fact is persisted, so the user can still find it.
      await pumpLocked(tester, owedWipe: true, accountOwed: true);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        find.textContaining('account itself was not deleted'),
        findsOneWidget,
        reason:
            'otherwise nothing anywhere records that the account still '
            'exists once the message that said so has gone',
      );
    });

    testWidgets('says nothing about an account that was deleted', (
      tester,
    ) async {
      await pumpLocked(tester, owedWipe: true);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(
        find.textContaining('account itself was not deleted'),
        findsNothing,
        reason: 'an ordinary owed wipe has no surviving account to report',
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
