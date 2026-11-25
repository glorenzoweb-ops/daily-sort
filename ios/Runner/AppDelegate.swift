import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CloudSync") {
      CloudSync.register(messenger: registrar.messenger())
    }
  }
}

/// Streak and stats in iCloud key-value storage (see lib/services/cloud_sync.dart).
/// Without the iCloud capability the store stays local to this phone.
enum CloudSync {
  static let key = "backup"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "daily_sort/cloud", binaryMessenger: messenger)
    let store = NSUbiquitousKeyValueStore.default
    store.synchronize()
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "get":
        result(store.string(forKey: key))
      case "set":
        if let code = call.arguments as? String {
          store.set(code, forKey: key)
          store.synchronize()
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
