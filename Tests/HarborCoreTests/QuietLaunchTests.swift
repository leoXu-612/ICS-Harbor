import XCTest
@testable import HarborCore

final class QuietLaunchTests: XCTestCase {
    /// Opt-in: runs only Wine's built-in WScript with owned temporary files.
    /// Catches broken working-directory/Unicode handling, argument expansion,
    /// early completion, and lost nonzero exit codes in the hidden launcher.
    func testRealWineArgumentsAndExitCode() throws {
        guard let wrapper = ProcessInfo.processInfo.environment["HARBOR_LAUNCH_SMOKE_WRAPPER"] else {
            throw XCTSkip("Set HARBOR_LAUNCH_SMOKE_WRAPPER to test an authorized runtime.")
        }
        let container = ContainerRecord(name: "Quiet launch test", wrapperPath: wrapper, origin: .managed)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Harbor 中文 & 50% " + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let helper = root.appendingPathComponent("arguments.vbs")
        try """
        Set files = CreateObject("Scripting.FileSystemObject")
        Set output = files.CreateTextFile("arguments.txt", True, True)
        For i = 0 To WScript.Arguments.Count - 1
            output.WriteLine WScript.Arguments.Item(i)
        Next
        output.Close
        WScript.Quit 37
        """.write(to: helper, atomically: true, encoding: .utf8)
        let expected = ["中文 value", "%PATH%", "a&b", "!literal!", "C:\\tail\\"]
        let result = root.appendingPathComponent("request.exit")
        let batch = try WindowsCommand.batch(
            executable: "C:\\windows\\system32\\wscript.exe",
            workingDirectory: WindowsCommand.windowsPath(root, container: container),
            arguments: [WindowsCommand.windowsPath(helper, container: container)] + expected,
            installer: false, resultPath: WindowsCommand.windowsPath(result, container: container))
        let launcher = try WindowsCommand.writeLaunchRequest(batch, to: root.appendingPathComponent("request.cmd"))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: container.launcher)
        process.arguments = ["WSS-installer", launcher.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(60)
        while !FileManager.default.fileExists(atPath: result.path) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        XCTAssertEqual(try String(contentsOf: result, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), "37")
        let received = try String(contentsOf: root.appendingPathComponent("arguments.txt"), encoding: .utf16)
        XCTAssertEqual(received.components(separatedBy: .newlines).filter { !$0.isEmpty }, expected)
    }
}
