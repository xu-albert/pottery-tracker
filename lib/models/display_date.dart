import '../database/database.dart';

/// The date shown for a piece in the album and on its detail screens.
///
/// A date the potter set explicitly wins. Otherwise the piece is dated by its
/// most recent photo, and a piece with no photos falls back to when it was
/// created.
DateTime resolveDisplayDate(Piece piece, Iterable<Photo> photos) {
  final explicit = piece.displayDate;
  if (explicit != null) return explicit;
  DateTime? latest;
  for (final photo in photos) {
    if (latest == null || photo.dateTaken.isAfter(latest)) {
      latest = photo.dateTaken;
    }
  }
  return latest ?? piece.createdAt;
}
