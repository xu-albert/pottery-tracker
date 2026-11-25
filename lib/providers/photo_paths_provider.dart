import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/photo_paths.dart';

/// Resolves stored photo paths against the current app documents directory.
///
/// Overridden in `main()` before `runApp` with the real documents directory so
/// every screen and service resolves paths synchronously on the first frame.
/// Defaults to [PhotoPaths.passthrough] so isolated widget tests can supply
/// fixture paths without mocking `path_provider`.
final photoPathsProvider = Provider<PhotoPaths>(
  (ref) => const PhotoPaths.passthrough(),
);
