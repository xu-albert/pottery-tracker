import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';

/// Lifts the row being dragged on a Manage Clays/Glazes/Tags screen.
Widget materialDragProxy(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    builder: (context, child) {
      final scale = 1.0 + 0.02 * animation.value;
      return Transform.scale(
        scale: scale,
        child: Material(
          elevation: 6 * animation.value,
          borderRadius: BorderRadius.circular(AppSizes.radiusMd),
          shadowColor: AppColors.charcoal.withValues(alpha: 0.3),
          child: child,
        ),
      );
    },
    child: child,
  );
}

/// The handle a Manage screen row is dragged by. It starts the drag at a
/// touch, so the row's own taps (edit, delete, tag colour) never do; screen
/// readers move rows with the list's own move up/down actions instead.
class MaterialDragHandle extends StatelessWidget {
  final int index;

  const MaterialDragHandle({super.key, required this.index});

  @override
  Widget build(BuildContext context) {
    return ReorderableDragStartListener(
      index: index,
      child: const SizedBox(
        width: AppSizes.minTouchTarget,
        height: AppSizes.minTouchTarget,
        child: Icon(Icons.drag_handle, color: AppColors.inputText),
      ),
    );
  }
}

/// [stored] in the order the user just dragged it into, until the stream
/// delivers the saved order.
///
/// The write lands a frame or more after the drop, and showing [stored] in
/// the meantime snaps the row back to where it was. [pending] is the dragged
/// order and [pendingBase] the list it was derived from: once [stored] is a
/// different list, the stream has spoken and its order wins.
List<T> withPendingOrder<T>(
  List<T> stored, {
  required List<T>? pending,
  required List<T>? pendingBase,
}) {
  if (pending == null || !identical(stored, pendingBase)) return stored;
  return pending;
}
