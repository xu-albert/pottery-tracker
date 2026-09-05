import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'database/database.dart';
import 'database/local_database_bootstrap.dart';
import 'database/transfer_key_backup.dart';
import 'features/recovery/pre_launch_app.dart';
import 'features/recovery/screens/database_recovery_screen.dart';
import 'features/recovery/screens/launch_failed_screen.dart';
import 'firebase_options.dart';
import 'providers/database_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/pieces_provider.dart';
import 'providers/transfer_provider.dart';
import 'services/encryption_key_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
  } catch (e) {
    debugPrint('Firebase init failed: $e');
  }

  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode ? AppleProvider.debug : AppleProvider.appAttest,
    );
  } catch (e) {
    debugPrint('App Check activation failed (non-fatal): $e');
  }

  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;

  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack);
    return true;
  };

  await _launch();
}

/// The transfer backup the bootstrap used, handed to the app's providers so
/// Settings reads and writes the same file the launch decision looked at.
late TransferKeyBackup _transferBackup;

Future<LocalDatabaseBootstrap> _bootstrap() async {
  AppDatabase.useSqlCipherLibrary();
  final documentsDir = await getApplicationDocumentsDirectory();
  _transferBackup = TransferKeyBackup(documentsDir: documentsDir);
  return LocalDatabaseBootstrap(
    keys: EncryptionKeyService(),
    documentsDir: documentsDir,
    temporaryDir: await getTemporaryDirectory(),
    prefs: await SharedPreferences.getInstance(),
    transferBackup: _transferBackup,
  );
}

/// Opens the local database and starts whichever app that calls for.
///
/// Three outcomes, each its own root widget: the database opened and the app
/// runs; a database is present that this device cannot open, and the
/// recovery screen runs first, calling back into [_runPotteryApp] once it has
/// a database it could; or opening failed outright, and the failure is shown
/// with a retry rather than left as a launch image that never goes away.
Future<void> _launch() async {
  final LocalDatabaseLaunch launch;
  try {
    launch = await (await _bootstrap()).launch();
  } catch (error, stack) {
    debugPrint('Opening the local database failed: $error');
    try {
      await FirebaseCrashlytics.instance.recordError(error, stack);
    } catch (_) {}
    runApp(
      PreLaunchApp(
        child: LaunchFailedScreen(error: error, onRetry: _launch),
      ),
    );
    return;
  }

  switch (launch) {
    case LocalDatabaseReady(:final database):
      await _runPotteryApp(database);
    case LocalDatabaseUnreadable(:final recovery):
      runApp(
        PreLaunchApp(
          child: DatabaseRecoveryScreen(
            recovery: recovery,
            onRecovered: _runPotteryApp,
          ),
        ),
      );
  }
}

Future<void> _runPotteryApp(AppDatabase db) async {
  final prefs = await SharedPreferences.getInstance();

  // Review-prompt session tracking
  final sessions = prefs.getInt('review_prompt_session_count') ?? 0;
  await prefs.setInt('review_prompt_session_count', sessions + 1);
  if (prefs.getString('review_prompt_first_launch_date') == null) {
    await prefs.setString(
      'review_prompt_first_launch_date',
      DateTime.now().toIso8601String(),
    );
  }

  final savedMode = prefs.getString('view_mode');
  final initialViewMode = savedMode == 'grid' ? ViewMode.grid : ViewMode.list;
  final transferPassphraseSet = _transferBackup.exists();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        transferKeyBackupProvider.overrideWithValue(_transferBackup),
        transferPassphraseSetProvider.overrideWith(
          (ref) => transferPassphraseSet,
        ),
        // Read before runApp so the read-only lock is correct on the first
        // frame: a device belonging to another account must never render the
        // album, not even for the frame before an async read resolves.
        ...deviceStateOverrides(prefs),
        viewModeProvider.overrideWith((ref) => initialViewMode),
      ],
      child: const PotteryTrackerApp(),
    ),
  );
}
