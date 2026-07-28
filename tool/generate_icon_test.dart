import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pottery_tracker/core/constants/app_colors.dart';
import 'package:pottery_tracker/widgets/vase_logo.dart';

/// Renders the approved vase path to assets/icon/icon.png at 1024x1024.
/// Run with: flutter test tool/generate_icon_test.dart
void main() {
  testWidgets('generates a full-bleed 1024px icon with the mark inside', (
    tester,
  ) async {
    const canvas = 1024.0;

    // The mark fills ~72% of the tile's height. Chosen from a rendered
    // comparison at 60/80/120/180px: 61% read timid beside denser home-screen
    // icons, 78% crowded the tile's rounded corners.
    const markSize = 740.0;

    // The icon's stroke in design-space units — 1.55x the splash's 3.6, the
    // uplift the design round settled on for small-size legibility. Converted
    // to canvas pixels with the same factor buildVasePath uses, so the two
    // cannot drift apart if markSize changes.
    const strokeInDesignUnits = 5.6;
    const stroke = strokeInDesignUnits * markSize / 120;

    // A path that spills past the canvas would ship a clipped icon.
    final markBounds = buildVasePath(
      const Size(markSize, markSize),
    ).getBounds();
    expect(markBounds.left, greaterThanOrEqualTo(-stroke / 2));
    expect(markBounds.top, greaterThanOrEqualTo(-stroke / 2));
    expect(markBounds.right, lessThanOrEqualTo(markSize + stroke / 2));
    expect(markBounds.bottom, lessThanOrEqualTo(markSize + stroke / 2));

    final recorder = ui.PictureRecorder();
    final c = Canvas(recorder);

    c.drawRect(
      const Rect.fromLTWH(0, 0, canvas, canvas),
      Paint()..color = AppColors.cream,
    );

    final inset = (canvas - markSize) / 2;
    c.save();
    c.translate(inset, inset);
    // Reuse the widget's painter so the icon and the splash animation cannot
    // drift apart — it already applies the lighter footring weight.
    VaseLogoPainter(
      color: AppColors.ink,
      strokeWidth: stroke,
      progress: 1.0,
    ).paint(c, const Size(markSize, markSize));
    c.restore();

    final image = await recorder.endRecording().toImage(
      canvas.toInt(),
      canvas.toInt(),
    );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);

    expect(image.width, 1024);
    expect(image.height, 1024);
    expect(bytes, isNotNull);

    final file = File('assets/icon/icon.png')
      ..writeAsBytesSync(bytes!.buffer.asUint8List());

    // A near-empty PNG means the path failed to render.
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(2000));
  });
}
