import 'dart:async';
import 'dart:io' show FileSystemException, SocketException;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/services.dart' show PlatformException;

/// Implemented by domain wrapper exceptions so [TelemetryService] can describe
/// the wrapper and its underlying cause types/codes without ever serializing
/// raw exception messages (which may carry file paths, emails, UIDs, or tokens).
abstract interface class TelemetryCauseCarrier {
  Iterable<Object> get telemetryCauses;
}

/// Sanitized exception forwarded to Crashlytics instead of the raw error.
///
/// Its string form carries only allowlisted structural metadata (runtime type,
/// static Firebase/platform error codes, numeric OS errno), never raw error
/// messages, file paths, user IDs, tokens, or user-authored text.
class SanitizedTelemetryError implements Exception {
  const SanitizedTelemetryError(this.summary);

  final String summary;

  @override
  String toString() => summary;
}

/// Guarded, sanitized Crashlytics non-fatal and breadcrumb reporter.
///
/// Every call checks Firebase readiness first and swallows reporting failures so
/// telemetry never breaks offline-first operation or tests without Firebase.
class TelemetryService {
  TelemetryService({
    bool Function()? isFirebaseReady,
    FutureOr<void> Function(String message)? log,
    FutureOr<void> Function(
      Object error,
      StackTrace stackTrace, {
      required String reason,
      required bool fatal,
    })?
    recordError,
  }) : _isFirebaseReady = isFirebaseReady ?? _defaultIsFirebaseReady,
       _log = log ?? _defaultLog,
       _recordError = recordError ?? _defaultRecordError;

  static const _offlineFirebaseCodes = <String>{
    'unavailable',
    'network-request-failed',
    'retry-limit-exceeded',
  };

  static final _safeTokenPattern = RegExp(r'^[a-zA-Z0-9._-]{1,64}$');

  final bool Function() _isFirebaseReady;
  final FutureOr<void> Function(String message) _log;
  final FutureOr<void> Function(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    required bool fatal,
  })
  _recordError;

  static bool _defaultIsFirebaseReady() {
    try {
      return Firebase.apps.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _defaultLog(String message) =>
      FirebaseCrashlytics.instance.log(message);

  static Future<void> _defaultRecordError(
    Object error,
    StackTrace stackTrace, {
    required String reason,
    required bool fatal,
  }) => FirebaseCrashlytics.instance.recordError(
    error,
    stackTrace,
    reason: reason,
    fatal: fatal,
  );

  /// Whether [error] represents a routine offline or network-reachability
  /// condition rather than an unexpected failure.
  static bool isExpectedOfflineError(Object error, {int depth = 0}) {
    if (error is SocketException || error is TimeoutException) return true;
    if (error is FirebaseException &&
        _offlineFirebaseCodes.contains(error.code)) {
      return true;
    }
    if (depth < 3 && error is TelemetryCauseCarrier) {
      final causes = error.telemetryCauses.toList();
      return causes.isNotEmpty &&
          causes.every((c) => isExpectedOfflineError(c, depth: depth + 1));
    }
    return false;
  }

  /// Builds a PII-, path-, token-, and UID-free summary of [error].
  static String describeError(Object error, {int depth = 0}) {
    final typeName = _sanitizeToken(error.runtimeType.toString());
    if (error is FirebaseException) {
      final plugin = _sanitizeToken(error.plugin);
      final code = _sanitizeToken(error.code);
      return '$typeName(plugin=$plugin, code=$code)';
    }
    if (error is PlatformException) {
      final code = _sanitizeToken(error.code);
      return '$typeName(code=$code)';
    }
    if (error is FileSystemException) {
      final errno = error.osError?.errorCode;
      return errno != null ? '$typeName(errno=$errno)' : typeName;
    }
    if (depth < 3 && error is TelemetryCauseCarrier) {
      final causes = error.telemetryCauses
          .take(4)
          .map((c) => describeError(c, depth: depth + 1))
          .toList();
      if (causes.isNotEmpty) {
        return '$typeName(${causes.join(', ')})';
      }
    }
    return typeName;
  }

  static String _sanitizeToken(String raw) =>
      _safeTokenPattern.hasMatch(raw) ? raw : 'redacted';

  static String _formatBreadcrumb(
    String context,
    Map<String, String> attributes, {
    String? errorSummary,
  }) {
    final buffer = StringBuffer(_sanitizeToken(context));
    for (final entry in attributes.entries) {
      buffer
        ..write(' ')
        ..write(_sanitizeToken(entry.key))
        ..write('=')
        ..write(_sanitizeToken(entry.value));
    }
    if (errorSummary != null) {
      buffer
        ..write(' error=')
        ..write(errorSummary);
    }
    return buffer.toString();
  }

  /// Logs a sanitized Crashlytics breadcrumb when Firebase is ready.
  Future<void> logBreadcrumb(
    String context, {
    Map<String, String> attributes = const {},
  }) async {
    if (!_isFirebaseReady()) return;
    try {
      await _log(_formatBreadcrumb(context, attributes));
    } catch (_) {}
  }

  /// Records a sanitized non-fatal error and matching breadcrumb when Firebase
  /// is ready. Routine offline errors are skipped by default.
  Future<void> recordNonFatal(
    Object error,
    StackTrace? stackTrace, {
    required String context,
    Map<String, String> attributes = const {},
    bool skipIfOffline = true,
  }) async {
    if (skipIfOffline && isExpectedOfflineError(error)) return;
    if (!_isFirebaseReady()) return;

    final safeContext = _sanitizeToken(context);
    final summary = describeError(error);
    final breadcrumb = _formatBreadcrumb(
      safeContext,
      attributes,
      errorSummary: summary,
    );
    try {
      await _log(breadcrumb);
      await _recordError(
        SanitizedTelemetryError('$safeContext: $summary'),
        stackTrace ?? StackTrace.current,
        reason: safeContext,
        fatal: false,
      );
    } catch (_) {}
  }
}
