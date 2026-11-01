import XCTest
import AppKit
import CoreGraphics
@testable import HarborCore

final class NierDisplayTests: XCTestCase {
    private func fixture(index: UInt8 = 1, output: String? = "Wine Monitor") throws -> (URL, URL, Data) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HarborDisplay-" + UUID().uuidString)
        let directory = root.appendingPathComponent("My Games/NieR_Automata")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        var bytes = Data(repeating: 0, count: 72)
        bytes.replaceSubrange(0..<8, with: [11,22,33,44,55,66,77,88])
        bytes.replaceSubrange(8..<20, with: [128,7,0,0,56,4,0,0,2,0,0,0])
        bytes[24] = index; bytes[32] = 3; bytes[36] = 2
        try bytes.write(to: directory.appendingPathComponent("SystemData.dat"))
        try Data("save-do-not-touch".utf8).write(to: directory.appendingPathComponent("SlotData_0.dat"))
        if let output { try graphic(output).write(to: directory.appendingPathComponent("Graphic.ini")) }
        return (directory, root.appendingPathComponent("Backups"), bytes)
    }
    private func graphic(_ name: String) -> Data {
        var bytes = name.data(using: .utf16LittleEndian)!
        bytes.append(Data(repeating: 0, count: 128 - bytes.count)); bytes.append(155)
        return Data(("[Graphic]\r\nOutput=" + bytes.map { String(format: "%02X", $0) }.joined() + "\r\n").utf8)
    }
    private func output(_ index: Int = 0, _ name: String = "PHL 27E1N5900") -> NierDisplaySnapshot {
        NierDisplaySnapshot(documentsPath: "C:\\users\\test\\Documents", outputIndex: index, outputName: name)
    }
    func testStaleOutputBackedUpAndOnlyMonitorByteChanges() throws {
        let (dir, backups, original) = try fixture()
        let beforeGraphic = try Data(contentsOf: dir.appendingPathComponent("Graphic.ini"))
        let result = try NierDisplayConfiguration.repair(directory: dir, target: output(), backupRoot: backups, isGameRunning: { false })
        let backup = try XCTUnwrap(result.backup)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("SystemData.dat")), original)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("Graphic.ini")), beforeGraphic)
        var expected = original; expected[24] = 0
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("SystemData.dat")), expected)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Graphic.ini").path))
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("SlotData_0.dat")), "save-do-not-touch")
        XCTAssertNil(try NierDisplayConfiguration.repair(directory: dir, target: output(), backupRoot: backups, isGameRunning: { false }).backup)
    }
    func testHealthyOutputIsNoOp() throws {
        let (dir, backups, bytes) = try fixture(index: 0, output: "PHL 27E1N5900")
        XCTAssertNil(try NierDisplayConfiguration.repair(directory: dir, target: output(), backupRoot: backups, isGameRunning: { false }).backup)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("SystemData.dat")), bytes)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Graphic.ini").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))
    }
    func testUnplugReplugAndReorderedPrimaryUseReportedIndex() throws {
        let (dir, backups, _) = try fixture(index: 0, output: "PHL 27E1N5900")
        XCTAssertNotNil(try NierDisplayConfiguration.repair(directory: dir, target: output(0, "Wine Monitor"), backupRoot: backups, isGameRunning: { false }).backup)
        try graphic("Wine Monitor").write(to: dir.appendingPathComponent("Graphic.ini"))
        XCTAssertNotNil(try NierDisplayConfiguration.repair(directory: dir, target: output(1), backupRoot: backups, isGameRunning: { false }).backup)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("SystemData.dat"))[24], 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Graphic.ini").path))
    }
    func testRunningOrMalformedConfigurationRemainsUntouched() throws {
        let (dir, backups, original) = try fixture()
        XCTAssertThrowsError(try NierDisplayConfiguration.repair(directory: dir, target: output(), backupRoot: backups, isGameRunning: { true }))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("SystemData.dat")), original)
        try Data([1,2,3]).write(to: dir.appendingPathComponent("SystemData.dat"))
        XCTAssertThrowsError(try NierDisplayConfiguration.repair(directory: dir, target: output(), backupRoot: backups, isGameRunning: { false }))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("SystemData.dat")), Data([1,2,3]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))
    }
    func testBadOutputOrUnavailableBackupNeverPartiallyChangesSettings() throws {
        let (dir, backups, original) = try fixture()
        try Data("[Graphic]\nOutput=nothex".utf8).write(to: dir.appendingPathComponent("Graphic.ini"))
        XCTAssertThrowsError(try NierDisplayConfiguration.repair(directory: dir, target: output(), backupRoot: backups, isGameRunning: { false }))
        try graphic("Wine Monitor").write(to: dir.appendingPathComponent("Graphic.ini"))
        try Data([1]).write(to: backups)
        XCTAssertThrowsError(try NierDisplayConfiguration.repair(directory: dir, target: output(), backupRoot: backups, isGameRunning: { false }))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("SystemData.dat")), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Graphic.ini").path))
    }
    func testInvalidPrimaryAndFreshInstallDoNotCreateGameFiles() throws {
        let (dir, backups, original) = try fixture()
        for target in [output(-1), output(32), output(0, " "), output(0, "")] {
            XCTAssertThrowsError(try NierDisplayConfiguration.repair(directory: dir, target: target, backupRoot: backups, isGameRunning: { false }))
        }
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("SystemData.dat")), original)
        let fresh = dir.appendingPathComponent("missing")
        XCTAssertNil(try NierDisplayConfiguration.repair(directory: fresh, target: output(), backupRoot: backups, isGameRunning: { false }).backup)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fresh.path))
    }
    func testGameStartingDuringBackupPreventsMutation() throws {
        let (dir, backups, original) = try fixture()
        var checks = 0
        XCTAssertThrowsError(try NierDisplayConfiguration.repair(directory: dir, target: output(), backupRoot: backups, isGameRunning: {
            checks += 1
            return checks > 1
        }))
        XCTAssertEqual(checks, 2)
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("SystemData.dat")), original)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("Graphic.ini").path))
    }
    func testProcessEnumerationFailureAndBareExecutableProtectConfiguration() throws {
        XCTAssertTrue(NierGameProcess.containsGame(["NieRAutomata.exe"]))
        XCTAssertTrue(NierGameProcess.containsGame(["P:\\Steam Library\\NieRAutomata.EXE"]))
        XCTAssertFalse(NierGameProcess.containsGame(["Steam.exe", "NieRAutomata.exe.backup"]))
        let (dir, backups, original) = try fixture()
        XCTAssertThrowsError(try NierDisplayConfiguration.repair(directory: dir, target: output(), backupRoot: backups, isGameRunning: {
            throw HarborError.unavailable("process enumeration failed")
        }))
        XCTAssertEqual(try Data(contentsOf: dir.appendingPathComponent("SystemData.dat")), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.path))
    }
    func testDriveRelativeAndControlCharacterDocumentsAreRejected() throws {
        for path in ["C:users\\test\\Documents", "Documents", "C:\\users\nwrong", "C:\\users\\..\\wrong"] {
            XCTAssertThrowsError(try NierDisplaySnapshot(documentsPath: path, outputIndex: 0, outputName: "PHL").validate())
        }
    }
    func testRealWineDisplayProbeReadsWithoutChangingGameFiles() throws {
        guard let wrapper = ProcessInfo.processInfo.environment["HARBOR_DISPLAY_SMOKE_WRAPPER"] else {
            throw XCTSkip("Set HARBOR_DISPLAY_SMOKE_WRAPPER for the read-only Wine probe.")
        }
        let container = ContainerRecord(name: "Display probe", wrapperPath: wrapper)
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Harbor/Resources/nier-display-probe.cs")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("Harbor 显示 & 50% " + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let request = try NierDisplayProbeRequest.prepare(container: container, root: root, source: source)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: container.launcher)
        process.arguments = ["WSS-installer", request.launcher.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(90)
        while !FileManager.default.fileExists(atPath: request.completion.path) && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        let primary = try XCTUnwrap(NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == CGMainDisplayID() })
        let snapshot = try request.result()
        if CGDisplayIsBuiltin(CGMainDisplayID()) == 0 { XCTAssertEqual(snapshot.outputName, primary.localizedName) }
        XCTAssertFalse(snapshot.outputName.hasPrefix("Generic "))
        XCTAssertGreaterThanOrEqual(snapshot.outputIndex, 0)
        XCTAssertFalse(snapshot.outputName.isEmpty)
        XCTAssertNotNil(SteamScanner.resolve(windowsPath: snapshot.documentsPath, prefix: container.prefix))
        // Exercise the production repair against disposable fixtures using the real detected output.
        let (dir, backups, original) = try fixture(index: 9)
        XCTAssertNotNil(try NierDisplayConfiguration.repair(directory: dir, target: snapshot, backupRoot: backups, isGameRunning: { false }).backup)
        let repaired = try Data(contentsOf: dir.appendingPathComponent("SystemData.dat"))
        XCTAssertEqual(Array(repaired.prefix(24)), Array(original.prefix(24)))
        XCTAssertEqual(Array(repaired.suffix(44)), Array(original.suffix(44)))
        XCTAssertEqual(repaired[24], UInt8(snapshot.outputIndex))
        try graphic(snapshot.outputName).write(to: dir.appendingPathComponent("Graphic.ini"))
        XCTAssertNil(try NierDisplayConfiguration.repair(directory: dir, target: snapshot, backupRoot: backups, isGameRunning: { false }).backup)
        print("Verified runtime primary output: \(snapshot.outputIndex), \(snapshot.outputName); Documents resolves successfully.")
    }

}
