import XCTest
@testable import HarborCore

final class ApplicationTests: XCTestCase {
    private func fixture() throws -> (ContainerRecord, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HarborAppTests-" + UUID().uuidString)
        let container = ContainerRecord(name: "Test", wrapperPath: root.appendingPathComponent("Runtime.app").path, origin: .managed)
        let c = URL(fileURLWithPath: container.prefix + "/drive_c")
        let dos = URL(fileURLWithPath: container.prefix + "/dosdevices")
        try FileManager.default.createDirectory(at: c.appendingPathComponent("Program Files/Example"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dos, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: dos.appendingPathComponent("c:"), withDestinationURL: c)
        try FileManager.default.createSymbolicLink(atPath: dos.appendingPathComponent("z:").path, withDestinationPath: "/")
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return (container, root)
    }
    func testLegacyStateAndContainerRemainCompatible() throws {
        var state = AppState(); state.containers = [ContainerRecord(name: "Steam", wrapperPath: "/old.app")]
        let encoded = try JSONEncoder().encode(state)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("applications"))
        let decoded = try JSONDecoder().decode(AppState.self, from: encoded)
        XCTAssertNil(decoded.applications); XCTAssertTrue(decoded.containers[0].preparesSteam)
        var appContainer = decoded.containers[0]; appContainer.purpose = .applications
        XCTAssertFalse(appContainer.preparesSteam)
    }
    func testApplicationStateRoundTripKeepsGamePresets() throws {
        var state = AppState(); state.presets["existing-game"] = GamePreset(renderer: .dxvk)
        let record = WindowsApplication(containerID: UUID(), name: "Example", executablePath: "/app.exe", workingDirectory: "/", arguments: ["a b", "中文"])
        state.applications = [record]
        let decoded = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.applications, [record]); XCTAssertEqual(decoded.presets, state.presets)
    }
    func testMappedPathPrefersContainerCOverHostZ() throws {
        let (container, _) = try fixture()
        XCTAssertEqual(try WindowsCommand.windowsPath(URL(fileURLWithPath: container.prefix + "/drive_c/Program Files/Example/tool.exe"), container: container), "C:\\Program Files\\Example\\tool.exe")
        XCTAssertEqual(try WindowsCommand.windowsPath(URL(fileURLWithPath: "/usr/bin/true"), container: container), "Z:\\usr\\bin\\true")
    }
    func testPrefixBoundaryAndMissingMapping() throws {
        let (container, _) = try fixture()
        let outside = container.prefix + "/drive_c-not-real/file.exe"
        XCTAssertTrue(try WindowsCommand.windowsPath(URL(fileURLWithPath: outside), container: container).hasPrefix("Z:"))
        try FileManager.default.removeItem(atPath: container.prefix + "/dosdevices/z:")
        XCTAssertThrowsError(try WindowsCommand.windowsPath(URL(fileURLWithPath: "/tmp/file.exe"), container: container))
    }
    func testBusyProbeNormalizesEnginePathSegments() throws {
        let (container, _) = try fixture()
        let engine = URL(fileURLWithPath: container.wrapperPath + "/Contents/SharedSupport/wine/bin")
        try FileManager.default.createDirectory(at: engine, withIntermediateDirectories: true)
        try Data().write(to: engine.appendingPathComponent("wineserver"))
        let command = container.wrapperPath + "/../Runtime.app/Contents/SharedSupport/wine/bin/wineserver"
        XCTAssertTrue(ProcessProbe.isBusy(container, entries: [ProcessEntry(pid: 1, command: command)]))
        XCTAssertFalse(ProcessProbe.isBusy(container, entries: [ProcessEntry(pid: 1, command: "/another/Contents/SharedSupport/wine/bin/wineserver")]))
    }
    func testFileTypeValidationDoesNotExecuteFixtures() throws {
        let (_, root) = try fixture()
        let exe = root.appendingPathComponent("example.EXE"), msi = root.appendingPathComponent("example.msi")
        try Data([0x4d, 0x5a, 0, 0]).write(to: exe)
        try Data([0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1]).write(to: msi)
        XCTAssertNoThrow(try WindowsCommand.validateFile(exe, installer: false))
        XCTAssertNoThrow(try WindowsCommand.validateFile(msi, installer: true))
        XCTAssertThrowsError(try WindowsCommand.validateFile(msi, installer: false))
        try Data("not an exe".utf8).write(to: exe)
        XCTAssertThrowsError(try WindowsCommand.validateFile(exe, installer: true))
    }
    func testApplicationValidationChecksWorkingDirectoryAndOwner() throws {
        let (container, root) = try fixture()
        let exe = root.appendingPathComponent("example.exe"); try Data([0x4d, 0x5a]).write(to: exe)
        var app = WindowsApplication(containerID: container.id, name: "Example", executablePath: exe.path, workingDirectory: root.path)
        XCTAssertNoThrow(try WindowsCommand.validate(app, container: container))
        app.workingDirectory = root.appendingPathComponent("missing").path
        XCTAssertThrowsError(try WindowsCommand.validate(app, container: container))
        app.workingDirectory = root.path; app.containerID = UUID()
        XCTAssertThrowsError(try WindowsCommand.validate(app, container: container))
    }
    func testArgumentsAreQuotedDataNotShellFragments() throws {
        let command = try WindowsCommand.batch(executable: "C:\\Program Files\\Tool\\app.exe", workingDirectory: "C:\\Program Files\\Tool", arguments: ["space value", "%PATH%", "a&b", "!literal!", "C:\\tail\\"], installer: false, resultPath: "Z:\\tmp\\result.exit")
        XCTAssertTrue(command.contains("setlocal DisableDelayedExpansion"))
        XCTAssertTrue(command.contains("\"%%PATH%%\" \"a&b\" \"!literal!\" \"C:\\tail\\\\\""))
        XCTAssertTrue(command.contains("start \"\" /wait \"C:\\Program Files\\Tool\\app.exe\""))
        XCTAssertFalse(command.contains("Steam.exe"))
        for invalid in ["a\" & calc", "x\ncalc", "\0", "\r", "\t"] { XCTAssertThrowsError(try WindowsCommand.quote(invalid)) }
    }
    func testMSIUsesWineInstallerWithoutSilentLicenseAcceptance() throws {
        let command = try WindowsCommand.batch(executable: "Z:\\tmp\\Setup.MSI", workingDirectory: "Z:\\tmp", arguments: [], installer: true, resultPath: "Z:\\tmp\\result.exit")
        XCTAssertTrue(command.contains("msiexec.exe\" /i \"Z:\\tmp\\Setup.MSI\" /norestart"))
        XCTAssertFalse(command.contains("/qn")); XCTAssertFalse(command.contains("Steam"))
        XCTAssertTrue(command.contains("%errorlevel%"))
    }
    func testStandaloneProgressDoesNotRequireOrClaimSteam() {
        var progress = LaunchProgress(containerID: UUID(), appID: nil, title: "Example")
        progress.standalone = true; progress.checkedFiles(at: Date())
        var evidence = LaunchEvidence(); evidence.runtimeRunning = true; evidence.gamePID = 8; evidence.steamPID = 9; evidence.connection = .online
        progress.observe(evidence, at: Date())
        XCTAssertEqual(progress.completedCount, 3); XCTAssertFalse(progress.completed.contains(.steam)); XCTAssertEqual(progress.connection, .unknown)
        XCTAssertEqual(progress.outcome, .pending)
        evidence.visibleWindowPIDs = [8]; progress.observe(evidence, at: Date())
        XCTAssertEqual(progress.fraction, 1); XCTAssertEqual(progress.heading, "应用窗口已出现")
    }
    func testInstallerExitDoesNotClaimInstalledOrInventWindow() {
        var progress = LaunchProgress(containerID: UUID(), appID: nil, title: "Setup")
        progress.standalone = true; progress.installer = true
        var evidence = LaunchEvidence(); evidence.exitCode = 0
        progress.observe(evidence, at: Date())
        XCTAssertEqual(progress.outcome, .exited); XCTAssertEqual(progress.heading, "安装器已结束")
        XCTAssertFalse(progress.completed.contains(.window)); XCTAssertTrue(progress.explanation.contains("添加已安装 EXE"))
    }
    func testCancelledFailedAndRestartRequiredInstallers() {
        for (code, outcome): (Int, LaunchOutcome) in [(1602,.exited),(3010,.exited),(1641,.exited),(1603,.failed)] {
            var progress = LaunchProgress(containerID: UUID(), appID: nil, title: "Setup"); progress.standalone = true; progress.installer = true
            var evidence = LaunchEvidence(); evidence.exitCode = code
            progress.observe(evidence, at: Date()); XCTAssertEqual(progress.outcome, outcome); XCTAssertEqual(progress.exitCode, code)
        }
    }
}
