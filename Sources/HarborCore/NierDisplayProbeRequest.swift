import Foundation

public struct NierDisplayProbeRequest: Sendable {
    public let launcher: URL
    public let completion: URL
    public let report: URL
    public let directory: URL

    public static func prepare(container: ContainerRecord, root: URL, source: URL) throws -> Self {
        let fm = FileManager.default
        let compiler = URL(fileURLWithPath: container.prefix + "/drive_c/windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe")
        guard fm.isReadableFile(atPath: compiler.path) else {
            throw HarborError.unavailable("此环境缺少显示预检所需的 Wine Mono 编译器，未修改游戏配置。")
        }
        let directory = root.appendingPathComponent("Display-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try fm.copyItem(at: source, to: directory.appendingPathComponent("probe.cs"))
        let batch = """
        @echo off
        setlocal DisableDelayedExpansion
        chcp 65001 >nul
        "C:\\windows\\Microsoft.NET\\Framework64\\v4.0.30319\\csc.exe" /nologo /platform:x64 /target:winexe /r:System.Web.Extensions.dll /out:probe.exe probe.cs >compile.log 2>&1
        if errorlevel 1 goto failed
        "probe.exe"
        if errorlevel 1 goto failed
        >done.tmp echo 0
        move /y done.tmp done.txt >nul
        exit /b 0
        :failed
        >done.tmp echo 1
        move /y done.tmp done.txt >nul
        exit /b 1
        """.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"
        let launcher = try WindowsCommand.writeLaunchRequest(batch, to: directory.appendingPathComponent("request.cmd"))
        return .init(launcher: launcher, completion: directory.appendingPathComponent("done.txt"), report: directory.appendingPathComponent("report.json"), directory: directory)
    }
    public func result() throws -> NierDisplaySnapshot {
        guard try String(contentsOf: completion, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) == "0" else {
            throw HarborError.unavailable("显示预检失败，未修改游戏配置。诊断：\(directory.path)")
        }
        let handle = try FileHandle(forReadingFrom: report); defer { try? handle.close() }
        let data = try handle.read(upToCount: 16385) ?? Data()
        guard data.count <= 16384 else { throw HarborError.invalid("显示预检返回了异常数据。") }
        let result = try JSONDecoder().decode(NierDisplaySnapshot.self, from: data)
        try result.validate()
        return result
    }
}
