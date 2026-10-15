import Foundation

public struct StateStore {
    public let root: URL
    public init(root: URL) { self.root = root }
    public var stateURL: URL { root.appendingPathComponent("state.json") }
    public var backupURL: URL { root.appendingPathComponent("state.previous.json") }
    public func load() throws -> AppState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return AppState() }
        let value = try JSONDecoder().decode(AppState.self, from: Data(contentsOf: stateURL))
        guard value.schema == 1 else { throw HarborError.protected("此配置来自更新版本，未覆盖原文件。") }
        return value
    }
    public func save(_ state: AppState) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let bytes = try encoder.encode(state)
        if let previous = try? Data(contentsOf: stateURL) { try previous.write(to: backupURL, options: .atomic) }
        try bytes.write(to: stateURL, options: .atomic)
    }
}

public enum LogRedactor {
    public static func redact(_ text: String, home: String = NSHomeDirectory()) -> String {
        text.components(separatedBy: .newlines).map { line in
            let lower = line.lowercased()
            if ["token", "ticket", "cookie", "password", "authorization", "access_key", "steamid"].contains(where: lower.contains) { return "[敏感日志行已隐藏]" }
            return line.replacingOccurrences(of: home, with: "~")
                .replacingOccurrences(of: "https?://[^\\s\\\"<>]+", with: "[URL 已隐藏]", options: .regularExpression)
                .replacingOccurrences(of: #"\[U:\d+:\d+\]|\b7656119\d{10}\b"#, with: "[账号标识已隐藏]", options: .regularExpression)
        }.joined(separator: "\n")
    }
}
