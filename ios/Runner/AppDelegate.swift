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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "Taps") {
      Taps.register(messenger: registrar.messenger())
    }
  }
}

/// Haptics with feedback generators made once, kept prepared and reused
/// (see lib/services/feedback.dart). Flutter's built-in HapticFeedback makes
/// a new generator for every tap, which wakes the Taptic Engine from cold
/// each time: on iPhone that briefly stalls the app and, because the engine
/// shares the audio hardware, cracks the sound.
enum Taps {
  static let light = UIImpactFeedbackGenerator(style: .light)
  static let medium = UIImpactFeedbackGenerator(style: .medium)
  static let heavy = UIImpactFeedbackGenerator(style: .heavy)
  static let selection = UISelectionFeedbackGenerator()
  static let notice = UINotificationFeedbackGenerator()

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "daily_sort/taps", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "light": light.impactOccurred(); light.prepare()
      case "medium": medium.impactOccurred(); medium.prepare()
      case "heavy": heavy.impactOccurred(); heavy.prepare()
      case "selection": selection.selectionChanged(); selection.prepare()
      case "success": notice.notificationOccurred(.success); notice.prepare()
      case "prepare":
        light.prepare(); medium.prepare(); heavy.prepare(); selection.prepare(); notice.prepare()
      default:
        result(FlutterMethodNotImplemented)
        return
      }
      result(nil)
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
