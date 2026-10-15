import Foundation

enum AppPaths {
    static var root: URL {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--data-root"), arguments.count > index + 1, arguments[index + 1].hasPrefix("/") {
            return URL(fileURLWithPath: arguments[index + 1])
        }
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Harbor")
    }
    static var containers: URL { root.appendingPathComponent("Containers") }
    static var cache: URL { root.appendingPathComponent("Cache") }
    static var requests: URL { root.appendingPathComponent("LaunchRequests") }
    static var backups: URL { root.appendingPathComponent("ConfigurationBackups") }
    // Resolve the shipped resource bundle, never SwiftPM's absolute build-cache fallback.
    static var bootstrap: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("Harbor_Harbor.bundle"), let bundle = Bundle(url: url) else { return nil }
        return bundle.url(forResource: "bootstrap", withExtension: "sh", subdirectory: "Resources")
    }
}

enum Format {
    static func duration(_ seconds: TimeInterval) -> String {
        let value = max(0, Int(seconds)); return String(format: "%02d:%02d", value / 60, value % 60)
    }
    static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    static func path(_ value: String) -> String { value.replacingOccurrences(of: NSHomeDirectory(), with: "~") }
}
