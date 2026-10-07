import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  // Never delete Keychain items here. The SQLCipher key lives in the Keychain
  // (see EncryptionKeyService) while the database it opens lives in Documents,
  // so any native wipe that runs before Dart leaves an encrypted journal
  // nothing can open. test/ios/app_delegate_test.dart guards this; the launch
  // itself is the device check in docs/local-database-key.md.
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
