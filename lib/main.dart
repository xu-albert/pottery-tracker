import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
import 'providers/photo_paths_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/pieces_provider.dart';
import 'providers/transfer_provider.dart';
import 'services/encryption_key_service.dart';
import 'services/photo_health_service.dart';
import 'services/photo_paths.dart';
import 'services/sync_service.dart';
import 'services/telemetry_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeFirebaseServices();
  await _launch();
}

/// Initializes Firebase Core, App Check, and Crashlytics error handlers.
///
/// Tracks [firebaseReady] from `Firebase.initializeApp(...)` so a startup
/// initialization failure falls back cleanly into offline-first mode instead
/// of crashing when touching `FirebaseAppCheck.instance` or
/// `FirebaseCrashlytics.instance` before `_launch()`.
@visibleForTesting
Future<bool> initializeFirebaseServices({
  Future<void> Function()? initializeApp,
  void Function()? configureFirestore,
  Future<void> Function()? activateAppCheck,
  void Function(FlutterExceptionHandler handler)? setFlutterErrorHandler,
  void Function(bool Function(Object error, StackTrace stack) handler)?
  setPlatformErrorHandler,
  FlutterExceptionHandler? recordFlutterFatalError,
  Future<void> Function(Object error, StackTrace stack, {bool fatal})?
  recordError,
  TelemetryService? telemetry,
}) async {
  final reporter = telemetry ?? TelemetryService.shared;
  var firebaseReady = false;
  try {
    await (initializeApp ??
        () => Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ))();
    firebaseReady = true;
    debugPrint('Firebase initialized successfully');
  } catch (e) {
    debugPrint('Firebase init failed: $e');
    unawaited(
      reporter.logBreadcrumb(
        'startup.firebase_init',
        attributes: {'ready': 'false'},
        error: e,
      ),
    );
  }

  if (!firebaseReady) {
    return false;
  }

  unawaited(reporter.setCustomKey('firebase_ready', true));
  unawaited(
    reporter.logBreadcrumb(
      'startup.firebase_init',
      attributes: {'ready': 'true'},
    ),
  );

  try {
    (configureFirestore ??
        () {
          FirebaseFirestore.instance.settings = const Settings(
            persistenceEnabled: false,
          );
        })();
  } catch (e, st) {
    debugPrint('Firestore settings configuration failed (non-fatal): $e');
    unawaited(
      reporter.recordNonFatal(
        e,
        st,
        context: 'startup.firestore_settings',
        skipIfOffline: false,
      ),
    );
  }

  try {
    await (activateAppCheck ??
        () => FirebaseAppCheck.instance.activate(
          androidProvider: kDebugMode
              ? AndroidProvider.debug
              : AndroidProvider.playIntegrity,
          appleProvider: kDebugMode
              ? AppleProvider.debug
              : AppleProvider.appAttest,
        ))();
    unawaited(reporter.setCustomKey('app_check_ready', true));
    unawaited(
      reporter.logBreadcrumb(
        'startup.app_check',
        attributes: {'ready': 'true'},
      ),
    );
  } catch (e, st) {
    debugPrint('App Check activation failed (non-fatal): $e');
    unawaited(reporter.setCustomKey('app_check_ready', false));
    unawaited(reporter.recordNonFatal(e, st, context: 'startup.app_check'));
  }

  try {
    final flutterFatalHandler =
        recordFlutterFatalError ??
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    final errorRecorder =
        recordError ??
        (error, stack, {bool fatal = false}) => FirebaseCrashlytics.instance
            .recordError(error, stack, fatal: fatal);

    (setFlutterErrorHandler ?? (h) => FlutterError.onError = h)(
      flutterFatalHandler,
    );
    (setPlatformErrorHandler ?? (h) => PlatformDispatcher.instance.onError = h)(
      (error, stack) {
        unawaited(
          errorRecorder(error, stack, fatal: true).catchError((Object _) {}),
        );
        return true;
      },
    );
  } catch (e) {
    debugPrint('Crashlytics setup failed (non-fatal): $e');
    unawaited(
      reporter.logBreadcrumb('startup.crashlytics_setup_failed', error: e),
    );
  }

  return true;
}

/// The documents directory and transfer backup resolved during bootstrap,
/// handed to the app's providers so every screen and service reads the same
/// container path the launch decision used.
late Directory _documentsDir;
late TransferKeyBackup _transferBackup;

Future<LocalDatabaseBootstrap> _bootstrap() async {
  AppDatabase.useSqlCipherLibrary();
  _documentsDir = await getApplicationDocumentsDirectory();
  _transferBackup = TransferKeyBackup(documentsDir: _documentsDir);
  return LocalDatabaseBootstrap(
    keys: EncryptionKeyService(),
    documentsDir: _documentsDir,
    temporaryDir: await getTemporaryDirectory(),
    prefs: await SharedPreferences.getInstance(),
    transferBackup: _transferBackup,
    telemetry: TelemetryService.shared,
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
    await TelemetryService.shared.setCustomKey('db_launch', 'failed');
    await TelemetryService.shared.recordNonFatal(
      error,
      stack,
      context: 'startup.local_database_launch_failed',
      skipIfOffline: false,
    );
    runApp(
      PreLaunchApp(
        child: LaunchFailedScreen(error: error, onRetry: _launch),
      ),
    );
    return;
  }

  switch (launch) {
    case LocalDatabaseReady(:final database):
      unawaited(TelemetryService.shared.setCustomKey('db_launch', 'ready'));
      unawaited(
        TelemetryService.shared.logBreadcrumb(
          'startup.db_launch',
          attributes: {'outcome': 'ready'},
        ),
      );
      await _runPotteryApp(database);
    case LocalDatabaseUnreadable(:final recovery):
      unawaited(
        TelemetryService.shared.setCustomKey('db_launch', 'unreadable'),
      );
      unawaited(
        TelemetryService.shared.setCustomKey(
          'db_unreadable_cause',
          recovery.cause.name,
        ),
      );
      unawaited(
        TelemetryService.shared.logBreadcrumb(
          'startup.db_launch',
          attributes: {'outcome': 'unreadable', 'cause': recovery.cause.name},
        ),
      );
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

/// Reports startup photo visibility telemetry best-effort without blocking
/// launch. Guards Firestore writes so another account's locked library or a
/// library pending wipe is never attributed to the signed-in user.
@visibleForTesting
Future<PhotoHealthSnapshot?> reportStartupPhotoHealth({
  required AppDatabase db,
  required PhotoPaths photoPaths,
  required int repairedCount,
  required SharedPreferences prefs,
  PhotoHealthService? photoHealth,
  String? Function()? currentUid,
}) {
  final service = photoHealth ?? PhotoHealthService.shared;
  String? uid;
  try {
    uid = currentUid != null
        ? currentUid()
        : (Firebase.apps.isNotEmpty
              ? FirebaseAuth.instance.currentUser?.uid
              : null);
  } catch (_) {
    uid = null;
  }

  final localOwner = prefs.getString(SyncService.localDataOwnerKey);
  final pendingWipe = prefs.getBool(SyncNotifier.pendingWipeKey) ?? false;
  final eligibleUid =
      uid != null && !pendingWipe && (localOwner == null || localOwner == uid)
      ? uid
      : null;

  return service.report(
    db: db,
    photoPaths: photoPaths,
    trigger: PhotoHealthTrigger.startup,
    repairedCount: repairedCount,
    uid: eligibleUid,
  );
}

Future<void> _runPotteryApp(AppDatabase db) async {
  final photoPaths = PhotoPaths(_documentsDir.path);
  var repaired = 0;
  // Normalize any legacy absolute photo paths left by earlier versions before
  // the first frame renders. Non-fatal on error because PhotoPaths also
  // resolves legacy absolute paths dynamically at runtime.
  try {
    repaired = await repairStoredPhotoPaths(
      db,
      photoPaths,
      telemetry: TelemetryService.shared,
    );
    if (repaired > 0) {
      debugPrint('Repaired $repaired stored photo path(s) to relative form');
    }
  } catch (error, stack) {
    debugPrint('Repairing stored photo paths failed (non-fatal): $error');
    await TelemetryService.shared.recordNonFatal(
      error,
      stack,
      context: 'startup.photo_path_repair',
      skipIfOffline: false,
    );
  }

  final prefs = await SharedPreferences.getInstance();
  unawaited(
    reportStartupPhotoHealth(
      db: db,
      photoPaths: photoPaths,
      repairedCount: repaired,
      prefs: prefs,
    ),
  );

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

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        photoPathsProvider.overrideWithValue(photoPaths),
        transferKeyBackupProvider.overrideWithValue(_transferBackup),
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
