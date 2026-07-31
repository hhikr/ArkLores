import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let appIconChannelName = "arklores/app_icon"

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: appIconChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "setIcon" else {
          result(FlutterMethodNotImplemented)
          return
        }
        guard
          UIApplication.shared.supportsAlternateIcons,
          let arguments = call.arguments as? [String: Any],
          let icon = arguments["icon"] as? String
        else {
          result(false)
          return
        }
        let iconName: String?
        switch icon {
        case "light":
          iconName = "AppIconLight"
        case "dark":
          iconName = "AppIconDark"
        default:
          result(FlutterError(
            code: "invalid_icon",
            message: "Unknown launcher icon: \(icon)",
            details: nil
          ))
          return
        }
        UIApplication.shared.setAlternateIconName(iconName) { error in
          result(error == nil)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
