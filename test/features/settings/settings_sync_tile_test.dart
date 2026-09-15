import 'dart:async';

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

/// Stands in for the Firebase session; the sync tile never reaches it.
class _FakeAuthService implements AuthService {
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

  /// What the persisted queue reports; the offline edits in these tests move
  /// it the way a real write does.
  late int pending;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    syncService = _MockSyncService();
    queue = _MockSyncQueue();
    pending = 0;

    when(() => queue.pendingCount).thenAnswer((_) async => pending);
    when(() => queue.getAll()).thenAnswer((_) async => <SyncQueueEntry>[]);
    when(() => syncService.getLocalDataOwner()).thenAnswer((_) async => null);
    when(() => syncService.getDeviceContested()).thenAnswer((_) async => false);
    when(() => syncService.setLocalDataOwner(any())).thenAnswer((_) async {});
    when(() => syncService.retryMissingUploads(any())).thenAnswer((_) async {});
    // A device that has synced before, so the launch below takes the
    // incremental path...
    when(
      () => syncService.getLastPulledAt(any()),
    ).thenAnswer((_) async => DateTime.utc(2026, 9, 1));
    // ...and finds the server unreachable, which is what an offline launch
    // now leaves on the tile.
    when(
      () => syncService.pullChangedSince(any(), any()),
    ).thenThrow(Exception('unavailable'));
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith(
            (ref) => _FakeAuthNotifier(
              const AuthState(
                status: AuthStatus.authenticated,
                uid: 'user-a',
                displayName: 'A',
              ),
            ),
          ),
          authServiceProvider.overrideWithValue(_FakeAuthService()),
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
    // The sign-in sync runs off several async hops; none of them is long
    // enough to reach the 500ms drain debounce.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  SyncNotifier notifierOf(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(SettingsScreen)),
  ).read(syncStateProvider.notifier);

  group('sync tile', () {
    testWidgets('reports work that has not left the device even while the '
        'sync is failing', (tester) async {
      pending = 2;

      await pumpSettings(tester);

      expect(find.text('Sync error'), findsOneWidget);
      expect(find.textContaining('2 changes pending'), findsOneWidget);
    });

    testWidgets('counts an edit queued while the sync is failing', (
      tester,
    ) async {
      await pumpSettings(tester);

      expect(find.text('Sync error'), findsOneWidget);
      expect(find.textContaining('pending'), findsNothing);

      // The offline edit: persisted, then handed to the debounced drain.
      pending = 1;
      notifierOf(tester).scheduleProcessQueue();
      await tester.pump();
      await tester.pump();

      expect(find.text('Sync error'), findsOneWidget);
      expect(find.textContaining('1 change pending'), findsOneWidget);

      // Let the debounce fire so no timer outlives the test.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });

    testWidgets('shows the failure reason and the pending count together at '
        'the moment a sync fails', (tester) async {
      pending = 1;

      await pumpSettings(tester);

      final subtitle = tester
          .widget<Text>(
            find.descendant(
              of: find.ancestor(
                of: find.text('Sync error'),
                matching: find.byType(ListTile),
              ),
              matching: find.textContaining('pending'),
            ),
          )
          .data!;
      expect(subtitle, contains('1 change pending'));
      expect(subtitle, contains('unavailable'));
    });

    testWidgets('reports queued work while a sync is still in progress', (
      tester,
    ) async {
      // An offline push Firestore holds until the device reconnects, so the
      // tile stays on "Syncing..." with the work still on the device.
      pending = 1;
      const queued = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'piece-1',
      );
      when(() => queue.getAll()).thenAnswer((_) async => const [queued]);
      when(() => queue.revisionOf(queued)).thenReturn(0);
      when(
        () => syncService.pushPiece(any(), any()),
      ).thenAnswer((_) => Completer<void>().future);

      await pumpSettings(tester);

      expect(find.text('Syncing...'), findsOneWidget);
      expect(find.textContaining('1 change pending'), findsOneWidget);

      // A second edit made while that push is still waiting.
      pending = 2;
      notifierOf(tester).scheduleProcessQueue();
      await tester.pump();
      await tester.pump();

      expect(find.text('Syncing...'), findsOneWidget);
      expect(find.textContaining('2 changes pending'), findsOneWidget);

      // Let the debounce fire; it stands down while the sync holds the lock.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    });

    testWidgets('stops reporting work the running sync has already delivered', (
      tester,
    ) async {
      // The push half succeeds and empties the queue; the pull half is still
      // running, which on a first sync is where most of the time goes.
      pending = 1;
      const queued = SyncQueueEntry(
        operation: SyncOperation.pushPiece,
        entityId: 'piece-1',
      );
      when(() => queue.getAll()).thenAnswer((_) async => const [queued]);
      when(() => queue.revisionOf(queued)).thenReturn(0);
      when(() => syncService.pushPiece(any(), any())).thenAnswer((_) async {});
      when(() => queue.remove(queued)).thenAnswer((_) async => pending = 0);
      when(
        () => syncService.pullChangedSince(any(), any()),
      ).thenAnswer((_) => Completer<void>().future);

      await pumpSettings(tester);

      expect(find.text('Syncing...'), findsOneWidget);
      expect(find.textContaining('pending'), findsNothing);
    });
  });
}
