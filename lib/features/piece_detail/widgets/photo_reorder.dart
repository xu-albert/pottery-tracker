import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../database/database.dart';

class PhotoReorderScreen extends StatefulWidget {
  final List<Photo> photos;

  const PhotoReorderScreen({super.key, required this.photos});

  @override
  State<PhotoReorderScreen> createState() => _PhotoReorderScreenState();
}

class _PhotoReorderScreenState extends State<PhotoReorderScreen> {
  late List<Photo> _photos;
  bool _hasChanges = false;

  @override
  void initState() {
    super.initState();
    _photos = List.of(widget.photos);
  }

  Future<bool> _onPopAttempt() async {
    if (!_hasChanges) return true;

    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Changes will be discarded.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _onPopAttempt();
        if (shouldPop && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reorder Photos'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, _photos),
              child: const Text('Done'),
            ),
          ],
        ),
        body: ReorderableListView.builder(
          padding: const EdgeInsets.symmetric(
            vertical: AppSizes.sm,
            horizontal: AppSizes.md,
          ),
          itemCount: _photos.length,
          onReorder: (oldIndex, newIndex) {
            setState(() {
              if (newIndex > oldIndex) newIndex--;
              final item = _photos.removeAt(oldIndex);
              _photos.insert(newIndex, item);
              _hasChanges = true;
            });
          },
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, child) {
                final scale = 1.0 + 0.02 * animation.value;
                return Transform.scale(
                  scale: scale,
                  child: Material(
                    elevation: 6 * animation.value,
                    borderRadius: BorderRadius.circular(AppSizes.radiusMd),
                    shadowColor: AppColors.charcoal.withValues(alpha: 0.3),
                    child: child,
                  ),
                );
              },
              child: child,
            );
          },
          itemBuilder: (context, index) {
            final photo = _photos[index];
            final path = photo.thumbnailPath ?? photo.localPath;
            return Card(
              key: ValueKey(photo.id),
              margin: const EdgeInsets.symmetric(vertical: AppSizes.xs),
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.sm),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppSizes.radiusSm),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: Image.file(
                          File(path),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: AppColors.peach.withValues(alpha: 0.3),
                            child: const Icon(Icons.broken_image, size: 24),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSizes.md),
                    Expanded(
                      child: Text(
                        DateFormat.yMMMd().format(photo.dateTaken),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.all(AppSizes.sm),
                        child: Icon(
                          Icons.drag_handle,
                          color: AppColors.inputText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
