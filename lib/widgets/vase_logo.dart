import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Index of the footring subpath within [buildVasePath]'s result. It strokes
/// lighter than the rim and body.
const _footringSubpath = 2;

/// How much lighter the footring draws than the body.
const _footringWeightRatio = 0.75;

/// Approved stroke weight for the vase mark, shared by [VaseLogo] and
/// [AnimatedVaseLogo]. This is a locked design value — do not change it
/// without updating the approved design and regenerating the app icon.
const kVaseStrokeWidth = 3.6;

/// The vase silhouette centreline, authored in a 100x120 design space and
/// scaled to [size]. Single source of shape truth for the logo, the splash
/// animation, and the generated app icon.
Path buildVasePath(Size size) {
  // One factor for both axes: the 5:6 design space must not stretch to fit a
  // square box. The offsets letterbox the mark inside whatever size is given.
  final s = math.min(size.width / 100, size.height / 120);
  final ox = (size.width - 100 * s) / 2;
  final oy = (size.height - 120 * s) / 2;

  double x(double v) => v * s + ox;
  double y(double v) => v * s + oy;

  final path = Path();

  // Rim — closed mouth ellipse.
  path.moveTo(x(64), y(9.8));
  path.cubicTo(x(64.3), y(11.8), x(58), y(13.6), x(50), y(13.7));
  path.cubicTo(x(42), y(13.6), x(35.8), y(12), x(36), y(9.9));
  path.cubicTo(x(36.2), y(7.8), x(42.5), y(6.2), x(50.5), y(6.3));
  path.cubicTo(x(58.3), y(6.4), x(63.8), y(8), x(64), y(9.8));
  path.close();

  // Body — open outline: trumpet lip, down the left, across the base, up
  // the right.
  path.moveTo(x(36), y(10.4));
  path.cubicTo(x(40), y(13.5), x(44), y(17), x(44.5), y(23));
  path.cubicTo(x(44.2), y(33), x(43), y(42), x(42.5), y(51));
  path.cubicTo(x(41.5), y(59), x(36), y(64), x(32), y(70));
  path.cubicTo(x(25.5), y(78), x(20.5), y(85), x(21), y(91));
  path.cubicTo(x(21.5), y(96), x(26), y(99), x(33), y(100));
  path.cubicTo(x(33.5), y(102), x(33), y(104), x(33), y(105.5));
  path.cubicTo(x(38), y(107.5), x(62), y(107.5), x(67), y(105.5));
  path.cubicTo(x(67), y(104), x(66.5), y(102), x(67), y(100));
  path.cubicTo(x(74), y(99), x(78.5), y(96), x(79), y(91));
  path.cubicTo(x(79.5), y(85), x(74.5), y(78), x(68), y(70));
  path.cubicTo(x(64), y(64), x(58.5), y(59), x(57.5), y(51));
  path.cubicTo(x(57), y(42), x(55.8), y(33), x(55.5), y(23));
  path.cubicTo(x(56), y(17), x(60), y(13.5), x(64), y(10.4));

  // Foot — open footring line.
  path.moveTo(x(33), y(100));
  path.cubicTo(x(40), y(101.5), x(60), y(101.5), x(67), y(100));

  return path;
}

class VaseLogo extends StatelessWidget {
  const VaseLogo({
    super.key,
    required this.size,
    this.color,
    this.strokeWidth = kVaseStrokeWidth,
  });

  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: VaseLogoPainter(
        color: color ?? Theme.of(context).colorScheme.primary,
        strokeWidth: strokeWidth,
        progress: 1.0,
      ),
    );
  }
}

class VaseLogoPainter extends CustomPainter {
  VaseLogoPainter({
    required this.color,
    required this.strokeWidth,
    required this.progress,
  });

  final Color color;
  final double strokeWidth;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final metrics = buildVasePath(size).computeMetrics().toList();

    for (var i = 0; i < metrics.length; i++) {
      final metric = metrics[i];
      paint.strokeWidth = i == _footringSubpath
          ? strokeWidth * _footringWeightRatio
          : strokeWidth;
      canvas.drawPath(
        metric.extractPath(0, metric.length * progress.clamp(0.0, 1.0)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(VaseLogoPainter oldDelegate) =>
      color != oldDelegate.color ||
      strokeWidth != oldDelegate.strokeWidth ||
      progress != oldDelegate.progress;
}

class AnimatedVaseLogo extends StatefulWidget {
  const AnimatedVaseLogo({
    super.key,
    required this.size,
    this.color,
    this.strokeWidth = kVaseStrokeWidth,
    this.duration = const Duration(milliseconds: 900),
    this.onComplete,
  });

  final double size;
  final Color? color;
  final double strokeWidth;
  final Duration duration;
  final VoidCallback? onComplete;

  @override
  State<AnimatedVaseLogo> createState() => _AnimatedVaseLogoState();
}

class _AnimatedVaseLogoState extends State<AnimatedVaseLogo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _progress = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onComplete?.call();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;

    return AnimatedBuilder(
      animation: _progress,
      builder: (context, _) => CustomPaint(
        size: Size(widget.size, widget.size),
        painter: VaseLogoPainter(
          color: color,
          strokeWidth: widget.strokeWidth,
          progress: _progress.value,
        ),
      ),
    );
  }
}
