import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/app_colors.dart';
import '../database/daos/pieces_dao.dart';
import '../providers/pieces_provider.dart';
import '../providers/splash_provider.dart';
import 'vase_logo.dart';

/// Paints the launch mark *above* the app rather than beside it.
///
/// The splash used to be a route, which meant the app could not exist until the
/// splash stopped existing — so however the handoff was animated, there was a
/// gap while the shell and album were built. As an overlay the app builds and
/// loads underneath while the mark is still being drawn, and lifting the overlay
/// reveals a screen that is already there.
class SplashOverlay extends ConsumerStatefulWidget {
  const SplashOverlay({
    super.key,
    this.animationDuration = const Duration(milliseconds: kVaseDrawMs),
  });

  final Duration animationDuration;

  /// Beat between the stroke landing and the overlay starting to lift, so the
  /// finished drawing registers before it goes.
  static const exitHold = Duration(milliseconds: 250);

  /// How long the overlay takes to lift away, revealing the app beneath.
  static const exitDuration = Duration(milliseconds: 450);

  /// How far the mark scales up as it lifts.
  static const exitScale = 1.16;

  /// Upper bound on how long the overlay may cover the app, regardless of what
  /// the animation does or whether the album's data ever arrives.
  static const fallback = Duration(seconds: 4);

  @override
  ConsumerState<SplashOverlay> createState() => _SplashOverlayState();
}

class _SplashOverlayState extends ConsumerState<SplashOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exitController;
  late final CurvedAnimation _exit;
  ProviderSubscription<AsyncValue<List<PieceWithCover>>>? _piecesSub;
  Timer? _fallbackTimer;
  Timer? _holdTimer;
  bool _drawDone = false;

  @override
  void initState() {
    super.initState();
    _exitController = AnimationController(
      vsync: this,
      duration: SplashOverlay.exitDuration,
    );
    _exit = CurvedAnimation(
      parent: _exitController,
      curve: const Cubic(0.4, 0, 0.2, 1),
    );
    _exitController.addStatusListener((status) {
      if (status == AnimationStatus.completed) _release();
    });

    // Starts the album's query while the mark is still being drawn, so the
    // screen underneath has its data by the time the overlay lifts.
    _piecesSub = ref.listenManual(
      filteredPiecesProvider,
      (previous, next) => _liftIfReady(),
    );

    _fallbackTimer = Timer(SplashOverlay.fallback, _release);
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

  /// The stroke has landed. Hold a beat, then lift once the app is ready.
  void _onDrawComplete() {
    _drawDone = true;
    _holdTimer = Timer(SplashOverlay.exitHold, _liftIfReady);
  }

  void _liftIfReady() {
    if (!mounted || !_drawDone) return;
    if (_holdTimer?.isActive ?? false) return;
    if (!ref.read(filteredPiecesProvider).hasValue) return;
    if (_exitController.status == AnimationStatus.dismissed) {
      _exitController.forward();
    }
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
    return AnimatedBuilder(
      animation: _exit,
      builder: (context, child) {
        final t = _exit.value;
        // The whole overlay fades, background included, so the app is revealed
        // rather than swapped in.
        return Opacity(
          opacity: 1 - t,
          child: ColoredBox(
            color: AppColors.cream,
            child: Center(
              child: Transform.scale(
                scale: 1 + (SplashOverlay.exitScale - 1) * t,
                child: child,
              ),
            ),
          ),
        );
      },
      child: AnimatedVaseLogo(
        size: 120,
        color: AppColors.ink,
        duration: widget.animationDuration,
        onComplete: _onDrawComplete,
      ),
    );
  }
}

/// Renders [SplashOverlay] until it releases, then nothing.
class SplashGate extends ConsumerWidget {
  const SplashGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(splashCompleteProvider)) return const SizedBox.shrink();
    return const Positioned.fill(child: IgnorePointer(child: SplashOverlay()));
  }
}
