import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/sync_provider.dart';
import 'package:pottery_tracker/services/sync_queue.dart';
import 'package:pottery_tracker/services/sync_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who the record of a half-finished account deletion belongs to.
///
/// One device, one slot, and two accounts that can both reach "Delete Account
/// & Data" on it. The record is what the user is left with once the message
/// that first reported the partial failure has gone, so whose deletion may
/// settle it is the whole question.
class _MockSyncService extends Mock implements SyncService {}

class _MockSyncQueue extends Mock implements SyncQueue {}

void main() {
  late _MockSyncService syncService;
  late _MockSyncQueue queue;

  /// Whether Firebase accepts the account deletion. It refuses with
  /// `requires-recent-login` far more often than not, which is why the record
  /// exists at all — but a deletion that goes through is what settles one, so
  /// both sides have to be reachable here.
  var accountDeleteSucceeds = true;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    accountDeleteSucceeds = true;
    syncService = _MockSyncService();
    queue = _MockSyncQueue();
    when(() => queue.pendingCount).thenAnswer((_) async => 0);
    when(() => queue.getAll()).thenAnswer((_) async => []);
    when(() => queue.clear()).thenAnswer((_) async {});
    when(
      () => syncService.getLastPulledAt(any()),
    ).thenAnswer((_) async => null);
    when(() => syncService.pushAllLocal(any())).thenAnswer((_) async {});
    when(() => syncService.pullAll(any())).thenAnswer((_) async {});
    when(() => syncService.retryMissingUploads(any())).thenAnswer((_) async {});
    when(() => syncService.deleteCloudData(any())).thenAnswer((_) async {});
    when(() => syncService.deleteLocalData()).thenAnswer((_) async {});
    when(() => syncService.getLocalDataOwner()).thenAnswer((_) async => null);
    when(() => syncService.setLocalDataOwner(any())).thenAnswer((_) async {});
    when(() => syncService.getDeviceContested()).thenAnswer((_) async => false);
  });

  /// The app signed in as [uid], seeded from preferences the way `main` seeds
  /// it, so a container built here launches the way the app launches.
  Future<ProviderContainer> appSignedInAs(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith(
          (_) => AuthNotifier.withState(
            AuthState(status: AuthStatus.authenticated, uid: uid),
          ),
        ),
        syncQueueProvider.overrideWithValue(queue),
        syncServiceProvider.overrideWithValue(syncService),
        syncStateProvider.overrideWith(
          (ref) => SyncNotifier(
            ref,
            queue,
            syncService,
            deleteAuthAccount: () async {
              if (!accountDeleteSucceeds) {
                throw PlatformException(code: 'requires-recent-login');
              }
            },
          ),
        ),
        ...deviceStateOverrides(prefs),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Future<void> settle() async {
    for (var i = 0; i < 30; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  /// Leaves the device as A's half-failed deletion leaves it: A's cloud tree
  /// gone, A's account standing and recorded, the local data wiped so the
  /// device is unclaimed, and A signed out.
  Future<void> aHalfFails() async {
    SharedPreferences.setMockInitialValues({});
    accountDeleteSucceeds = false;
    final asA = await appSignedInAs('account-a');
    await settle();
    expect(
      await asA.read(syncStateProvider.notifier).deleteAllData(),
      DeleteAllDataResult.accountSurvived,
    );
    await settle();
    asA.dispose();
  }

  test("B's own deletion does not settle A's outstanding one", () async {
    await aHalfFails();

    // The phone is handed over — the wipe left it unclaimed — and B signs in
    // and later deletes B's own account, which Firebase accepts.
    accountDeleteSucceeds = true;
    final asB = await appSignedInAs('account-b');
    await settle();
    expect(
      await asB.read(syncStateProvider.notifier).deleteAllData(),
      DeleteAllDataResult.deleted,
      reason: "this proves nothing unless B's deletion actually succeeded",
    );
    await settle();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(SyncService.accountDeletionOwedKey),
      'account-a',
      reason:
          "A's account is still standing and A was told to sign in again and "
          "retry — B finishing their own deletion is not A's record to erase",
    );
  });

  test('so A still finds it after signing back in', () async {
    await aHalfFails();

    accountDeleteSucceeds = true;
    final asB = await appSignedInAs('account-b');
    await settle();
    await asB.read(syncStateProvider.notifier).deleteAllData();
    await settle();
    asB.dispose();

    final asA = await appSignedInAs('account-a');
    expect(
      asA.read(accountDeletionOwedForSessionProvider),
      isTrue,
      reason:
          'the delete-account surface has to still say the deletion is '
          'outstanding, which is the whole point of persisting it',
    );
  });

  test("an account's own successful deletion does settle its record", () async {
    // The other half of the scope: this must not over-correct into a record
    // nothing can ever clear.
    await aHalfFails();

    accountDeleteSucceeds = true;
    final asA = await appSignedInAs('account-a');
    await settle();
    expect(
      await asA.read(syncStateProvider.notifier).deleteAllData(),
      DeleteAllDataResult.deleted,
    );
    await settle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SyncService.accountDeletionOwedKey), isNull);
    expect(asA.read(accountDeletionOwedForSessionProvider), isFalse);
  });
}
