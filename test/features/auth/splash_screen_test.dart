import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/features/auth/screens/splash_screen.dart';
import 'package:pottery_tracker/providers/splash_provider.dart';
import 'package:pottery_tracker/widgets/vase_logo.dart';

Future<ProviderContainer> _pumpSplash(WidgetTester tester) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: SplashScreen()),
    ),
  );
  return container;
}

void main() {
  testWidgets('renders the animated vase mark', (tester) async {
    await _pumpSplash(tester);
    expect(find.byType(AnimatedVaseLogo), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('sets splashComplete when the stroke finishes', (tester) async {
    final container = await _pumpSplash(tester);

    expect(container.read(splashCompleteProvider), isFalse);

    await tester.pump(const Duration(milliseconds: 950));
    expect(container.read(splashCompleteProvider), isTrue);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('fallback timer releases the splash if the stroke stalls', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: SplashScreen(animationDuration: Duration(days: 1)),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 950));
    expect(
      container.read(splashCompleteProvider),
      isFalse,
      reason: 'animation is still running',
    );

    await tester.pump(const Duration(seconds: 3));
    expect(container.read(splashCompleteProvider), isTrue);
  });

  testWidgets('cancels the fallback timer on dispose', (tester) async {
    await _pumpSplash(tester);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(seconds: 5));
    // A surviving timer fails the test with "A Timer is still pending".
  });
}
