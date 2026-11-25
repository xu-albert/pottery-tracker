import 'dart:async';
import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../database/database.dart';
import 'photo_paths.dart';
import 'telemetry_service.dart';

/// Lifecycle point at which a [PhotoHealthSnapshot] was computed.
enum PhotoHealthTrigger {
  startup('startup'),
  postSync('post_sync');

  const PhotoHealthTrigger(this.value);

  final String value;
}

/// Aggregate, zero-PII visibility snapshot of active local photo rows.
class PhotoHealthSnapshot {
  const PhotoHealthSnapshot({
    required this.trigger,
    required this.totalPhotos,
    required this.presentLocal,
    required this.repairedCount,
    required this.missingLocal,
    required this.missingWithCloud,
    required this.missingUnrecoverable,
  });

  final PhotoHealthTrigger trigger;
  final int totalPhotos;
  final int presentLocal;
  final int repairedCount;
  final int missingLocal;
  final int missingWithCloud;
  final int missingUnrecoverable;

  bool get allVisible => missingLocal == 0;
}

/// Sanitized non-fatal marker emitted when one or more photo rows have neither
/// a readable local file nor a cloud URL.
class PhotoMissingUnrecoverableException implements Exception {
  const PhotoMissingUnrecoverableException({
    required this.missingUnrecoverable,
    required this.totalPhotos,
  });

  final int missingUnrecoverable;
  final int totalPhotos;

  @override
  String toString() =>
      'PhotoMissingUnrecoverableException('
      'missingUnrecoverable=$missingUnrecoverable, '
      'totalPhotos=$totalPhotos)';
}

/// Computes and reports privacy-safe photo visibility telemetry across
/// Firebase Analytics, Firestore (`users/{uid}/diagnostics/photo_health`), and
/// Crashlytics (via [TelemetryService]).
///
/// Every reporting call is guarded on Firebase readiness, runs best-effort with
/// errors swallowed/sanitized, and never blocks offline startup or sync.
class PhotoHealthService {
  /// Process-wide singleton shared between startup (`main.dart`) and Riverpod
  /// providers so the once-per-session unrecoverable non-fatal guard spans both
  /// `startup` and `post_sync` checks.
  static final PhotoHealthService shared = PhotoHealthService();

  static const String analyticsEventName = 'photo_health_check';
  static const String firestoreCollection = 'diagnostics';
  static const String firestoreDocId = 'photo_health';
  static const String unrecoverableContext = 'photo.missing_unrecoverable';

  PhotoHealthService({
    bool Function()? isFirebaseReady,
    TelemetryService? telemetry,
    FutureOr<void> Function(String name, Map<String, Object> parameters)?
    logAnalyticsEvent,
    FirebaseFirestore? firestore,
    Future<PackageInfo> Function()? packageInfoLoader,
    String Function()? platformResolver,
  }) : _isFirebaseReady = isFirebaseReady ?? _defaultIsFirebaseReady,
       _telemetry = telemetry ?? TelemetryService.shared,
       _logAnalyticsEvent = logAnalyticsEvent ?? _defaultLogAnalyticsEvent,
       _firestoreOverride = firestore,
       _packageInfoLoader = packageInfoLoader ?? PackageInfo.fromPlatform,
       _platformResolver = platformResolver ?? _defaultPlatform;

  final bool Function() _isFirebaseReady;
  final TelemetryService _telemetry;
  final FutureOr<void> Function(String name, Map<String, Object> parameters)
  _logAnalyticsEvent;
  final FirebaseFirestore? _firestoreOverride;
  final Future<PackageInfo> Function() _packageInfoLoader;
  final String Function() _platformResolver;

  bool _unrecoverableReported = false;
  String? _cachedAppVersion;

  static bool _defaultIsFirebaseReady() {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _defaultLogAnalyticsEvent(
    String name,
    Map<String, Object> parameters,
  ) => FirebaseAnalytics.instance.logEvent(name: name, parameters: parameters);

  static String _defaultPlatform() {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }

  Future<String> _resolveAppVersion() async {
    final cached = _cachedAppVersion;
    if (cached != null) return cached;
    try {
      final pkg = await _packageInfoLoader();
      final version = pkg.buildNumber.isNotEmpty
          ? '${pkg.version}+${pkg.buildNumber}'
          : pkg.version;
      final resolved = version.isNotEmpty ? version : 'unknown';
      _cachedAppVersion = resolved;
      return resolved;
    } catch (_) {
      return 'unknown';
    }
  }

  String _resolvePlatform() {
    try {
      final value = _platformResolver();
      return value.isNotEmpty ? value : 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  /// Inspects active rows in [db] against [photoPaths] on disk and builds an
  /// aggregate [PhotoHealthSnapshot] containing zero PII or file paths.
  Future<PhotoHealthSnapshot> computeSnapshot({
    required AppDatabase db,
    required PhotoPaths photoPaths,
    required PhotoHealthTrigger trigger,
    int repairedCount = 0,
  }) async {
    final allPhotos = await db.photosDao.getAllPhotos();
    var presentLocal = 0;
    var missingLocal = 0;
    var missingWithCloud = 0;
    var missingUnrecoverable = 0;

    for (final photo in allPhotos) {
      if (photoPaths.resolveMainFile(photo).existsSync()) {
        presentLocal++;
      } else {
        missingLocal++;
        final hasCloud = photo.cloudUrl?.trim().isNotEmpty ?? false;
        if (hasCloud) {
          missingWithCloud++;
        } else {
          missingUnrecoverable++;
        }
      }
    }

    return PhotoHealthSnapshot(
      trigger: trigger,
      totalPhotos: allPhotos.length,
      presentLocal: presentLocal,
      repairedCount: repairedCount,
      missingLocal: missingLocal,
      missingWithCloud: missingWithCloud,
      missingUnrecoverable: missingUnrecoverable,
    );
  }

  /// Computes a [PhotoHealthSnapshot] and reports it best-effort to Analytics,
  /// Firestore (when signed in), and Crashlytics. Never throws.
  Future<PhotoHealthSnapshot?> report({
    required AppDatabase db,
    required PhotoPaths photoPaths,
    required PhotoHealthTrigger trigger,
    int repairedCount = 0,
    String? uid,
    bool? emitUnrecoverableOnStartup,
  }) async {
    final PhotoHealthSnapshot snapshot;
    try {
      snapshot = await computeSnapshot(
        db: db,
        photoPaths: photoPaths,
        trigger: trigger,
        repairedCount: repairedCount,
      );
    } catch (e) {
      unawaited(
        _telemetry.logBreadcrumb('photo_health.snapshot_failed', error: e),
      );
      return null;
    }

    await reportSnapshot(
      snapshot,
      uid: uid,
      emitUnrecoverableOnStartup: emitUnrecoverableOnStartup,
    );
    return snapshot;
  }

  /// Reports a precomputed [snapshot] across all three Firebase telemetry
  /// surfaces. Guarded on Firebase readiness and swallows all reporting errors.
  Future<void> reportSnapshot(
    PhotoHealthSnapshot snapshot, {
    String? uid,
    bool? emitUnrecoverableOnStartup,
  }) async {
    unawaited(
      _telemetry.logBreadcrumb(
        'photo_health.check',
        attributes: {
          'trigger': snapshot.trigger.value,
          'total': '${snapshot.totalPhotos}',
          'present': '${snapshot.presentLocal}',
          'repaired': '${snapshot.repairedCount}',
          'missing': '${snapshot.missingLocal}',
          'missing_cloud': '${snapshot.missingWithCloud}',
          'missing_unrecoverable': '${snapshot.missingUnrecoverable}',
          'all_visible': '${snapshot.allVisible}',
        },
      ),
    );

    if (!_isFirebaseReady()) return;

    final appVersion = await _resolveAppVersion();
    final platform = _resolvePlatform();

    await Future.wait([
      _reportCrashlytics(
        snapshot,
        uid: uid,
        emitUnrecoverableOnStartup: emitUnrecoverableOnStartup,
      ),
      _reportAnalytics(snapshot, appVersion: appVersion),
      _reportFirestore(
        snapshot,
        uid: uid,
        appVersion: appVersion,
        platform: platform,
      ),
    ]);
  }

  Future<void> _reportCrashlytics(
    PhotoHealthSnapshot snapshot, {
    required String? uid,
    bool? emitUnrecoverableOnStartup,
  }) async {
    try {
      await _telemetry.setCustomKey(
        'photos_missing_unrecoverable_count',
        snapshot.missingUnrecoverable,
      );
      await _telemetry.setCustomKey('photos_all_visible', snapshot.allVisible);
      await _telemetry.setCustomKey('photos_total_count', snapshot.totalPhotos);
      await _telemetry.setCustomKey(
        'photos_missing_local_count',
        snapshot.missingLocal,
      );

      final canEmitOnStartup =
          emitUnrecoverableOnStartup ?? (uid == null || uid.isEmpty);
      final canEmitUnrecoverable =
          snapshot.trigger == PhotoHealthTrigger.postSync || canEmitOnStartup;
      if (canEmitUnrecoverable &&
          snapshot.missingUnrecoverable > 0 &&
          !_unrecoverableReported) {
        _unrecoverableReported = true;
        await _telemetry.recordNonFatal(
          PhotoMissingUnrecoverableException(
            missingUnrecoverable: snapshot.missingUnrecoverable,
            totalPhotos: snapshot.totalPhotos,
          ),
          StackTrace.current,
          context: unrecoverableContext,
          attributes: {
            'trigger': snapshot.trigger.value,
            'missing_unrecoverable': '${snapshot.missingUnrecoverable}',
            'total': '${snapshot.totalPhotos}',
          },
          skipIfOffline: false,
        );
      }
    } catch (_) {}
  }

  Future<void> _reportAnalytics(
    PhotoHealthSnapshot snapshot, {
    required String appVersion,
  }) async {
    try {
      await _logAnalyticsEvent(analyticsEventName, {
        'app_version': appVersion,
        'trigger': snapshot.trigger.value,
        'total_photos': snapshot.totalPhotos,
        'present_local': snapshot.presentLocal,
        'repaired_count': snapshot.repairedCount,
        'missing_local': snapshot.missingLocal,
        'missing_with_cloud': snapshot.missingWithCloud,
        'missing_unrecoverable': snapshot.missingUnrecoverable,
        'all_visible': snapshot.allVisible ? 1 : 0,
      });
    } catch (e) {
      if (!TelemetryService.isExpectedOfflineError(e)) {
        unawaited(
          _telemetry.logBreadcrumb('photo_health.analytics_failed', error: e),
        );
      }
    }
  }

  Future<void> _reportFirestore(
    PhotoHealthSnapshot snapshot, {
    required String? uid,
    required String appVersion,
    required String platform,
  }) async {
    if (uid == null || uid.isEmpty) return;
    try {
      final firestore = _firestoreOverride ?? FirebaseFirestore.instance;
      await firestore
          .collection('users')
          .doc(uid)
          .collection(firestoreCollection)
          .doc(firestoreDocId)
          .set({
            'appVersion': appVersion,
            'platform': platform,
            'trigger': snapshot.trigger.value,
            'checkedAt': FieldValue.serverTimestamp(),
            'totalPhotos': snapshot.totalPhotos,
            'presentLocal': snapshot.presentLocal,
            'repairedCount': snapshot.repairedCount,
            'missingLocal': snapshot.missingLocal,
            'missingWithCloud': snapshot.missingWithCloud,
            'missingUnrecoverable': snapshot.missingUnrecoverable,
            'allVisible': snapshot.allVisible,
          }, SetOptions(merge: true));
    } catch (e) {
      if (!TelemetryService.isExpectedOfflineError(e)) {
        unawaited(
          _telemetry.logBreadcrumb('photo_health.firestore_failed', error: e),
        );
      }
    }
  }
}
