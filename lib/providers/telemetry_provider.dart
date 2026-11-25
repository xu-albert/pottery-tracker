import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/photo_health_service.dart';
import '../services/telemetry_service.dart';

final telemetryServiceProvider = Provider<TelemetryService>((ref) {
  return TelemetryService.shared;
});

final photoHealthServiceProvider = Provider<PhotoHealthService>((ref) {
  return PhotoHealthService.shared;
});
