import Flutter
import UIKit
import Firebase
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        FirebaseApp.configure()
        GeneratedPluginRegistrant.register(with: self)

        // Set up widget method channel
        let controller = window?.rootViewController as! FlutterViewController
        let widgetChannel = FlutterMethodChannel(
            name: "com.ornimetrics.app/widget",
            binaryMessenger: controller.binaryMessenger
        )

        widgetChannel.setMethodCallHandler { [weak self] (call, result) in
            switch call.method {
            case "updateWidget":
                self?.updateWidget(call: call, result: result)
            case "refreshWidget":
                self?.refreshWidget(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func updateWidget(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let appGroupId = args["appGroupId"] as? String,
              let key = args["key"] as? String,
              let data = args["data"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }

        // Save to shared UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: appGroupId) {
            sharedDefaults.set(data.data(using: .utf8), forKey: key)
            sharedDefaults.synchronize()

            // Refresh widgets
            if #available(iOS 14.0, *) {
                WidgetCenter.shared.reloadAllTimelines()
            }

            result(true)
        } else {
            result(FlutterError(code: "FAILED", message: "Could not access app group", details: nil))
        }
    }

    private func refreshWidget(result: @escaping FlutterResult) {
        if #available(iOS 14.0, *) {
            WidgetCenter.shared.reloadAllTimelines()
            result(true)
        } else {
            result(false)
        }
    }
}
