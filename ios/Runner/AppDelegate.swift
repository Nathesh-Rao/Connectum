import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      FlutterMethodChannel(name: "connectum/device", binaryMessenger: controller.binaryMessenger)
        .setMethodCallHandler { call, result in
          switch call.method {
          case "model":
            result(UIDevice.current.model)
          case "appVersion":
            let info = Bundle.main.infoDictionary
            let name = info?["CFBundleShortVersionString"] as? String ?? ""
            let build = info?["CFBundleVersion"] as? String ?? ""
            result("\(name) (\(build))")
          case "openSettings":
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return result(false) }
            UIApplication.shared.open(url)
            result(true)
          case "excludeFromBackup":
            guard let path = call.arguments as? String else { return result(false) }
            var url = URL(fileURLWithPath: path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            result((try? url.setResourceValues(values)) != nil)
          default:
            result(FlutterMethodNotImplemented)
          }
        }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
