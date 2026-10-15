import Foundation

public struct WindowsApplication: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var containerID: UUID
    public var name: String
    public var executablePath: String
    public var workingDirectory: String
    public var arguments: [String]
    public init(id: UUID = UUID(), containerID: UUID, name: String, executablePath: String, workingDirectory: String, arguments: [String] = []) {
        self.id = id; self.containerID = containerID; self.name = name
        self.executablePath = executablePath; self.workingDirectory = workingDirectory; self.arguments = arguments
    }
}

/// Use Wine's existing cmd/start/msiexec implementations, not a second installer.
public enum WindowsCommand {
    public static func validateFile(_ url: URL, installer: Bool) throws {
        let ext = url.pathExtension.lowercased()
        guard ext == "exe" || (installer && ext == "msi") else { throw HarborError.invalid(installer ? "请选择 EXE 或 MSI 安装包。" : "请选择 Windows EXE 程序。") }
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              let file = FileHandle(forReadingAtPath: url.path) else { throw HarborError.unavailable("文件不可读。请检查磁盘和访问权限，原文件未修改。") }
        defer { try? file.close() }
        let header = try file.read(upToCount: 8) ?? Data()
        let valid = ext == "exe" ? header.starts(with: [0x4d, 0x5a]) : header == Data([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1])
        guard valid else { throw HarborError.invalid("文件头与 EXE/MSI 类型不符，未执行。文件头检查不代表来源可信。") }
    }
    public static func windowsPath(_ url: URL, container: ContainerRecord) throws -> String {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        let dos = URL(fileURLWithPath: container.prefix + "/dosdevices")
        let letters = ((try? FileManager.default.contentsOfDirectory(atPath: dos.path)) ?? []).filter {
            $0.count == 2 && $0.last == ":" && $0.first?.isASCII == true && $0.first?.isLetter == true
        }.sorted { ($0 == "z:" ? "~" : $0) < ($1 == "z:" ? "~" : $1) }
        for letter in letters {
            let root = dos.appendingPathComponent(letter).resolvingSymlinksInPath().standardizedFileURL.path
            guard root == "/" || path == root || path.hasPrefix(root + "/") else { continue }
            let suffix = root == "/" ? path : String(path.dropFirst(root.count))
            return letter.uppercased() + "\\" + suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/")).replacingOccurrences(of: "/", with: "\\")
        }
        throw HarborError.unavailable("这个路径没有可用的 Wine 盘符映射。请先在运行环境中检查映射；不会擅自新增盘符。")
    }
    // All user values are quoted data. No user-supplied command text is evaluated.
    public static func quote(_ value: String, crt: Bool = false) throws -> String {
        guard !value.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }), !value.contains("\"") else {
            throw HarborError.invalid("路径和参数不能包含双引号、换行或控制字符。每行参数会作为一个完整参数传递，不是命令脚本。")
        }
        var escaped = value.replacingOccurrences(of: "%", with: "%%")
        if crt { escaped += String(value.reversed().prefix(while: { $0 == "\\" })) }
        return "\"" + escaped + "\""
    }
    public static func batch(executable: String, workingDirectory: String, arguments: [String], installer: Bool, resultPath: String) throws -> String {
        let command: String
        if installer && executable.lowercased().hasSuffix(".msi") {
            command = "\"C:\\windows\\system32\\msiexec.exe\" /i " + (try quote(executable, crt: true)) + " /norestart"
        } else {
            command = try ([quote(executable, crt: true)] + arguments.map { try quote($0, crt: true) }).joined(separator: " ")
        }
        return "@echo off\r\nsetlocal DisableDelayedExpansion\r\nchcp 65001 >nul\r\ncd /d \(try quote(workingDirectory))\r\nif errorlevel 1 exit /b 3\r\nstart \"\" /wait \(command)\r\nset \"HARBOR_RESULT=%errorlevel%\"\r\n>\(try quote(resultPath)) echo %HARBOR_RESULT%\r\nexit /b %HARBOR_RESULT%\r\n"
    }
    public static func validate(_ app: WindowsApplication, container: ContainerRecord) throws {
        guard app.containerID == container.id, !app.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw HarborError.invalid("应用名称或所属环境无效。") }
        try validateFile(URL(fileURLWithPath: app.executablePath), installer: false)
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: app.workingDirectory, isDirectory: &directory), directory.boolValue else { throw HarborError.unavailable("工作目录不存在或磁盘未连接。") }
        _ = try quote(windowsPath(URL(fileURLWithPath: app.executablePath), container: container))
        _ = try quote(windowsPath(URL(fileURLWithPath: app.workingDirectory), container: container))
        for argument in app.arguments { _ = try quote(argument, crt: true) }
    }
}
