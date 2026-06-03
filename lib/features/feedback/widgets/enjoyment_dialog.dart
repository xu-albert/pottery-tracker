import 'package:flutter/cupertino.dart';
import '../../../l10n/app_localizations.dart';

enum EnjoymentResponse { yes, no, dismissed }

Future<EnjoymentResponse> showEnjoymentDialog(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final result = await showCupertinoDialog<EnjoymentResponse>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(l10n.enjoymentDialogTitle),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx, EnjoymentResponse.no),
          child: Text(l10n.enjoymentDialogNo),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx, EnjoymentResponse.yes),
          child: Text(l10n.enjoymentDialogYes),
        ),
      ],
    ),
  );
  return result ?? EnjoymentResponse.dismissed;
}
