import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/analytics_provider.dart';
import '../../../providers/pieces_provider.dart';

class ViewModeToggle extends ConsumerWidget {
  const ViewModeToggle({super.key});

  static const _width = 64.0;
  static const _height = 32.0;
  static const _radius = 16.0;
  static const _padding = 2.0;
  static const _thumbSize = _height - _padding * 2;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(viewModeProvider);
    final l10n = AppLocalizations.of(context)!;
    final isGrid = mode == ViewMode.grid;

    return Semantics(
      label: isGrid ? l10n.viewModeGrid : l10n.viewModeList,
      toggled: isGrid,
      child: GestureDetector(
        onTapUp: (details) {
          final tapX = details.localPosition.dx;
          if (tapX < _width / 2) {
            _setMode(ref, ViewMode.list);
          } else {
            _setMode(ref, ViewMode.grid);
          }
        },
        onHorizontalDragEnd: (details) {
          final velocity = details.primaryVelocity ?? 0;
          if (velocity > 0) {
            _setMode(ref, ViewMode.grid);
          } else if (velocity < 0) {
            _setMode(ref, ViewMode.list);
          }
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_radius),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
            child: Container(
              width: _width,
              height: _height,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.35),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                borderRadius: BorderRadius.circular(_radius),
              ),
              child: Stack(
                children: [
                  AnimatedAlign(
                    alignment:
                        isGrid ? Alignment.centerRight : Alignment.centerLeft,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: Padding(
                      padding: const EdgeInsets.all(_padding),
                      child: Container(
                        width: _thumbSize,
                        height: _thumbSize,
                        decoration: BoxDecoration(
                          color: AppColors.teal.withValues(alpha: 0.85),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Icon(
                            Icons.view_list_rounded,
                            size: 16,
                            color: isGrid
                                ? AppColors.charcoal.withValues(alpha: 0.6)
                                : Colors.white,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Center(
                          child: Icon(
                            Icons.grid_view_rounded,
                            size: 16,
                            color: isGrid
                                ? Colors.white
                                : AppColors.charcoal.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setMode(WidgetRef ref, ViewMode mode) {
    if (ref.read(viewModeProvider) == mode) return;
    ref.read(viewModeProvider.notifier).state = mode;
    ref.read(analyticsProvider).logEvent(
      name: 'view_mode_changed',
      parameters: {'mode': mode.name},
    );
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString('view_mode', mode.name);
    });
  }
}
