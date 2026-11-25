import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/image_service.dart';
import 'telemetry_provider.dart';

final imageServiceProvider = Provider<ImageService>((ref) {
  return ImageService(telemetry: ref.watch(telemetryServiceProvider));
});
