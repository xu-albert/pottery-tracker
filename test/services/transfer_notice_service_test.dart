import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/services/transfer_notice_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late int pieces;
  late TransferNoticeService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    pieces = 0;
    service = TransferNoticeService(pieceCount: () async => pieces);
  });

  test(
    'never for a signed-in user — their pottery comes back by signing in',
    () async {
      pieces = 5;
      expect(await service.shouldShow(isLocalOnly: false), isFalse);
    },
  );

  test('not while there is nothing on the phone to lose', () async {
    expect(await service.shouldShow(isLocalOnly: true), isFalse);
  });

  test('once, for a local-only user with at least one piece', () async {
    pieces = 1;
    expect(await service.shouldShow(isLocalOnly: true), isTrue);
    await service.markShown();
    expect(await service.shouldShow(isLocalOnly: true), isFalse);
  });

  test('the shown flag survives a relaunch', () async {
    SharedPreferences.setMockInitialValues({
      TransferNoticeService.shownKey: true,
    });
    pieces = 3;
    expect(await service.shouldShow(isLocalOnly: true), isFalse);
  });
}
