import Flutter
import UIKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // One-time Keychain clear to fix corrupted state from previous crash cycles.
    // Remove this block after first successful launch.
    let cleared = UserDefaults.standard.bool(forKey: "keychain_cleared_v1")
    if !cleared {
      let secItemClasses: [CFString] = [
        kSecClassGenericPassword,
        kSecClassInternetPassword,
        kSecClassCertificate,
        kSecClassKey,
        kSecClassIdentity
      ]
      for itemClass in secItemClasses {
        let spec: NSDictionary = [kSecClass: itemClass]
        SecItemDelete(spec)
      }
      UserDefaults.standard.set(true, forKey: "keychain_cleared_v1")
      NSLog("Keychain cleared for pottery-tracker")
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
