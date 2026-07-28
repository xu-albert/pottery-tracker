import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Set to true once the splash draw-on animation has finished (or its
/// fallback timer has fired). The router will not leave `/splash` until this
/// is true, so the launch animation is never cut off mid-stroke.
final splashCompleteProvider = StateProvider<bool>((ref) => false);
