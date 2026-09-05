import 'package:flutter/cupertino.dart';

import '../../../l10n/app_localizations.dart';

/// Asks the potter to confirm deleting a piece. Resolves true only when the
/// destructive action was tapped.
Future<bool> confirmDeletePiece(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final confirmed = await showCupertinoDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(l10n.deletePieceConfirmTitle),
      content: Text(l10n.deletePieceConfirmMessage),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(l10n.cancel),
        ),
        CupertinoDialogAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(l10n.delete),
        ),
      ],
    ),
  );
  return confirmed == true;
}
