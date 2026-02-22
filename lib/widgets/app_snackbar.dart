import 'dart:async';
import 'package:flutter/material.dart';

abstract final class AppSnackbar {
  static OverlayEntry? _currentEntry;
  static _SnackbarWidgetState? _currentState;

  static void show(
    BuildContext context, {
    required String message,
    Duration duration = const Duration(seconds: 2),
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    hide();

    final overlay = Overlay.of(context, rootOverlay: true);
    late final OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => _SnackbarWidget(
        message: message,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        onDismissed: () {
          entry.remove();
          if (_currentEntry == entry) {
            _currentEntry = null;
            _currentState = null;
          }
        },
        onStateCreated: (state) => _currentState = state,
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  static void hide() {
    _currentState?.dismiss();
    _currentState = null;
    // If state wasn't available (already dismissed), remove entry directly
    final entry = _currentEntry;
    _currentEntry = null;
    if (entry != null && _currentState == null) {
      try {
        entry.remove();
      } catch (_) {}
    }
  }
}

class _SnackbarWidget extends StatefulWidget {
  final String message;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback onDismissed;
  final ValueChanged<_SnackbarWidgetState> onStateCreated;

  const _SnackbarWidget({
    required this.message,
    required this.duration,
    this.actionLabel,
    this.onAction,
    required this.onDismissed,
    required this.onStateCreated,
  });

  @override
  State<_SnackbarWidget> createState() => _SnackbarWidgetState();
}

class _SnackbarWidgetState extends State<_SnackbarWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;
  Timer? _timer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated(this);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer(widget.duration, () {
      if (!_dismissed) dismiss();
    });
  }

  void dismiss() {
    if (_dismissed) return;
    _dismissed = true;
    _timer?.cancel();
    _controller.reverse().then((_) {
      if (mounted) widget.onDismissed();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom +
        kBottomNavigationBarHeight +
        16;

    return Positioned(
      left: 16,
      right: 16,
      bottom: bottomPadding,
      child: SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: const Color(0xFF323232),
            borderRadius: BorderRadius.circular(8),
            elevation: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.message,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  if (widget.actionLabel != null)
                    TextButton(
                      onPressed: () {
                        widget.onAction?.call();
                        dismiss();
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF4DB6AC),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(48, 36),
                      ),
                      child: Text(
                        widget.actionLabel!,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
