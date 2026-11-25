import 'dart:io';
import 'package:flutter/material.dart';

class PhotoFullscreen extends StatelessWidget {
  final String photoPath;

  const PhotoFullscreen({super.key, required this.photoPath});

  @override
  Widget build(BuildContext context) {
    final file = File(photoPath);
    const fallback = Icon(Icons.broken_image, color: Colors.white54, size: 48);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: file.existsSync()
              ? Image.file(
                  file,
                  key: ValueKey(file.path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => fallback,
                )
              : fallback,
        ),
      ),
    );
  }
}
