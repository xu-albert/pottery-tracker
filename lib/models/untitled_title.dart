/// Titles the app assigns to new pieces until the potter names them.
const untitledTitlePrefix = 'Untitled Piece';

final RegExp _untitledPattern = RegExp('^$untitledTitlePrefix (\\d+)\$');

/// Whether [title] is one the app generated rather than one the potter typed.
bool isUntitledTitle(String title) => _untitledPattern.hasMatch(title);

/// The lowest unused "Untitled Piece N" given the titles already in use.
///
/// Numbers are reused once a piece is renamed or deleted, and titles that do
/// not match the generated pattern are ignored.
String nextUntitledTitle(Iterable<String> existingTitles) {
  final used = <int>{};
  for (final title in existingTitles) {
    final match = _untitledPattern.firstMatch(title);
    if (match != null) used.add(int.parse(match.group(1)!));
  }
  var n = 1;
  while (used.contains(n)) {
    n++;
  }
  return '$untitledTitlePrefix $n';
}
