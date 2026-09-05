import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/piece_writer.dart';
import 'database_provider.dart';
import 'image_service_provider.dart';
import 'sync_provider.dart';

final pieceWriterProvider = Provider<PieceWriter>((ref) {
  return PieceWriter(
    piecesDao: ref.watch(piecesDaoProvider),
    photosDao: ref.watch(photosDaoProvider),
    imageService: ref.watch(imageServiceProvider),
    syncTrigger: ref.watch(syncTriggerProvider),
  );
});
