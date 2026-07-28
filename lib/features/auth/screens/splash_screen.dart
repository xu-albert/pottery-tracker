import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/splash_provider.dart';
import '../../../widgets/vase_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({
    super.key,
    this.animationDuration = const Duration(milliseconds: 900),
  });

  final Duration animationDuration;

  /// Upper bound on how long the splash may hold the router, regardless of
  /// what the animation does. A stalled draw-on must never block launch.
  static const fallback = Duration(seconds: 3);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  Timer? _fallbackTimer;

  @override
  void initState() {
    super.initState();
    _fallbackTimer = Timer(SplashScreen.fallback, _release);
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    super.dispose();
  }

  void _release() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    if (!mounted) return;
    ref.read(splashCompleteProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Center(
        child: AnimatedVaseLogo(
          size: 120,
          color: AppColors.ink,
          duration: widget.animationDuration,
          onComplete: _release,
        ),
      ),
    );
  }
}
