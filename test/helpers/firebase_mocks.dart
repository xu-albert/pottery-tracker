import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';

/// A fake [FirebaseAppPlatform] used to satisfy [Firebase.app()] in widget
/// tests without touching a real platform channel.
class _FakeFirebaseAppPlatform extends FirebaseAppPlatform {
  _FakeFirebaseAppPlatform()
    : super(
        defaultFirebaseAppName,
        const FirebaseOptions(
          apiKey: 'fake-api-key',
          appId: 'fake-app-id',
          messagingSenderId: 'fake-sender-id',
          projectId: 'fake-project-id',
        ),
      );
}

/// A fake [FirebasePlatform] that always resolves to a single default app,
/// so code paths that call `Firebase.app()` (e.g. `FirebaseAnalytics.instance`
/// used by the app router) don't need `Firebase.initializeApp()` to have run
/// against a real platform channel.
class _FakeFirebasePlatform extends FirebasePlatform {
  final FirebaseAppPlatform _app = _FakeFirebaseAppPlatform();

  @override
  List<FirebaseAppPlatform> get apps => [_app];

  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _app;

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async {
    return _app;
  }
}

/// Installs a fake Firebase Core platform so widgets/providers that call
/// `Firebase.app()` (directly or transitively, e.g. via
/// `FirebaseAnalytics.instance`) work in widget tests without a real
/// platform channel or `Firebase.initializeApp()`.
///
/// Call once from `setUpAll` in any test that builds `routerProvider` or
/// anything else that reaches for `Firebase.app()`.
void setupFirebaseCoreMocks() {
  Firebase.delegatePackingProperty = _FakeFirebasePlatform();
}
