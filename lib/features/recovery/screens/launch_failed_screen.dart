import 'package:flutter/material.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../l10n/app_localizations.dart';

/// Shown instead of the app when opening the local database failed for a
/// reason that is not a missing key — SQLCipher absent, the key store
/// refusing to persist, a corrupt file.
///
/// Before this the failure surfaced nowhere: `main` threw before the first
/// frame and the app sat on its launch image. The error is the one thing the
/// user can send along, so it is shown in full.
class LaunchFailedScreen extends StatelessWidget {
  const LaunchFailedScreen({
    super.key,
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSizes.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline, size: 56),
                const SizedBox(height: AppSizes.lg),
                Text(
                  l10n.launchFailedTitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSizes.md),
                SelectableText(
                  l10n.launchFailedMessage(error.toString()),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSizes.xl),
                FilledButton(onPressed: onRetry, child: Text(l10n.tryAgain)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
