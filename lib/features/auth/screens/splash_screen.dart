import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_colors.dart';
import '../../../database/daos/pieces_dao.dart';
import '../../../providers/pieces_provider.dart';
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
  /// the animation does or whether the album's data ever arrives. A stalled
  /// draw-on or a hung query must never block launch.
  static const fallback = Duration(seconds: 4);

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exitController;
  late final CurvedAnimation _exit;
  ProviderSubscription<AsyncValue<List<PieceWithCover>>>? _piecesSub;
  Timer? _fallbackTimer;
  Timer? _holdTimer;
  bool _liftDone = false;

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
      if (status == AnimationStatus.completed) {
        _liftDone = true;
        _releaseIfReady();
      }
    });

    // Subscribing here starts the album's query while the mark is still being
    // drawn, instead of when the album mounts. Without it the app is handed a
    // route with nothing to paint: the page fades in empty and the content
    // pops in afterwards, which is what made the handoff feel abrupt.
    _piecesSub = ref.listenManual(
      filteredPiecesProvider,
      (previous, next) => _releaseIfReady(),
    );

    _fallbackTimer = Timer(SplashScreen.fallback, _release);
  }

  @override
  void dispose() {
    _fallbackTimer?.cancel();
    _holdTimer?.cancel();
    _piecesSub?.close();
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

  /// Leaves only once the mark has gone *and* the app has something to show.
  void _releaseIfReady() {
    if (!_liftDone || !mounted) return;
    if (!ref.read(filteredPiecesProvider).hasValue) return;
    _release();
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
