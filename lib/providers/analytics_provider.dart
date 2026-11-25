import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final analyticsProvider = Provider<FirebaseAnalytics?>((ref) {
  if (Firebase.apps.isEmpty) return null;
  return FirebaseAnalytics.instance;
});
