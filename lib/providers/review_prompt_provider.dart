import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/review_prompt_service.dart';
import 'database_provider.dart';

final reviewPromptServiceProvider = Provider<ReviewPromptService>((ref) {
  final piecesDao = ref.watch(piecesDaoProvider);
  return ReviewPromptService(
    pieceCount: () async => piecesDao.countPieces(),
  );
});
