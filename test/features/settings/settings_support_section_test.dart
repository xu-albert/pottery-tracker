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
/// platform channel. Nothing here is tapped, so no member is answered.
class _FakeAuthService implements AuthService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
    '${invocation.memberName} not used in this test',
  );
}

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(super.initial) : super.withState();
}

/// V1 is free on every platform: no paywall, no donation link, no tip jar
/// (captain ruling, 2026-08-18, taken so nothing has to be checked against
/// Play's payments policy and because the iOS link was not wanted either).
/// The Support section of Settings is where such a link lived, so this pins
/// what that section offers a signed-in user once the whole screen is laid
/// out: a way to send feedback, and nothing that asks for money or opens an
/// outside page.
void main() {
  setUpAll(setupFirebaseCoreMocks);

  late _MockSyncService syncService;
  late _MockSyncQueue queue;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    syncService = _MockSyncService();
    queue = _MockSyncQueue();
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
    when(() => syncService.getDeviceContested()).thenAnswer((_) async => false);
    when(
      () => syncService.pendingPhotoUploadIds(),
    ).thenAnswer((_) async => <String>{});
    when(() => syncService.getLocalDataOwner()).thenAnswer((_) async => null);
  });

  Future<void> pumpSettings(
    WidgetTester tester, {
    required AuthState auth,
  }) async {
    // Tall enough that every row of the list is built and on screen, so a
    // tile hidden below the fold cannot slip past the assertions.
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(auth)),
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
    // Not pumpAndSettle: the sync tile can keep animating.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Words a donation or tip-jar row would have to use to make sense to a
  /// user. `\btip\b` rather than `tip` so "multiple" cannot match.
  final asksForMoney = RegExp(
    r'support the developer|ko-?fi|donat|\btip\b|buy me a|sponsor',
    caseSensitive: false,
  );

  /// The heart the donation tile was drawn with.
  const donationIcon = Icons.favorite_outline;

  for (final (label, auth) in [
    (
      'a signed-in account',
      const AuthState(
        status: AuthStatus.authenticated,
        uid: 'user-a',
        displayName: 'A',
        linkedProviders: {'google.com', 'apple.com'},
      ),
    ),
    ('a local-only session', const AuthState(status: AuthStatus.authenticated)),
  ]) {
    group('Support section, $label', () {
      testWidgets('offers feedback', (tester) async {
        await pumpSettings(tester, auth: auth);

        final feedbackTile = tester.widget<ListTile>(
          find.ancestor(
            of: find.text('Send Feedback'),
            matching: find.byType(ListTile),
          ),
        );
        expect(feedbackTile.onTap, isNotNull);
      });

      testWidgets('offers nothing that asks for money', (tester) async {
        await pumpSettings(tester, auth: auth);

        expect(find.text('Send Feedback'), findsOneWidget);
        expect(find.textContaining(asksForMoney), findsNothing);
        expect(find.byIcon(donationIcon), findsNothing);
      });
    });
  }
}
