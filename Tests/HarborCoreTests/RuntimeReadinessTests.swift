import XCTest
@testable import HarborCore

final class RuntimeReadinessTests: XCTestCase {
    private func fixture(purpose: ContainerPurpose? = .steam) throws -> ContainerRecord {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HarborReady-" + UUID().uuidString)
        var container = ContainerRecord(name: "Fixture", wrapperPath: root.appendingPathComponent("Runtime.app").path, origin: .managed)
        container.purpose = purpose
        for folder in ["/Contents/MacOS", "/Contents/SharedSupport/wine/bin", "/Contents/SharedSupport/prefix/drive_c/windows/system32"] {
            try FileManager.default.createDirectory(atPath: container.wrapperPath + folder, withIntermediateDirectories: true)
        }
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        try Data().write(to: URL(fileURLWithPath: container.prefix + "/system.reg"))
        return container
    }
    private func complete(_ container: ContainerRecord) throws {
        for item in ["/Contents/MacOS/launcher", "/Contents/SharedSupport/wine/bin/wine"] {
            let path = container.wrapperPath + item
            try Data("fixture, never executed".utf8).write(to: URL(fileURLWithPath: path))
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        }
        try container.id.uuidString.write(toFile: container.wrapperPath + "/Contents/HarborManagedRuntime", atomically: true, encoding: .utf8)
        try "profile-ready-v1\n".write(toFile: container.prefix + "/.harbor-profile-ready", atomically: true, encoding: .utf8)
        try "HARBOR_WIN32_OK\r\n".write(toFile: container.prefix + "/drive_c/harbor-ready.txt", atomically: true, encoding: .utf8)
        try Data([0x4d, 0x5a]).write(to: URL(fileURLWithPath: container.prefix + "/drive_c/windows/system32/cmd.exe"))
    }
    func testRegistryAloneDoesNotOfferInstallation() throws {
        let c = try fixture()
        XCTAssertTrue(RuntimeInfo.read(c).initialized)
        XCTAssertFalse(RuntimeInfo.read(c).applicationReady)
    }
    func testMissingCommandProcessorKeepsEnvironmentUnready() throws {
        let c = try fixture(); try complete(c)
        try FileManager.default.removeItem(atPath: c.prefix + "/drive_c/windows/system32/cmd.exe")
        XCTAssertFalse(RuntimeInfo.read(c).applicationReady)
    }
    func testCompletedLegacyManagedEnvironmentDoesNotNeedNewFontMarker() throws {
        let c = try fixture(purpose: nil); try complete(c)
        XCTAssertTrue(RuntimeInfo.read(c).applicationReady)
    }
    func testGeneralEnvironmentWaitsForItsFontPreparation() throws {
        let c = try fixture(purpose: .applications); try complete(c)
        XCTAssertFalse(RuntimeInfo.read(c).applicationReady)
        try "harbor-cjk-v1\r\n".write(toFile: c.prefix + "/drive_c/harbor-cjk-ready.txt", atomically: true, encoding: .utf8)
        XCTAssertTrue(RuntimeInfo.read(c).applicationReady)
    }
    func testReadinessRequiresCorrectOwnerAndExecutableLauncher() throws {
        let c = try fixture(); try complete(c)
        var other = c; other.id = UUID()
        XCTAssertFalse(RuntimeInfo.read(other).applicationReady)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: c.launcher)
        XCTAssertFalse(RuntimeInfo.read(c).applicationReady)
    }
    func testFailedProbeOrMissingCompletionMarkerCannotOfferInstall() throws {
        let c = try fixture(); try complete(c)
        try "failed".write(toFile: c.prefix + "/drive_c/harbor-ready.txt", atomically: true, encoding: .utf8)
        XCTAssertFalse(RuntimeInfo.read(c).applicationReady)
        try "HARBOR_WIN32_OK".write(toFile: c.prefix + "/drive_c/harbor-ready.txt", atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(atPath: c.prefix + "/.harbor-profile-ready")
        XCTAssertFalse(RuntimeInfo.read(c).applicationReady)
    }
}
