import XCTest
@testable import HarborCore

final class DriveReconnectTests: XCTestCase {
    func testReconnectRestoresMissingLetterAndExistingLibraryWithoutChangingSteamRegistration() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let container = ContainerRecord(name: "Linked", wrapperPath: root.appendingPathComponent("Wine.app").path)
        try fm.createDirectory(atPath: container.prefix + "/dosdevices", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: container.steamRoot + "/steamapps", withIntermediateDirectories: true)
        let vdf = #""libraryfolders" { "1" { "path" "P:\\SteamLibrary" "apps" { "312520" "123" } } }"#
        let config = container.steamRoot + "/steamapps/libraryfolders.vdf"
        try vdf.write(toFile: config, atomically: true, encoding: .utf8)
        let volume = root.appendingPathComponent("Elements")
        let apps = volume.appendingPathComponent("SteamLibrary/steamapps")
        try fm.createDirectory(at: apps.appendingPathComponent("common/Rain World"), withIntermediateDirectories: true)
        try #""AppState" { "appid" "312520" "name" "Rain World" "installdir" "Rain World" "StateFlags" "4" }"#.write(to: apps.appendingPathComponent("appmanifest_312520.acf"), atomically: true, encoding: .utf8)
        let binding = DriveBinding(containerID: container.id, letter: "P", volumeUUID: "volume-id", volumeName: "Elements")
        let link = container.prefix + "/dosdevices/p:"
        try fm.createSymbolicLink(atPath: link, withDestinationPath: volume.path)
        XCTAssertEqual(SteamScanner.scan(container).games.first?.availability, .ready)
        // Reproduce the observed disappearance of the Wine drive link on disconnect.
        try fm.removeItem(atPath: link)
        XCTAssertTrue(DriveMapper.restoreBindings([binding], containers: [container], volumes: []).isEmpty)
        XCTAssertEqual(SteamScanner.scan(container).games.first?.availability, .offline)
        let remounted = root.appendingPathComponent("Elements 1")
        try fm.moveItem(at: volume, to: remounted)
        let mounted = MountedVolume(name: "Elements", path: remounted.path, uuid: "volume-id")
        XCTAssertTrue(DriveMapper.restoreBindings([binding], containers: [container], volumes: [mounted]).isEmpty)
        XCTAssertEqual(SteamScanner.scan(container).games.first?.availability, .ready)
        XCTAssertEqual(try String(contentsOfFile: config), vdf)
        XCTAssertTrue(DriveMapper.restoreBindings([binding], containers: [container], volumes: [mounted]).isEmpty)
    }

    func testReconnectNeverAdoptsSameNameDiskOrOverwritesExistingMapping() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let container = ContainerRecord(name: "Linked", wrapperPath: root.appendingPathComponent("Wine.app").path)
        try fm.createDirectory(atPath: container.prefix + "/dosdevices", withIntermediateDirectories: true)
        let binding = DriveBinding(containerID: container.id, letter: "P", volumeUUID: "right", volumeName: "Elements")
        let link = container.prefix + "/dosdevices/p:"
        _ = DriveMapper.restoreBindings([binding], containers: [container], volumes: [.init(name: "Elements", path: root.path, uuid: "wrong")])
        XCTAssertFalse(fm.fileExists(atPath: link))
        try fm.createSymbolicLink(atPath: link, withDestinationPath: "/missing-other-drive")
        XCTAssertEqual(DriveMapper.restoreBindings([binding], containers: [container], volumes: [.init(name: "Elements", path: root.path, uuid: "right")]).count, 1)
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: link), "/missing-other-drive")
    }
}
