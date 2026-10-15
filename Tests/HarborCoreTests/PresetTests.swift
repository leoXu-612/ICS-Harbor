import XCTest
@testable import HarborCore

final class PresetTests: XCTestCase {
    private func fixture(origin: ContainerOrigin = .linked, dxmt: Bool = false) throws -> (ContainerRecord, URL, Data) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HarborPresetTests-" + UUID().uuidString)
        let container = ContainerRecord(name: "Fixture", wrapperPath: root.appendingPathComponent("Runtime.app").path, origin: origin)
        let contents = URL(fileURLWithPath: container.wrapperPath + "/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let original: [String: Any] = ["D3DMETAL":0,"DXVK":0,"WINEESYNC":1,"WINEMSYNC":1,"METAL_HUD":1,"WINEDEBUG":"original-channels","Program Flags":"original flags","CLI Custom Commands":"original commands","custom-user-key":"keep"]
        let data = try PropertyListSerialization.data(fromPropertyList: original, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        if origin == .managed {
            try data.write(to: contents.appendingPathComponent("HarborBaseline.plist"))
            try container.id.uuidString.write(to: contents.appendingPathComponent("HarborManagedRuntime"), atomically: true, encoding: .utf8)
        }
        if dxmt {
            for arch in ["x86_64-windows", "i386-windows"] {
                let folder = contents.appendingPathComponent("Frameworks/renderer/dxmt/wine/" + arch)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                // Capability fixture only; never executed as a DLL.
                try Data("d3d11.preferredMaxFrameRate\0dxgi.forceSDR\0dxgi.handleAltTab\0".utf8).write(to: folder.appendingPathComponent("d3d11.dll"))
            }
        }
        return (container, root.appendingPathComponent("backups"), data)
    }
    private func current(_ container: ContainerRecord) throws -> [String: Any] {
        try PropertyListSerialization.propertyList(from: Data(contentsOf: URL(fileURLWithPath: container.wrapperPath + "/Contents/Info.plist")), format: nil) as! [String: Any]
    }
    func testLegacyPresetDecodesWithoutMakingProtectedDefaultsAnOverride() throws {
        let old = Data(#"{"renderer":"inherit","sync":"inherit","metalHUD":false}"#.utf8)
        let preset = try JSONDecoder().decode(GamePreset.self, from: old)
        XCTAssertFalse(preset.modifiesRuntime); XCTAssertEqual(preset.hud, .inherit)
        XCTAssertTrue(preset.showProgress); XCTAssertFalse(preset.focusOnWindow)
        XCTAssertEqual(preset.waitThreshold, .seconds45)
        let legacyOn = try JSONDecoder().decode(GamePreset.self, from: Data(#"{"renderer":"dxmt","sync":"enabled","metalHUD":true}"#.utf8))
        XCTAssertEqual(legacyOn.hud, .enabled); XCTAssertEqual(legacyOn.sync, .enabled)
    }
    func testDetailedPresetRoundTripAndFiniteEnvironment() throws {
        var p = GamePreset(renderer: .dxmt, sync: .msync)
        p.frameLimit = .fps60; p.forceSDR = .enabled; p.handleAltTab = .disabled
        p.hud = .disabled; p.logging = .warnings; p.showProgress = false; p.focusOnWindow = true; p.waitThreshold = .seconds180
        XCTAssertEqual(try JSONDecoder().decode(GamePreset.self, from: JSONEncoder().encode(p)), p)
        XCTAssertEqual(p.runtimeEnvironment["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=60;dxgi.forceSDR=True;dxgi.handleAltTab=False")
        XCTAssertEqual(p.runtimeEnvironment["MTL_HUD_ENABLED"], "0")
        XCTAssertFalse(p.runtimeEnvironment.values.contains { $0.contains("\n") || $0.contains("&") || $0.contains("%") })
    }
    func testIndependentSyncPathsAndLegacyPair() {
        for (mode, e, m): (SyncMode, Int, Int) in [(.msync,0,1),(.esync,1,0),(.disabled,0,0),(.enabled,1,1)] {
            let result = LaunchPolicy.applying(.init(sync: mode), to: ["other":"keep"])
            XCTAssertEqual(result["WINEESYNC"] as? Int, e); XCTAssertEqual(result["WINEMSYNC"] as? Int, m)
            XCTAssertEqual(result["other"] as? String, "keep")
        }
    }
    func testHUDAndLoggingInheritanceDoesNotForceNewValues() {
        let base: [String: Any] = ["METAL_HUD":1,"WINEDEBUG":"user-defined"]
        let inherited = LaunchPolicy.applying(.init(), to: base)
        XCTAssertEqual(inherited["METAL_HUD"] as? Int, 1)
        XCTAssertEqual(inherited["WINEDEBUG"] as? String, "user-defined")
        var p = GamePreset(); p.hud = .disabled; p.logging = .errors
        let result = LaunchPolicy.applying(p, to: base)
        XCTAssertEqual(result["METAL_HUD"] as? Int, 0)
        XCTAssertEqual(result["WINEDEBUG"] as? String, "-all,err+all")
    }
    func testStartupOnlyPreferencesDoNotRequireRuntimePermission() {
        var p = GamePreset(); p.showProgress = false; p.focusOnWindow = true; p.waitThreshold = .seconds90
        XCTAssertFalse(p.modifiesRuntime); XCTAssertTrue(p.runtimeEnvironment.isEmpty)
    }
    func testLinkedAuthorizationCopiesOriginalWithoutChangingIt() throws {
        let (container, backups, original) = try fixture()
        XCTAssertFalse(RuntimeControl.isAuthorized(container, root: backups))
        try RuntimeControl.authorizeLinked(container, root: backups, busy: false)
        XCTAssertTrue(RuntimeControl.isAuthorized(container, root: backups)); XCTAssertEqual(container.origin, .linked)
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: container.wrapperPath + "/Contents/Info.plist")), original)
        XCTAssertEqual(try RuntimeControl.baseline(container, root: backups)["custom-user-key"] as? String, "keep")
    }
    func testBusyAuthorizationAndRetargetedPathAreRejected() throws {
        let (container, backups, _) = try fixture()
        XCTAssertThrowsError(try RuntimeControl.authorizeLinked(container, root: backups, busy: true))
        XCTAssertFalse(RuntimeControl.isAuthorized(container, root: backups))
        try RuntimeControl.authorizeLinked(container, root: backups, busy: false)
        var moved = container; moved.wrapperPath += "-other"
        XCTAssertFalse(RuntimeControl.isAuthorized(moved, root: backups))
        XCTAssertThrowsError(try RuntimeControl.baseline(moved, root: backups))
    }
    func testAuthorizedOverridesPreserveUnrelatedKeysAndRestoreBaseline() throws {
        let (container, backups, original) = try fixture()
        try RuntimeControl.authorizeLinked(container, root: backups, busy: false)
        var p = GamePreset(renderer: .dxvk, sync: .esync); p.hud = .disabled; p.logging = .warnings
        try LaunchPolicy.apply(p, container: container, backupRoot: backups, busy: false)
        let changed = try current(container)
        XCTAssertEqual(changed["DXVK"] as? Int, 1); XCTAssertEqual(changed["WINEMSYNC"] as? Int, 0)
        XCTAssertEqual(changed["Program Flags"] as? String, "original flags")
        XCTAssertEqual(changed["CLI Custom Commands"] as? String, "original commands")
        try RuntimeControl.authorizeLinked(container, root: backups, busy: false)
        XCTAssertEqual(try RuntimeControl.baseline(container, root: backups)["DXVK"] as? Int, 0)
        XCTAssertThrowsError(try LaunchPolicy.apply(.init(), container: container, backupRoot: backups, busy: true))
        try LaunchPolicy.apply(.init(), container: container, backupRoot: backups, busy: false)
        let baseline = try PropertyListSerialization.propertyList(from: original, format: nil) as! [String: Any]
        XCTAssertEqual(NSDictionary(dictionary: try current(container)), NSDictionary(dictionary: baseline))
    }
    func testSessionOnlyOverridesCannotLeakIntoWarmDefaultGame() throws {
        let (container, backups, _) = try fixture(dxmt: true)
        try RuntimeControl.authorizeLinked(container, root: backups, busy: false)
        var p = GamePreset(); p.frameLimit = .fps60
        try LaunchPolicy.apply(p, container: container, backupRoot: backups, busy: false)
        XCTAssertEqual((try current(container)["HarborSessionEnvironment"] as? [String: String])?["DXMT_CONFIG"], "d3d11.preferredMaxFrameRate=60")
        XCTAssertThrowsError(try LaunchPolicy.apply(.init(), container: container, backupRoot: backups, busy: true))
        try LaunchPolicy.apply(.init(), container: container, backupRoot: backups, busy: false)
        XCTAssertNil(try current(container)["HarborSessionEnvironment"])
    }
    func testMissingDXMTCapabilityFailsBeforeWriting() throws {
        let (container, backups, original) = try fixture()
        try RuntimeControl.authorizeLinked(container, root: backups, busy: false)
        var p = GamePreset(); p.frameLimit = .fps60
        XCTAssertThrowsError(try LaunchPolicy.apply(p, container: container, backupRoot: backups, busy: false))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: container.wrapperPath + "/Contents/Info.plist")), original)
    }
    func testDXMTOptionsAreRejectedForDXVK() throws {
        let (container, backups, original) = try fixture(dxmt: true)
        try RuntimeControl.authorizeLinked(container, root: backups, busy: false)
        var p = GamePreset(renderer: .dxvk); p.forceSDR = .enabled
        XCTAssertThrowsError(try LaunchPolicy.apply(p, container: container, backupRoot: backups, busy: false))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: container.wrapperPath + "/Contents/Info.plist")), original)
    }
    func testConfigurableWaitThresholdDoesNotChangeCheckpoints() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        var p = LaunchProgress(containerID: UUID(), appID: "730", title: "Fixture", now: start)
        p.warningDelay = 90; p.automaticDisplay = false; p.checkedFiles(at: start)
        XCTAssertFalse(p.isTakingLong(at: start.addingTimeInterval(60)))
        XCTAssertTrue(p.isTakingLong(at: start.addingTimeInterval(91)))
        XCTAssertEqual(p.completedCount, 1); XCTAssertEqual(p.automaticDisplay, false)
    }
}
