import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'firebase_options.dart';
import 'providers/pieces_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');
    FirebaseFirestore.instance.settings =
        const Settings(persistenceEnabled: false);
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
      appleProvider:
          kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );
  } catch (e) {
    debugPrint('App Check activation failed (non-fatal): $e');
  }

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack);
    return true;
  };

  final prefs = await SharedPreferences.getInstance();
  final savedMode = prefs.getString('view_mode');
  final initialViewMode =
      savedMode == 'grid' ? ViewMode.grid : ViewMode.list;

  runApp(ProviderScope(
    overrides: [
      viewModeProvider.overrideWith((ref) => initialViewMode),
    ],
    child: const PotteryTrackerApp(),
  ));
}
