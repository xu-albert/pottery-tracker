import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../features/feedback/widgets/enjoyment_dialog.dart';

class ReviewPromptService {
  ReviewPromptService({
    DateTime Function()? now,
    InAppReview? inAppReview,
    required Future<int> Function() pieceCount,
  }) : _now = now ?? DateTime.now,
       _inAppReview = inAppReview ?? InAppReview.instance,
       _pieceCount = pieceCount;

  static const _kFirstLaunch = 'review_prompt_first_launch_date';
  static const _kSessions = 'review_prompt_session_count';
  static const _kLastPrompted = 'review_prompt_last_prompted_at';
  static const _kCompleted = 'review_prompt_completed';

  static const _minPieces = 3;
  static const _minSessions = 2;
  static const _minDaysSinceInstall = Duration(days: 3);
  static const _cooldown = Duration(days: 90);

  final DateTime Function() _now;
  final InAppReview _inAppReview;
  final Future<int> Function() _pieceCount;

  Future<bool> shouldPrompt() async {
    final prefs = await SharedPreferences.getInstance();

    final firstLaunchStr = prefs.getString(_kFirstLaunch);
    if (firstLaunchStr == null) return false;
    final firstLaunch = DateTime.parse(firstLaunchStr);
    if (_now().difference(firstLaunch) < _minDaysSinceInstall) return false;

    final sessions = prefs.getInt(_kSessions) ?? 0;
    if (sessions < _minSessions) return false;

    final lastPromptedStr = prefs.getString(_kLastPrompted);
    if (lastPromptedStr != null) {
      final lastPrompted = DateTime.parse(lastPromptedStr);
      if (_now().difference(lastPrompted) < _cooldown) return false;
    }

    final pieces = await _pieceCount();
    if (pieces < _minPieces) return false;

    return true;
  }

  Future<void> recordPrompted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastPrompted, _now().toIso8601String());
  }

  Future<void> recordCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCompleted, true);
  }

  Future<void> maybePromptAfterPieceSave(BuildContext context) async {
    if (!await shouldPrompt()) return;

    // Mark prompted atomically before showing the dialog (per design spec).
    await recordPrompted();

    if (!context.mounted) return;
    final response = await showEnjoymentDialog(context);

    switch (response) {
      case EnjoymentResponse.yes:
        if (await _inAppReview.isAvailable()) {
          await _inAppReview.requestReview();
        }
        await recordCompleted();
      case EnjoymentResponse.no:
        if (!context.mounted) return;
        context.push('/feedback');
      case EnjoymentResponse.dismissed:
        break;
    }
  }
}
