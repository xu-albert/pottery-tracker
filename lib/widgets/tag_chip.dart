import 'package:flutter/material.dart';

import '../core/constants/app_colors.dart';

/// A small "#tag" pill used wherever a piece's tags are listed.
///
/// A tag with a colour chosen in Manage Tags uses that colour; any other tag
/// gets a stable colour picked from a short palette by hashing its name, so
/// the same tag always looks the same across the album.
class TagChip extends StatelessWidget {
  final String tag;
  final Color? customColor;

  const TagChip({super.key, required this.tag, this.customColor});

  // Each entry: (background tint colour, accessible text colour).
  static const defaultColors = [
    (AppColors.teal, AppColors.teal), // #2D6E6E — dark enough
    (AppColors.terracotta, Color(0xFF8B5536)), // darken terracotta for text
    (AppColors.dustyRose, Color(0xFF8B5D55)), // darken dustyRose for text
    (AppColors.sage, Color(0xFF536B53)), // darken sage for text
    (AppColors.blue, AppColors.blue), // #4A7FB5 — dark enough
  ];

  /// The (background, text) colours for [tag], mirroring the widget's own
  /// choice so callers and tests can reason about it without building.
  static (Color bg, Color text) colorsFor(String tag, Color? customColor) {
    if (customColor != null) return TagColorPresets.colorsFor(customColor);
    final defaults = defaultColors[tag.hashCode.abs() % defaultColors.length];
    return (defaults.$1.withValues(alpha: 0.18), defaults.$2);
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall;
    final (bgColor, textColor) = colorsFor(tag, customColor);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 150),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '#',
              style: textStyle?.copyWith(
                color: textColor.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                tag,
                style: textStyle?.copyWith(color: textColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
