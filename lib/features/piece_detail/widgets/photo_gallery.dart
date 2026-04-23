import 'dart:io';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../database/database.dart';
import '../../../core/constants/app_sizes.dart';
import 'photo_fullscreen.dart';

class PhotoGallery extends StatelessWidget {
  final List<Photo> photos;
  final ValueChanged<Photo>? onDelete;
  final ValueChanged<Photo>? onEditDate;
  final VoidCallback? onAddPhoto;
  final EdgeInsets padding;

  const PhotoGallery({
    super.key,
    required this.photos,
    this.onDelete,
    this.onEditDate,
    this.onAddPhoto,
    this.padding = const EdgeInsets.symmetric(horizontal: 32),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: GridView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: AppSizes.sm,
          mainAxisSpacing: AppSizes.sm,
          childAspectRatio: 1.0,
        ),
        itemCount: photos.length + (onAddPhoto != null ? 1 : 0),
        itemBuilder: (context, index) {
          // "+" add photo button as last item
          if (index == photos.length) {
            return GestureDetector(
              onTap: onAddPhoto,
              child: CustomPaint(
                painter: _DashedBorderPainter(
                  color: AppColors.charcoal.withValues(alpha: 0.3),
                  borderRadius: AppSizes.radiusSm,
                ),
                child: Center(
                  child: Icon(
                    Icons.add,
                    size: 32,
                    color: AppColors.charcoal.withValues(alpha: 0.4),
                  ),
                ),
              ),
            );
          }

          final photo = photos[index];
          final path = photo.thumbnailPath ?? photo.localPath;
          return GestureDetector(
            onTap: () {
              FirebaseAnalytics.instance.logEvent(
                name: 'photo_viewed_fullscreen',
              );
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PhotoFullscreen(photoPath: photo.localPath),
                ),
              );
            },
            onLongPress: photos.length > 1 && onDelete != null
                ? () => _showPhotoActions(context, photo)
                : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSizes.radiusSm),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Center(child: Icon(Icons.broken_image, size: 32)),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: GestureDetector(
                      onTap: onEditDate != null
                          ? () => onEditDate!(photo)
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          vertical: 3,
                          horizontal: 4,
                        ),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Color.fromRGBO(0, 0, 0, 0.45),
                            ],
                          ),
                        ),
                        child: Text(
                          DateFormat.yMMMd().format(photo.dateTaken),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPhotoActions(BuildContext context, Photo photo) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              onDelete?.call(photo);
            },
            child: const Text('Delete Photo'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double borderRadius;

  _DashedBorderPainter({required this.color, required this.borderRadius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(borderRadius),
    );

    final path = Path()..addRRect(rrect);
    const dashWidth = 6.0;
    const dashSpace = 4.0;

    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        final end = (distance + dashWidth).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, end), paint);
        distance += dashWidth + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color || borderRadius != oldDelegate.borderRadius;
}
