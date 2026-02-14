import 'package:flutter/material.dart';

abstract final class AppColors {
  static const cream = Color(0xFFEDE5DA);
  static const teal = Color(0xFF2D6E6E);
  static const charcoal = Color(0xFF3C3C3C);
  static const sage = Color(0xFF8FA98F);
  static const terracotta = Color(0xFFBF7B5E);
  static const peach = Color(0xFFF2C6A5);
  static const dustyRose = Color(0xFFCFA39A);
  static const warmWhite = Color(0xFFF5F0EB);
  static const divider = Color(0xFFD8CFC4);
  static const inputText = Color(0xFF6B6259);
  static const blue = Color(0xFF4A7FB5);
  static const error = Color(0xFFB3261E);
}

abstract final class TagColorPresets {
  static const colors = <Color>[
    Color(0xFF2D6E6E), // teal
    Color(0xFF4A7FB5), // blue
    Color(0xFFB55A5A), // brick red
    Color(0xFFA67BB5), // lavender
    Color(0xFFD4A843), // goldenrod
    Color(0xFFD4768A), // rose
    Color(0xFFE08A4A), // tangerine
  ];

  static String hexAt(int index) {
    final c = colors[index % colors.length];
    return c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
  }

  static String colorToHex(Color c) {
    return c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
  }

  static Color hexToColor(String hex) {
    return Color(int.parse(hex, radix: 16));
  }

  /// Returns (bgColor, textColor) with accessible contrast.
  /// Background is a light tint; text is darkened for readability.
  static (Color bg, Color text) colorsFor(Color base) {
    final bg = base.withValues(alpha: 0.18);
    // Darken the base color by blending toward black for text
    final textColor = Color.lerp(base, const Color(0xFF000000), 0.3)!;
    return (bg, textColor);
  }

  /// Default color for a new tag based on its creation order.
  static String defaultHexForIndex(int index) => hexAt(index);
}
