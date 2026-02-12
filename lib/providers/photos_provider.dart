import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/database.dart';
import 'database_provider.dart';

final photosForPieceProvider =
    StreamProvider.family<List<Photo>, String>((ref, pieceId) {
  final dao = ref.watch(photosDaoProvider);
  return dao.watchPhotosForPiece(pieceId);
});
