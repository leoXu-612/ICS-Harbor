import XCTest
@testable import HarborCore

final class CoreTests: XCTestCase {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("HarborTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testNestedVDFAndEscapedPaths() throws {
        let parsed = try VDFParser.parse(#""libraryfolders" { "0" { "path" "P:\\SteamLibrary" "apps" { "524220" "43897584850" } } }"#)
        XCTAssertEqual(parsed["libraryfolders"]?["0"]?["path"]?.string, "P:\\SteamLibrary")
        XCTAssertEqual(parsed["libraryfolders"]?["0"]?["apps"]?["524220"]?.string, "43897584850")
    }
    func testMalformedVDFIsRejected() {
        XCTAssertThrowsError(try VDFParser.parse("\"root\" { \"k\" \"value\""))
        XCTAssertThrowsError(try VDFParser.parse("\"root\" { \"k\" \"unterminated"))
    }
    func testCommandInjectionRejected() {
        for id in ["1 & calc", "12\nexit", "%PATH%", "１２３", "", "1234567890123"] {
            XCTAssertThrowsError(try LaunchPolicy.batch(appID: id))
        }
        XCTAssertTrue((try? LaunchPolicy.batch(appID: "312520"))?.contains("-applaunch 312520") == true)
    }
    func testRendererOptionsAreMutuallyExclusiveAndPreserveOtherKeys() {
        let original: [String:Any] = ["DXVK":1, "D3DMETAL":1, "untouched":"keep"]
        let updated = LaunchPolicy.applying(.init(renderer: .dxmt), to: original)
        XCTAssertEqual(updated["DXVK"] as? Int, 0)
        XCTAssertEqual(updated["D3DMETAL"] as? Int, 0)
        XCTAssertEqual(updated["untouched"] as? String, "keep")
    }
    func testMissingDriveRepairDoesNotOverwriteAnotherDrive() throws {
        let base = try scratch()
        let wrapper = base.appendingPathComponent("Test.app")
        let container = ContainerRecord(name: "Fixture", wrapperPath: wrapper.path, origin: .managed)
        try FileManager.default.createDirectory(atPath: container.prefix + "/dosdevices", withIntermediateDirectories: true)
        let volume = base.appendingPathComponent("Elements"); try FileManager.default.createDirectory(at: volume, withIntermediateDirectories: true)
        try DriveMapper.createMissingLink(container: container, letter: "P", target: volume)
        XCTAssertEqual(SteamScanner.resolve(windowsPath: "P:\\SteamLibrary", prefix: container.prefix), volume.path + "/SteamLibrary")
        try DriveMapper.createMissingLink(container: container, letter: "P", target: volume)
        XCTAssertThrowsError(try DriveMapper.createMissingLink(container: container, letter: "P", target: base))
        XCTAssertThrowsError(try DriveMapper.createMissingLink(container: container, letter: "C", target: volume))
        XCTAssertNil(SteamScanner.resolve(windowsPath: "P:\\..\\Secret", prefix: container.prefix))
    }
    func testLinkedContainerCannotBeModifiedWithoutScopedConsent() throws {
        let base = try scratch()
        let container = ContainerRecord(name: "Linked", wrapperPath: base.path)
        XCTAssertThrowsError(try DriveMapper.createMissingLink(container: container, letter: "P", target: base))
        XCTAssertThrowsError(try LaunchPolicy.apply(.init(renderer: .dxvk), container: container, backupRoot: base, busy: false))
    }
    func testStateRoundTripAndBackup() throws {
        let store = StateStore(root: try scratch())
        var state = AppState(); state.containers = [ContainerRecord(name: "测试", wrapperPath: "/tmp/Container.app")]
        try store.save(state); state.presets["game"] = .init(renderer: .dxmt); try store.save(state)
        XCTAssertEqual(try store.load().presets["game"]?.renderer, .dxmt)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.backupURL.path))
        try Data("broken".utf8).write(to: store.stateURL)
        XCTAssertThrowsError(try store.load())
    }
    func testSensitiveLogLinesAreRemoved() {
        let redacted = LogRedactor.redact("URL https://x.test/?secret=x\nCookie: private\naccess_token=abc\n/Users/test/game\n[U:1:123456789] account 76561198012345678", home: "/Users/test")
        XCTAssertFalse(redacted.contains("private")); XCTAssertFalse(redacted.contains("abc"))
        XCTAssertFalse(redacted.contains("https://")); XCTAssertTrue(redacted.contains("~/game"))
        XCTAssertFalse(redacted.contains("123456789")); XCTAssertFalse(redacted.contains("76561198012345678"))
    }
    func testVolumeResolutionUsesUUIDNotJustName() {
        let binding = DriveBinding(containerID: UUID(), letter: "P", volumeUUID: "real", volumeName: "Elements")
        XCTAssertNil(DriveMapper.target(for: binding, volumes: [.init(name: "Elements", path: "/Volumes/Elements", uuid: "wrong")]))
        XCTAssertEqual(DriveMapper.target(for: binding, volumes: [.init(name: "Elements 1", path: "/Volumes/Elements 1", uuid: "real")])?.path, "/Volumes/Elements 1")
    }
    func testOfflineLibraryRemainsVisibleWithoutInventingInstallStatus() throws {
        let base = try scratch()
        let container = ContainerRecord(name: "Fixture", wrapperPath: base.appendingPathComponent("Test.app").path)
        try FileManager.default.createDirectory(atPath: container.steamRoot + "/steamapps", withIntermediateDirectories: true)
        let vdf = #""libraryfolders" { "0" { "path" "P:\\SteamLibrary" "apps" { "312520" "4328135541" } } }"#
        try vdf.write(toFile: container.steamRoot + "/steamapps/libraryfolders.vdf", atomically: true, encoding: .utf8)
        let snapshot = SteamScanner.scan(container)
        XCTAssertEqual(snapshot.games.count, 1); XCTAssertEqual(snapshot.games.first?.availability, .offline)
        XCTAssertEqual(snapshot.games.first?.name, "Rain World")
        XCTAssertFalse(snapshot.libraries[0].isOnline)
        XCTAssertThrowsError(try LaunchPolicy.validate(game: snapshot.games[0], container: container, preset: .init(), busy: false))
    }
    func testSharedNativeAndWineLibraryIsDetected() {
        let id = UUID()
        let lib = LibraryRecord(id: "shared", containerID: id, windowsPath: "P:\\SteamLibrary", unixPath: "/Volumes/Elements/SteamLibrary", drive: "P", mappedTarget: "/Volumes/Elements", isOnline: true, registeredCount: 1)
        let text = #""libraryfolders" { "0" { "path" "/Volumes/Elements/SteamLibrary" } }"#
        XCTAssertEqual(SteamScanner.nativeLibraryConflicts([lib], nativeVDF: text), ["shared"])
        XCTAssertTrue(SteamScanner.nativeLibraryConflicts([lib], nativeVDF: #""libraryfolders" { "0" { "path" "/Volumes/Other/SteamLibrary" } }"#).isEmpty)
    }
    func testBusyOwnedContainerRejectsRuntimeChange() {
        let container = ContainerRecord(name: "owned", wrapperPath: "/tmp/owned.app", origin: .managed)
        let game = GameRecord(containerID: container.id, appID: "312520", name: "Rain World", libraryID: "lib", libraryWindowsPath: "P:\\SteamLibrary", installDirectory: "/Volumes/Elements/SteamLibrary/steamapps/common/Rain World", sizeOnDisk: 1, buildID: nil, availability: .ready, coverPath: nil, heroPath: nil)
        XCTAssertThrowsError(try LaunchPolicy.validate(game: game, container: container, preset: .init(renderer: .dxmt), busy: true))
        XCTAssertNoThrow(try LaunchPolicy.validate(game: game, container: container, preset: .init(), busy: true))
    }
    func testManagedPresetBacksUpAndPreservesOtherSettings() throws {
        let root = try scratch()
        let container = ContainerRecord(name: "managed", wrapperPath: root.appendingPathComponent("Runtime.app").path, origin: .managed)
        let contents = URL(fileURLWithPath: container.wrapperPath + "/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try container.id.uuidString.write(to: contents.appendingPathComponent("HarborManagedRuntime"), atomically: true, encoding: .utf8)
        let original: [String: Any] = ["D3DMETAL":0, "DXVK":0, "Program Name and Path":"/Steam.exe", "custom-user-key":"preserve"]
        let data = try PropertyListSerialization.data(fromPropertyList: original, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        try data.write(to: contents.appendingPathComponent("HarborBaseline.plist"))
        let backups = root.appendingPathComponent("backups")
        try LaunchPolicy.apply(.init(renderer: .dxvk, sync: .disabled), container: container, backupRoot: backups, busy: false)
        let result = try PropertyListSerialization.propertyList(from: Data(contentsOf: contents.appendingPathComponent("Info.plist")), format: nil) as! [String:Any]
        XCTAssertEqual(result["DXVK"] as? Int, 1); XCTAssertEqual(result["custom-user-key"] as? String, "preserve")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path).count, 1)
        // Switching back to inheritance must undo the previous game's graphics overrides.
        XCTAssertThrowsError(try LaunchPolicy.apply(.init(), container: container, backupRoot: backups, busy: true))
        try LaunchPolicy.apply(.init(), container: container, backupRoot: backups, busy: false)
        let restored = try PropertyListSerialization.propertyList(from: Data(contentsOf: contents.appendingPathComponent("Info.plist")), format: nil) as! [String:Any]
        XCTAssertEqual(restored["DXVK"] as? Int, 0)
        XCTAssertNil(restored["WINEESYNC"])
        // Inherit restores the original absence instead of forcing HUD off.
        XCTAssertNil(restored["METAL_HUD"])
        XCTAssertEqual(restored["custom-user-key"] as? String, "preserve")
        XCTAssertNoThrow(try LaunchPolicy.apply(.init(), container: container, backupRoot: backups, busy: true))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: backups.path).count, 2)
    }
}
