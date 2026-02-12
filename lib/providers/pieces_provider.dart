import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/daos/pieces_dao.dart';
import 'database_provider.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

final archivedFilterProvider = StateProvider<bool>((ref) => false);

final filteredPiecesProvider = StreamProvider<List<PieceWithCover>>((ref) {
  final dao = ref.watch(piecesDaoProvider);
  final query = ref.watch(searchQueryProvider);
  final archivedOnly = ref.watch(archivedFilterProvider);
  return dao.watchAllPieces(searchQuery: query, archivedOnly: archivedOnly);
});
