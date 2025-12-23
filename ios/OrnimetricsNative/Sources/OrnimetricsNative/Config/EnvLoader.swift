import Foundation

struct EnvLoader {
    static func load() -> [String: String] {
        let fileNames = [".env", ".env.example", "env"]
        for name in fileNames {
            if let url = Bundle.main.url(forResource: name, withExtension: nil),
               let contents = try? String(contentsOf: url) {
                return parse(contents: contents)
            }
        }

        if let url = try? FileManager.default
            .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent(".env"),
           let contents = try? String(contentsOf: url) {
            return parse(contents: contents)
        }

        return ProcessInfo.processInfo.environment
    }

    private static func parse(contents: String) -> [String: String] {
        var output: [String: String] = [:]
        for rawLine in contents.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            output[key] = value
        }
        return output
    }
}
