import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/features/feedback/widgets/enjoyment_dialog.dart';
import 'package:pottery_tracker/l10n/app_localizations.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Builder(builder: (_) => child),
  );

  testWidgets('returns yes when "Yes" tapped', (tester) async {
    EnjoymentResponse? result;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () async {
                result = await showEnjoymentDialog(context);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes, I love it!'));
    await tester.pumpAndSettle();
    expect(result, EnjoymentResponse.yes);
  });

  testWidgets('returns no when "Could be better" tapped', (tester) async {
    EnjoymentResponse? result;
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (context) {
            return CupertinoButton(
              onPressed: () async {
                result = await showEnjoymentDialog(context);
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Could be better'));
    await tester.pumpAndSettle();
    expect(result, EnjoymentResponse.no);
  });
}
