import Foundation

struct AppConfig {
    private(set) var values: [String: String] = [:]

    mutating func load() {
        values = EnvLoader.load()
    }

    func value(for key: String) -> String {
        values[key, default: ""]
    }

    var firebaseAPIKey: String { value(for: "FIREBASE_API_KEY") }
    var firebaseProjectID: String { value(for: "FIREBASE_PROJECT_ID") }
    var firebaseAppID: String { value(for: "FIREBASE_APP_ID") }
    var firebaseSenderID: String { value(for: "FIREBASE_SENDER_ID") }
    var firebaseStorageBucket: String { value(for: "FIREBASE_STORAGE_BUCKET") }
    var weatherKitBundleID: String { value(for: "WEATHERKIT_BUNDLE_ID") }
}

enum EnvLoader {
    static func load() -> [String: String] {
        var result: [String: String] = [:]
        let sources = [
            Bundle.main.url(forResource: ".env", withExtension: nil),
            FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(".env"),
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent(".env")
        ]

        for url in sources.compactMap({ $0 }) {
            if let data = try? Data(contentsOf: url), let contents = String(data: data, encoding: .utf8) {
                mergeEnv(into: &result, contents: contents)
            }
        }
        return result
    }

    private static func mergeEnv(into dict: inout [String: String], contents: String) {
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
                var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix("\"") && value.hasSuffix("\"") {
                    value = String(value.dropFirst().dropLast())
                }
                dict[key] = value
            }
        }
    }
}
