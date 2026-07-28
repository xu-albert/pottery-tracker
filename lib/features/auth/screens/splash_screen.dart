import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../providers/splash_provider.dart';
import '../../../widgets/vase_logo.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({
    super.key,
    this.animationDuration = const Duration(milliseconds: kVaseDrawMs),
  });

  final Duration animationDuration;

  /// Beat between the stroke landing and the mark starting to lift, so the
  /// finished drawing registers before it goes.
  static const exitHold = Duration(milliseconds: 250);

  /// How long the mark takes to fade and scale away.
  static const exitDuration = Duration(milliseconds: 400);

  /// How far the mark scales up as it lifts.
  static const exitScale = 1.16;

  /// Upper bound on how long the splash may hold the router, regardless of what
  /// the animation does. A stalled draw-on must never block launch, so this
  /// covers the draw, the hold and the lift together.
  static const fallback = Duration(seconds: 4);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exitController;
  late final CurvedAnimation _exit;
  Timer? _fallbackTimer;
  Timer? _holdTimer;

  @override
  void initState() {
    super.initState();
    _exitController = AnimationController(
      vsync: this,
      duration: SplashScreen.exitDuration,
    );
    _exit = CurvedAnimation(
      parent: _exitController,
      curve: const Cubic(0.4, 0, 0.2, 1),
    );
    _exitController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _release();
    });
    _fallbackTimer = Timer(SplashScreen.fallback, _release);
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _holdTimer?.cancel();
    _exit.dispose();
    _exitController.dispose();
    super.dispose();
  }

  /// The stroke has landed. Hold a beat, then lift the mark away.
  void _onDrawComplete() {
    _holdTimer = Timer(SplashScreen.exitHold, () {
      if (!mounted) return;
      _exitController.forward();
    });
  }

  void _release() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!mounted) return;
    ref.read(splashCompleteProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.cream,
      body: Center(
        child: AnimatedBuilder(
          animation: _exit,
          builder: (context, child) {
            final t = _exit.value;
            return Opacity(
              opacity: 1 - t,
              child: Transform.scale(
                scale: 1 + (SplashScreen.exitScale - 1) * t,
                child: child,
              ),
            );
          },
          child: AnimatedVaseLogo(
            size: 120,
            color: AppColors.ink,
            duration: widget.animationDuration,
            onComplete: _onDrawComplete,
          ),
        ),
      ),
    );
  }
}
