import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../database/daos/pieces_dao.dart';
import 'database_provider.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

final finishedFilterProvider = StateProvider<bool>((ref) => false);

final filteredPiecesProvider = StreamProvider<List<PieceWithCover>>((ref) {
  final dao = ref.watch(piecesDaoProvider);
  final query = ref.watch(searchQueryProvider);
  final finishedOnly = ref.watch(finishedFilterProvider);
  return dao.watchAllPieces(searchQuery: query, finishedOnly: finishedOnly);
});
