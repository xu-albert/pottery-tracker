import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/core/constants/app_colors.dart';
import 'package:pottery_tracker/widgets/vase_logo.dart';

void main() {
  group('buildVasePath', () {
    test('scales to the requested size and stays inside its bounds', () {
      final path = buildVasePath(const Size(120, 120));
      final bounds = path.getBounds();

      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.top, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(120));
      expect(bounds.bottom, lessThanOrEqualTo(120));
    });

    test('keeps the approved 5:6 proportions in a square box', () {
      // The design space is 100x120. Scaling x and y independently to fill a
      // square stretches the mark; this asserts it does not.
      final square = buildVasePath(const Size(120, 120)).getBounds();
      final design = buildVasePath(const Size(100, 120)).getBounds();

      expect(
        square.width / square.height,
        closeTo(design.width / design.height, 0.001),
        reason: 'a square box must letterbox the mark, not stretch it',
      );
      expect(square.width / square.height, closeTo(0.582, 0.005));
    });

    test('has rim, body and footring as three subpaths in order', () {
      final path = buildVasePath(const Size(120, 120));
      final metrics = path.computeMetrics().toList();

      expect(metrics, hasLength(3));
      expect(metrics[0].isClosed, isTrue, reason: 'rim ellipse is closed');
      expect(metrics[1].isClosed, isFalse, reason: 'body outline is open');
      expect(metrics[2].isClosed, isFalse, reason: 'footring line is open');

      // The footring is much the shortest run; body much the longest.
      expect(metrics[2].length, lessThan(metrics[0].length));
      expect(metrics[1].length, greaterThan(metrics[0].length));
    });
  });

  group('footring timing window', () {
    test('matches where the body stroke crosses the footring ends', () {
      final metrics = buildVasePath(
        const Size(120, 120),
      ).computeMetrics().toList();
      final body = metrics[1];
      final foot = metrics[2];

      final footLeft = foot.getTangentForOffset(0)!.position;
      final footRight = foot.getTangentForOffset(foot.length)!.position;

      double fractionNearest(Offset target) {
        var best = 0.0;
        var bestDistance = double.infinity;
        const samples = 2000;
        for (var i = 0; i <= samples; i++) {
          final f = i / samples;
          final point = body.getTangentForOffset(body.length * f)!.position;
          final d = (point - target).distanceSquared;
          if (d < bestDistance) {
            bestDistance = d;
            best = f;
          }
        }
        return best;
      }

      // The painter gates the footring on 0.41 -> 0.59 so the ring appears
      // under the pen. If the path is ever redrawn these must be re-measured.
      expect(fractionNearest(footLeft), closeTo(0.41, 0.02));
      expect(fractionNearest(footRight), closeTo(0.59, 0.02));
    });

    test('body reaches the footring left end before the right end', () {
      final metrics = buildVasePath(
        const Size(120, 120),
      ).computeMetrics().toList();
      final foot = metrics[2];
      // Left-to-right: the ring must run the same way the pen crosses the base.
      expect(
        foot.getTangentForOffset(0)!.position.dx,
        lessThan(foot.getTangentForOffset(foot.length)!.position.dx),
      );
    });
  });

  group('VaseLogo', () {
    testWidgets('renders the mark', (tester) async {
      const boundaryKey = Key('vase_logo_golden_boundary');

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            backgroundColor: AppColors.cream,
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: VaseLogo(size: 120, color: AppColors.ink),
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byKey(boundaryKey),
        matchesGoldenFile('goldens/vase_logo.png'),
      );
    });
  });

  group('AnimatedVaseLogo', () {
    testWidgets('fires onComplete once the stroke finishes', (tester) async {
      var completed = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AnimatedVaseLogo(
                size: 120,
                color: AppColors.ink,
                duration: const Duration(milliseconds: 900),
                onComplete: () => completed++,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 400));
      expect(completed, 0, reason: 'still mid-stroke');

      await tester.pump(const Duration(milliseconds: 600));
      expect(completed, 1);

      await tester.pump(const Duration(milliseconds: 500));
      expect(completed, 1, reason: 'must not fire twice');
    });
  });
}
