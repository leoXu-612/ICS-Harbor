import XCTest
@testable import HarborCore

/// Opt-in only: use a disposable, prepared Harbor runtime containing trusted 7-Zip.
/// Normal test runs never download/install/launch Windows programs.
final class StandaloneSmokeTests: XCTestCase {
    func testRealWineArgumentAndFileRoundTrip() throws {
        guard let wrapper = ProcessInfo.processInfo.environment["HARBOR_SMOKE_WRAPPER"] else { throw XCTSkip("Set HARBOR_SMOKE_WRAPPER only for an explicitly authorized disposable runtime.") }
        XCTAssertTrue(FileManager.default.fileExists(atPath: wrapper + "/Contents/HarborManagedRuntime"))
        let container = ContainerRecord(name: "Smoke", wrapperPath: wrapper, origin: .managed)
        let tool = URL(fileURLWithPath: container.prefix + "/drive_c/Program Files/7-Zip/7z.exe")
        try WindowsCommand.validateFile(tool, installer: false)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Harbor Smoke 中文 & 50% " + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("Harbor Windows EXE argument and byte-for-byte round-trip.\n中文内容 0123456789\n".utf8)
        try original.write(to: root.appendingPathComponent("sample 中文.txt"))
        func run(_ args: [String], name: String) throws {
            let script = root.appendingPathComponent(name + ".cmd"), result = root.appendingPathComponent(name + ".exit")
            let batch = try WindowsCommand.batch(executable: WindowsCommand.windowsPath(tool, container: container), workingDirectory: WindowsCommand.windowsPath(root, container: container), arguments: args, installer: false, resultPath: WindowsCommand.windowsPath(result, container: container))
            try batch.write(to: script, atomically: true, encoding: .utf8)
            let process = Process(); process.executableURL = URL(fileURLWithPath: container.launcher)
            process.arguments = ["WSS-installer", script.path]
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run()
            let deadline = Date().addingTimeInterval(45)
            while !FileManager.default.fileExists(atPath: result.path) && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
            let code = try String(contentsOf: result, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
            XCTAssertEqual(code, "0", "\(name) should complete successfully")
        }
        try run(["a", "roundtrip.7z", "sample 中文.txt"], name: "compress")
        XCTAssertGreaterThan(try Data(contentsOf: root.appendingPathComponent("roundtrip.7z")).count, 0)
        try run(["x", "roundtrip.7z", "-orestored", "-y"], name: "extract")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("restored/sample 中文.txt")), original)
    }
}
