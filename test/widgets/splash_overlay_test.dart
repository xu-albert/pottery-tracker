import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/daos/pieces_dao.dart';
import 'package:pottery_tracker/providers/pieces_provider.dart';
import 'package:pottery_tracker/providers/splash_provider.dart';
import 'package:pottery_tracker/widgets/splash_overlay.dart';
import 'package:pottery_tracker/widgets/vase_logo.dart';

/// The overlay waits for the album's data before lifting, so tests must supply
/// it. Pass a controller to hold the data back and release it mid-test.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  Stream<List<PieceWithCover>>? pieces,
  Duration animationDuration = const Duration(milliseconds: kVaseDrawMs),
}) async {
  final container = ProviderContainer(
    overrides: [
      filteredPiecesProvider.overrideWith(
        (ref) => pieces ?? Stream.value(const <PieceWithCover>[]),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: Color(0xFF00FF00))),
            Positioned.fill(
              child: SplashOverlay(animationDuration: animationDuration),
            ),
          ],
        ),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('renders the animated vase mark', (tester) async {
    await _pump(tester);
    expect(find.byType(AnimatedVaseLogo), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('covers the app until the draw, the beat and the lift are done', (
    tester,
  ) async {
    final container = await _pump(tester);
    expect(container.read(splashCompleteProvider), isFalse);

    // Mid-stroke.
    await tester.pump(const Duration(milliseconds: 400));
    expect(container.read(splashCompleteProvider), isFalse);

    // Stroke landed, beat and lift still to run.
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      container.read(splashCompleteProvider),
      isFalse,
      reason: 'must not uncover the moment the stroke finishes',
    );

    // Past the beat, into the lift.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      container.read(splashCompleteProvider),
      isFalse,
      reason: 'must not uncover mid-lift',
    );

    // Comfortably past the lift.
    await tester.pump(const Duration(milliseconds: 700));
    expect(container.read(splashCompleteProvider), isTrue);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('the whole overlay fades, revealing the app beneath', (
    tester,
  ) async {
    await _pump(tester);

    Opacity overlayOpacity() => tester.widget<Opacity>(
      find.ancestor(
        of: find.byType(AnimatedVaseLogo),
        matching: find.byType(Opacity),
      ),
    );

    await tester.pump(const Duration(milliseconds: 800));
    expect(
      overlayOpacity().opacity,
      1.0,
      reason: 'app must stay hidden until the lift begins',
    );

    // The background must fade with the mark — a mark-only fade would leave the
    // cream in place and the app would still have to be swapped in.
    expect(
      find.descendant(
        of: find.byType(Opacity),
        matching: find.byType(ColoredBox),
      ),
      findsWidgets,
    );

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));
    expect(overlayOpacity().opacity, lessThan(1.0));

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('waits for the album data before lifting', (tester) async {
    final pieces = StreamController<List<PieceWithCover>>();
    addTearDown(pieces.close);

    final container = await _pump(tester, pieces: pieces.stream);

    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 700));
    expect(
      container.read(splashCompleteProvider),
      isFalse,
      reason: 'must not reveal a screen with nothing to paint',
    );

    pieces.add(const <PieceWithCover>[]);
    // Data arrival, then the lift's ticker registering, then the lift itself.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 700));
    expect(container.read(splashCompleteProvider), isTrue);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('fallback releases the overlay if the stroke stalls', (
    tester,
  ) async {
    final container = await _pump(
      tester,
      animationDuration: const Duration(days: 1),
    );

    await tester.pump(const Duration(milliseconds: 950));
    expect(
      container.read(splashCompleteProvider),
      isFalse,
      reason: 'animation is still running',
    );

    await tester.pump(const Duration(seconds: 4));
    expect(container.read(splashCompleteProvider), isTrue);
  });

  testWidgets('cancels its timers on dispose', (tester) async {
    await _pump(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 6));
    // A surviving timer fails the test with "A Timer is still pending".
  });
}
