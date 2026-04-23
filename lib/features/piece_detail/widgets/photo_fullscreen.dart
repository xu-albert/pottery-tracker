import 'dart:io';
import 'package:flutter/material.dart';

class PhotoFullscreen extends StatelessWidget {
  final String photoPath;

  const PhotoFullscreen({super.key, required this.photoPath});

  @override
  Widget build(BuildContext context) {
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
          child: Image.file(File(photoPath), fit: BoxFit.contain),
        ),
      ),
    );
  }
}
