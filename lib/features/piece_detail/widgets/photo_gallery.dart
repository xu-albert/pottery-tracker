import 'dart:io';
import 'package:flutter/material.dart';
import '../../../database/database.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/constants/app_sizes.dart';
import 'photo_fullscreen.dart';

class PhotoGallery extends StatefulWidget {
  final List<Photo> photos;
  final ValueChanged<Photo> onDelete;

  const PhotoGallery({
    super.key,
    required this.photos,
    required this.onDelete,
  });

  @override
  State<PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<PhotoGallery> {
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        AspectRatio(
          aspectRatio: 1,
          child: PageView.builder(
            itemCount: widget.photos.length,
            onPageChanged: (i) => setState(() => _currentPage = i),
            itemBuilder: (context, index) {
              final photo = widget.photos[index];
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        PhotoFullscreen(photoPath: photo.localPath),
                  ),
                ),
                onLongPress: () => _showPhotoActions(photo),
                child: Image.file(
                  File(photo.localPath),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image, size: 48),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSizes.sm),
          child: Text(
            l10n.photoOf(_currentPage + 1, widget.photos.length),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }

  void _showPhotoActions(Photo photo) {
    final l10n = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(l10n.deletePhoto,
                  style: const TextStyle(color: Colors.red)),
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
