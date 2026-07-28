import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/database/daos/pieces_dao.dart';
import 'package:pottery_tracker/features/auth/screens/splash_screen.dart';
import 'package:pottery_tracker/providers/pieces_provider.dart';
import 'package:pottery_tracker/providers/splash_provider.dart';
import 'package:pottery_tracker/widgets/vase_logo.dart';

/// The splash waits for the album's data before releasing, so tests must supply
/// it. Pass a controller to hold the data back and release it mid-test.
Future<ProviderContainer> _pumpSplash(
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
        home: SplashScreen(animationDuration: animationDuration),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('renders the animated vase mark', (tester) async {
    await _pumpSplash(tester);
    expect(find.byType(AnimatedVaseLogo), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets(
    'holds through the draw, the beat and the lift before releasing',
    (tester) async {
      final container = await _pumpSplash(tester);
      expect(container.read(splashCompleteProvider), isFalse);

      // Mid-stroke.
      await tester.pump(const Duration(milliseconds: 400));
      expect(container.read(splashCompleteProvider), isFalse);

      // Stroke has landed, but the beat and the lift have not run.
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        container.read(splashCompleteProvider),
        isFalse,
        reason: 'must not release the moment the stroke finishes',
      );

      // Past the 250ms hold, so the lift has begun but cannot have finished.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        container.read(splashCompleteProvider),
        isFalse,
        reason: 'must not release mid-lift',
      );

      // Comfortably past the end of the 400ms lift.
      await tester.pump(const Duration(milliseconds: 600));
      expect(container.read(splashCompleteProvider), isTrue);

      await tester.pump(const Duration(seconds: 5));
    },
  );

  testWidgets('the mark fades and scales as it lifts', (tester) async {
    await _pumpSplash(tester);

    Opacity opacity() => tester.widget<Opacity>(
      find.ancestor(
        of: find.byType(AnimatedVaseLogo),
        matching: find.byType(Opacity),
      ),
    );

    await tester.pump(const Duration(milliseconds: 800));
    expect(opacity().opacity, 1.0, reason: 'still holding after the stroke');

    // The hold timer fires inside this pump and starts the exit controller;
    // its ticker needs a further frame before it reports any elapsed time.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 200));
    expect(opacity().opacity, lessThan(1.0));

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('waits for the album data before releasing', (tester) async {
    final pieces = StreamController<List<PieceWithCover>>();
    addTearDown(pieces.close);

    final container = await _pumpSplash(tester, pieces: pieces.stream);

    // Draw, hold and lift all complete, but no data has arrived.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 600));
    expect(
      container.read(splashCompleteProvider),
      isFalse,
      reason: 'must not hand over a screen with nothing to paint',
    );

    pieces.add(const <PieceWithCover>[]);
    await tester.pump();
    expect(container.read(splashCompleteProvider), isTrue);

    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('fallback timer releases the splash if the stroke stalls', (
    tester,
  ) async {
    final container = await _pumpSplash(
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
    await _pumpSplash(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 6));
    // A surviving timer fails the test with "A Timer is still pending".
  });
}
