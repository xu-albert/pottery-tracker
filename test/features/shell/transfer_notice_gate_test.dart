import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/database.dart';
import 'package:pottery_tracker/features/shell/widgets/transfer_notice_gate.dart';
import 'package:pottery_tracker/l10n/app_localizations_en.dart';
import 'package:pottery_tracker/providers/auth_provider.dart';
import 'package:pottery_tracker/providers/database_provider.dart';
import 'package:pottery_tracker/providers/splash_provider.dart';
import 'package:pottery_tracker/services/transfer_notice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/test_helpers.dart';

final _l10n = AppLocalizationsEn();

class _FakeAuthNotifier extends AuthNotifier {
  _FakeAuthNotifier(super.initial) : super.withState();

  void become(AuthState next) => state = next;
}

const _localOnly = AuthState(status: AuthStatus.authenticated);
const _signedIn = AuthState(status: AuthStatus.authenticated, uid: 'uid');

void main() {
  late AppDatabase db;
  late _FakeAuthNotifier auth;
  late int settingsOpened;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settingsOpened = 0;
  });

  tearDown(() => db.close());

  Future<void> addPiece() => db.customStatement(
    "INSERT INTO pieces (id, title, stage, created_at, updated_at, is_archived) "
    "VALUES ('p1', 'Bowl', 'greenware', 0, 0, 0)",
  );

  Future<void> pumpGate(
    WidgetTester tester, {
    AuthState initial = _localOnly,
    bool splashDone = true,
  }) async {
    auth = _FakeAuthNotifier(initial);
    await pumpApp(
      tester,
      TransferNoticeGate(
        onOpenSettings: () => settingsOpened++,
        child: const Text('the app'),
      ),
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith((ref) => auth),
        splashCompleteProvider.overrideWith((ref) => splashDone),
      ],
    );
    await tester.pumpAndSettle();
  }

  Finder notice() => find.text(_l10n.transferNoticeTitle);

  testWidgets('shows once to a local-only user with pottery, and records it', (
    tester,
  ) async {
    await addPiece();
    await pumpGate(tester);

    expect(notice(), findsOneWidget);
    expect(find.text(_l10n.transferNoticeMessage), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(TransferNoticeService.shownKey), isTrue);
  });

  testWidgets('"Open Settings" hands off to the settings tab', (tester) async {
    await addPiece();
    await pumpGate(tester);

    await tester.tap(find.text(_l10n.transferNoticeOpenSettings));
    await tester.pumpAndSettle();

    expect(notice(), findsNothing);
    expect(settingsOpened, 1);
  });

  testWidgets('"Not now" dismisses without opening anything', (tester) async {
    await addPiece();
    await pumpGate(tester);

    await tester.tap(find.text(_l10n.notNow));
    await tester.pumpAndSettle();

    expect(notice(), findsNothing);
    expect(settingsOpened, 0);
  });

  testWidgets('never again once shown', (tester) async {
    await addPiece();
    SharedPreferences.setMockInitialValues({
      TransferNoticeService.shownKey: true,
    });
    await pumpGate(tester);
    expect(notice(), findsNothing);
  });

  testWidgets('not for a signed-in user', (tester) async {
    await addPiece();
    await pumpGate(tester, initial: _signedIn);
    expect(notice(), findsNothing);
  });

  testWidgets('not while there is nothing to lose', (tester) async {
    await pumpGate(tester);
    expect(notice(), findsNothing);
  });

  testWidgets('waits for the splash to lift', (tester) async {
    await addPiece();
    await pumpGate(tester, splashDone: false);
    expect(notice(), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.text('the app')),
    );
    container.read(splashCompleteProvider.notifier).state = true;
    await tester.pumpAndSettle();

    expect(notice(), findsOneWidget);
  });

  testWidgets('waits for auth to resolve, then decides', (tester) async {
    await addPiece();
    await pumpGate(tester, initial: const AuthState());
    expect(notice(), findsNothing);

    auth.become(_localOnly);
    await tester.pumpAndSettle();

    expect(notice(), findsOneWidget);
  });
}
