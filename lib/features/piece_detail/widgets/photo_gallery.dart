import 'dart:io';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../database/database.dart';
import '../../../core/constants/app_sizes.dart';
import 'photo_fullscreen.dart';

class PhotoGallery extends StatefulWidget {
  final List<Photo> photos;
  final ValueChanged<Photo> onDelete;
  final ValueChanged<Photo>? onEditDate;

  const PhotoGallery({
    super.key,
    required this.photos,
    required this.onDelete,
    this.onEditDate,
  });

  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  final _scrollController = ScrollController();
  bool _showLeftGradient = false;
  bool _showRightGradient = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
  }

  @override
  void didUpdateWidget(PhotoGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photos.length != widget.photos.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkOverflow());
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _checkOverflow() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    setState(() {
      _showRightGradient = maxScroll > 0;
      _showLeftGradient = _scrollController.position.pixels > 0;
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final atStart = pos.pixels <= 0;
    final atEnd = pos.pixels >= pos.maxScrollExtent - 1;
    if (_showLeftGradient != !atStart || _showRightGradient != !atEnd) {
      setState(() {
        _showLeftGradient = !atStart;
        _showRightGradient = !atEnd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final photoSize = screenWidth * 0.72;
    final sidePadding = (screenWidth - photoSize) / 2;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final gradientWidth = photoSize * 0.3;

    const dateLabelHeight = 24.0;

    return SizedBox(
      height: photoSize + dateLabelHeight,
      child: Stack(
        children: [
          ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: sidePadding),
            itemCount: widget.photos.length,
            separatorBuilder: (_, _) => const SizedBox(width: AppSizes.md),
            itemBuilder: (context, index) {
              final photo = widget.photos[index];
              return SizedBox(
                width: photoSize,
                child: Column(
                  children: [
                    GestureDetector(
                      onTap: () {
                        FirebaseAnalytics.instance.logEvent(
                          name: 'photo_viewed_fullscreen',
                        );
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PhotoFullscreen(photoPath: photo.localPath),
                          ),
                        );
                      },
                      onLongPress: () => _showPhotoActions(photo),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                        child: SizedBox(
                          width: photoSize,
                          height: photoSize,
                          child: Image.file(
                            File(photo.localPath),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const Center(
                              child: Icon(Icons.broken_image, size: 48),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: widget.onEditDate != null
                          ? () => widget.onEditDate!(photo)
                          : null,
                      child: Text(
                        DateFormat.yMMMd().format(photo.dateTaken),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.charcoal.withValues(alpha: 0.6),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_showLeftGradient)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: gradientWidth,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerRight,
                      end: Alignment.centerLeft,
                      colors: [
                        bgColor.withValues(alpha: 0),
                        bgColor.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_showRightGradient)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: gradientWidth,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        bgColor.withValues(alpha: 0),
                        bgColor.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showPhotoActions(Photo photo) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text(
                'Delete photo',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(ctx);
                widget.onDelete(photo);
              },
            ),
          ],
        ),
      ),
    );
  }
}
