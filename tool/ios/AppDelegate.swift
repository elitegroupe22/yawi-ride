import Flutter
import UIKit
import UserNotifications
import PushKit
import flutter_callkit_incoming

// Généré par tool/prepare_ios.py : notifications Yawi + appels VoIP (PushKit → écran d'appel CallKit).
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  private var voipRegistry: PKPushRegistry?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Notifications affichées application ouverte (flutter_local_notifications, sonnerie Yawi).
    UNUserNotificationCenter.current().delegate = self
    let registry = PKPushRegistry(queue: DispatchQueue.main)
    registry.delegate = self
    registry.desiredPushTypes = [.voIP]
    voipRegistry = registry
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // Jeton VoIP : transmis à l'application Flutter, qui l'enregistre auprès de Yawi.
  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  // Apple exige d'afficher un appel CallKit pour chaque notification VoIP reçue.
  func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload,
                    for type: PKPushType, completion: @escaping () -> Void) {
    guard type == .voIP else { completion(); return }
    let p = payload.dictionaryPayload
    let id = p["call_id"] as? String ?? UUID().uuidString
    let data = flutter_callkit_incoming.Data(
      id: id,
      nameCaller: p["caller_name"] as? String ?? "Yawi",
      handle: p["caller_detail"] as? String ?? "Appel Yawi",
      type: 0)
    data.appName = "Yawi"
    data.duration = (Int(p["ring_seconds"] as? String ?? "") ?? 40) * 1000
    data.extra = ["call_id": id]
    if let plugin = SwiftFlutterCallkitIncomingPlugin.sharedInstance {
      plugin.showCallkitIncoming(data, fromPushKit: true) { completion() }
    } else {
      completion()
    }
  }
}
