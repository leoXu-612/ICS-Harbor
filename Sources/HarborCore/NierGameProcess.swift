import Foundation

public enum NierGameProcess {
    public static func containsGame(_ commands: [String]) -> Bool {
        commands.contains {
            $0.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last?.lowercased() == "nierautomata.exe"
        }
    }
    public static func isRunning() throws -> Bool {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "comm="]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw HarborError.unavailable("无法确认游戏是否仍在运行，未修改显示配置。")
        }
        return containsGame(text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) })
    }
}
