import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/auth_service.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

class SignInScreen extends ConsumerWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final authService = AuthService();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSizes.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Icon(
                Icons.emoji_objects_outlined,
                size: 80,
                color: AppColors.teal,
                semanticLabel: l10n.appTitle,
              ),
              const SizedBox(height: AppSizes.lg),
              Text(
                l10n.signInTitle,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppColors.charcoal,
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: AppSizes.sm),
              Text(
                l10n.signInSubtitle,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.charcoal.withValues(alpha: 0.7),
                    ),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () async {
                  final name = await authService.signInWithGoogle();
                  if (name != null && context.mounted) {
                    ref.read(authProvider.notifier).signIn(displayName: name);
                  }
                },
                icon: const Icon(Icons.g_mobiledata, size: 24),
                label: Text(l10n.signInWithGoogle),
              ),
              if (Platform.isIOS) ...[
                const SizedBox(height: AppSizes.md),
                ElevatedButton.icon(
                  onPressed: () async {
                    final name = await authService.signInWithApple();
                    if (name != null && context.mounted) {
                      ref.read(authProvider.notifier).signIn(displayName: name);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.apple, size: 24),
                  label: Text(l10n.signInWithApple),
                ),
              ],
              const SizedBox(height: AppSizes.md),
              TextButton(
                onPressed: () => ref.read(authProvider.notifier).skip(),
                child: Text(l10n.skipForNow),
              ),
              const SizedBox(height: AppSizes.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
