import Foundation

public struct NierDisplaySnapshot: Codable, Sendable {
    public let documentsPath: String
    public let outputIndex: Int
    public let outputName: String
    public init(documentsPath: String, outputIndex: Int, outputName: String) {
        self.documentsPath = documentsPath; self.outputIndex = outputIndex; self.outputName = outputName
    }
    public func validate() throws {
        guard documentsPath.range(of: #"^[A-Za-z]:[\\/]"#, options: .regularExpression) != nil,
              !documentsPath.unicodeScalars.contains(where: { $0.value < 32 }),
              !documentsPath.replacingOccurrences(of: "\\", with: "/").split(separator: "/").contains("..") else {
            throw HarborError.invalid("显示预检返回了无效的 Windows 文档路径，未修改游戏配置。")
        }
        guard (0..<32).contains(outputIndex), !outputName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !outputName.unicodeScalars.contains(where: { $0.value < 32 }) else {
            throw HarborError.unavailable("无法确认主显示器，未修改 NieR 显示配置。")
        }
    }
}

public struct NierDisplayRepair: Sendable {
    public let message: String
    public let backup: URL?
}

/// Only the verified Steam NieR format is supported; no game saves are reset.
public enum NierDisplayConfiguration {
    public static let appID = "524220"

    public static func repair(directory: URL, target: NierDisplaySnapshot, backupRoot: URL, isGameRunning: () throws -> Bool) throws -> NierDisplayRepair {
        guard try !isGameRunning() else { throw HarborError.protected("NieR 正在运行，未修改显示设置。请保存并退出后再启动。") }
        try target.validate()
        let fm = FileManager.default
        let system = directory.appendingPathComponent("SystemData.dat")
        let graphic = directory.appendingPathComponent("Graphic.ini")
        guard fm.fileExists(atPath: system.path) else { return .init(message: "首次启动，由 NieR 创建显示配置。", backup: nil) }
        let original = try read(system, limit: 72)
        guard original.count == 72, (1...16384).contains(word(original, 8)), (1...16384).contains(word(original, 12)),
              word(original, 16) <= 2, word(original, 24) < 32 else {
            throw HarborError.invalid("NieR 显示配置格式不受支持，原文件保留。")
        }
        let oldGraphic = fm.fileExists(atPath: graphic.path) ? try read(graphic, limit: 16384) : nil
        let oldOutput = try oldGraphic.map(outputName)
        let changedIndex = word(original, 24) != UInt32(target.outputIndex)
        let changedOutput = oldOutput.map { $0.caseInsensitiveCompare(target.outputName) != .orderedSame } ?? false
        guard changedIndex || changedOutput else { return .init(message: "显示配置已匹配主屏：\(target.outputName)。", backup: nil) }
        let backup = backupRoot.appendingPathComponent("NieR-display-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try preserve(original, to: backup.appendingPathComponent("SystemData.dat"))
        if let oldGraphic { try preserve(oldGraphic, to: backup.appendingPathComponent("Graphic.ini")) }
        // Do not overwrite a game/Steam write that happened while creating backups.
        guard try Data(contentsOf: system) == original,
              (fm.fileExists(atPath: graphic.path) ? try Data(contentsOf: graphic) : nil) == oldGraphic else {
            throw HarborError.protected("NieR 配置在检查期间发生变化，未应用修正。请退出游戏后重试。")
        }
        guard try !isGameRunning() else {
            throw HarborError.protected("NieR 在预检期间启动了，未修改显示设置。请保存并退出后再试。")
        }
        var updated = original
        let index = UInt32(target.outputIndex)
        for byte in 0..<4 { updated[24 + byte] = UInt8(truncatingIfNeeded: index >> (byte * 8)) }
        do {
            if changedIndex { try updated.write(to: system, options: .atomic) }
            // A stale output name can override even a corrected monitor index.
            if oldGraphic != nil { try fm.removeItem(at: graphic) }
        } catch {
            do {
                try original.write(to: system, options: .atomic)
                if let oldGraphic { try oldGraphic.write(to: graphic, options: .atomic) }
            } catch {
                throw HarborError.unavailable("显示修正未完成，恢复也失败。原始配置备份：\(backup.path)")
            }
            throw HarborError.unavailable("显示修正失败，已恢复原配置。备份：\(backup.path)")
        }
        return .init(message: "已修正 NieR 显示配置，使用主屏：\(target.outputName)。备份：\(backup.path)", backup: backup)
    }
    private static func read(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let bytes = try handle.read(upToCount: limit + 1) ?? Data()
        guard bytes.count <= limit else { throw HarborError.invalid("NieR 显示配置大小异常，原文件保留。") }
        return bytes
    }
    private static func preserve(_ bytes: Data, to url: URL) throws {
        try bytes.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        guard try Data(contentsOf: url) == bytes else { throw HarborError.unavailable("显示配置备份校验失败，未修改原文件。") }
    }
    private static func word(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | (UInt32(data[offset + $1]) << ($1 * 8)) }
    }
    private static func outputName(_ bytes: Data) throws -> String {
        guard let text = String(data: bytes, encoding: .utf8) else { throw HarborError.invalid("Graphic.ini 编码无法识别，原文件保留。") }
        let values = text.components(separatedBy: .newlines).filter { $0.hasPrefix("Output=") }
        guard values.count == 1 else { throw HarborError.invalid("Graphic.ini 输出字段无法识别，原文件保留。") }
        let hex = Array(values[0].dropFirst(7))
        guard hex.count == 258 else { throw HarborError.invalid("Graphic.ini 输出格式不受支持，原文件保留。") }
        var data = Data()
        for i in stride(from: 0, to: hex.count, by: 2) {
            guard let byte = UInt8(String(hex[i...i+1]), radix: 16) else { throw HarborError.invalid("Graphic.ini 输出字段损坏，原文件保留。") }
            data.append(byte)
        }
        guard let decoded = String(data: data.prefix(128), encoding: .utf16LittleEndian),
              let end = decoded.firstIndex(of: "\0"), !decoded[..<end].isEmpty else {
            throw HarborError.invalid("Graphic.ini 显示器名称无法识别，原文件保留。")
        }
        return String(decoded[..<end])
    }
}
