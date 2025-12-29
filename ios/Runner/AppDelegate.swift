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
              let jsonString = args["data"] as? String else {
            print("Widget Update: Invalid arguments")
            result(FlutterError(code: "INVALID_ARGS", message: "Invalid arguments", details: nil))
            return
        }

        print("Widget Update: Saving to \(appGroupId) with key \(key)")
        print("Widget Update: Data = \(jsonString.prefix(100))...")

        // Save to shared UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: appGroupId) {
            // Save as Data for the widget to read
            if let jsonData = jsonString.data(using: .utf8) {
                sharedDefaults.set(jsonData, forKey: key)
                sharedDefaults.synchronize()
                print("Widget Update: Saved successfully")

                // Refresh widgets
                if #available(iOS 14.0, *) {
                    WidgetCenter.shared.reloadAllTimelines()
                    print("Widget Update: Triggered widget reload")
                }

                result(true)
            } else {
                print("Widget Update: Failed to convert string to data")
                result(FlutterError(code: "FAILED", message: "Could not convert data", details: nil))
            }
        } else {
            print("Widget Update: Could not access app group \(appGroupId)")
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
