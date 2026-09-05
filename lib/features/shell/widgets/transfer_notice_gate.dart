import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/database_provider.dart';
import '../../../providers/splash_provider.dart';
import '../../../services/transfer_notice_service.dart';

final transferNoticeServiceProvider = Provider<TransferNoticeService>((ref) {
  final piecesDao = ref.watch(piecesDaoProvider);
  return TransferNoticeService(pieceCount: piecesDao.countPieces);
});

/// Shows the one-time transfer notice over [child] once the app is settled:
/// auth resolved to a local-only session, the splash lifted, and there is at
/// least one piece.
///
/// Lives in the shell rather than the album because it is about the device,
/// not the list — and the shell is the one surface that is mounted exactly
/// when the user is inside the app and not on a lock or sign-in screen.
class TransferNoticeGate extends ConsumerStatefulWidget {
  const TransferNoticeGate({
    super.key,
    required this.child,
    required this.onOpenSettings,
  });

  final Widget child;
  final VoidCallback onOpenSettings;

  @override
  ConsumerState<TransferNoticeGate> createState() => _TransferNoticeGateState();
}

class _TransferNoticeGateState extends ConsumerState<TransferNoticeGate> {
  bool _decided = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (_decided || !mounted) return;
    if (!ref.read(splashCompleteProvider)) return;
    final auth = ref.read(authProvider);
    if (auth.status == AuthStatus.unknown) return;
    // A signed-in user's pottery comes back by signing in; nothing to say.
    if (!auth.isLocalOnly) {
      _decided = true;
      return;
    }
    final service = ref.read(transferNoticeServiceProvider);
    if (!await service.shouldShow(isLocalOnly: true)) {
      _decided = true;
      return;
    }
    if (!mounted || _decided) return;
    _decided = true;
    // Marked before it is shown, so a dismissal by any route counts.
    await service.markShown();
    if (!mounted) return;

    final l10n = AppLocalizations.of(context)!;
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.transferNoticeTitle),
        content: Text(l10n.transferNoticeMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.notNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.transferNoticeOpenSettings),
          ),
        ],
      ),
    );
    if (openSettings == true && mounted) widget.onOpenSettings();
  }

  @override
  Widget build(BuildContext context) {
    // Whichever of the two conditions settles last is the one that fires.
    ref.listen<bool>(splashCompleteProvider, (_, done) {
      if (done) _maybeShow();
    });
    ref.listen<AuthState>(authProvider, (_, next) {
      if (next.status != AuthStatus.unknown) _maybeShow();
    });
    return widget.child;
  }
}
