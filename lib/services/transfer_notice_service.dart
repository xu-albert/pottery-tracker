import 'package:shared_preferences/shared_preferences.dart';

/// Decides whether to tell a user, once, that pottery kept on this phone
/// alone does not move to a new phone by itself.
///
/// The database key is stored so that it never enters a backup, which is the
/// hardening; the transfer passphrase is the way around it for a user with
/// no cloud account. Neither helps a user who does not know. So the first
/// time a local-only user opens the app with something to lose — at least
/// one piece — they are told, and pointed at Settings. Once: it is a
/// warning, not a nag, and the settings section carries the same text for
/// whenever they come back to it.
class TransferNoticeService {
  TransferNoticeService({required Future<int> Function() pieceCount})
    : _pieceCount = pieceCount;

  static const shownKey = 'transferNoticeShown';

  final Future<int> Function() _pieceCount;

  /// True when the notice has not been shown and there is pottery on this
  /// phone that is not backed up anywhere else.
  Future<bool> shouldShow({required bool isLocalOnly}) async {
    if (!isLocalOnly) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(shownKey) == true) return false;
    return await _pieceCount() > 0;
  }

  Future<void> markShown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(shownKey, true);
  }
}
