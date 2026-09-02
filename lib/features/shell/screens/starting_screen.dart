import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../widgets/vase_logo.dart';

/// The route the app holds on while auth is still resolving, on a device some
/// account already has a stake in.
///
/// Neither of the other two can be shown safely in that window. The lock
/// screen would tell an owner opening the app offline that their own pottery
/// belongs to somebody else, and the album is a write surface on a device that
/// may turn out to be refused — mounted, and hit-testable through the splash,
/// which wraps only its own overlay in `IgnorePointer`. That is what the hold
/// buys: not a head start withheld, since [SplashOverlay] subscribes to the
/// album's query itself and it runs either way, but a writable screen that is
/// never mounted before the app knows whose device this is.
///
/// It carries the launch mark rather than nothing, because the splash lifts on
/// a fallback timer that a slow sign-in check can outlast.
class StartingScreen extends StatelessWidget {
  const StartingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.cream,
      body: Center(child: VaseLogo(size: 120, color: AppColors.ink)),
    );
  }
}
