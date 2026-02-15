import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/auth_service.dart' show AuthService, SignInCancelledException;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _authService = AuthService();
  bool _loading = false;

  Future<void> _signInWithGoogle() async {
    if (_loading) return;
    ref.read(analyticsProvider).logEvent(
      name: 'sign_in_attempted',
      parameters: {'method': 'google'},
    );
    setState(() => _loading = true);
    try {
      final user = await _authService.signInWithGoogle();
      if (mounted) {
        ref.read(authProvider.notifier).signIn(user);
      }
    } on SignInCancelledException {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.signInCancelled)),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithApple() async {
    if (_loading) return;
    ref.read(analyticsProvider).logEvent(
      name: 'sign_in_attempted',
      parameters: {'method': 'apple'},
    );
    setState(() => _loading = true);
    try {
      final user = await _authService.signInWithApple();
      if (mounted) {
        ref.read(authProvider.notifier).signIn(user);
      }
    } on SignInCancelledException {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(
            SnackBar(content: Text(AppLocalizations.of(context)!.signInCancelled)),
          );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

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
                onPressed: _loading ? null : _signInWithGoogle,
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.g_mobiledata, size: 24),
                label: Text(l10n.signInWithGoogle),
              ),
              if (Platform.isIOS) ...[
                const SizedBox(height: AppSizes.md),
                ElevatedButton.icon(
                  onPressed: _loading ? null : _signInWithApple,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                  ),
                  icon: const Icon(Icons.apple, size: 24),
                  label: Text(l10n.signInWithApple),
                ),
              ],
              const SizedBox(height: AppSizes.md),
              TextButton(
                onPressed: _loading
                    ? null
                    : () {
                        ref.read(analyticsProvider).logEvent(name: 'sign_in_skipped');
                        ref.read(authProvider.notifier).skip();
                      },
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
