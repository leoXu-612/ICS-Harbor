import XCTest
@testable import HarborCore

final class CatalogKindTests: XCTestCase {
    func testLegacyIndexAcceptsCrossSourceClassificationsWithoutChangingLaunchData() throws {
        let oldIndex = #"{"schema":1,"containers":[],"presets":{},"previousPresets":{},"favorites":[],"bindings":[],"activity":[]}"#
        var state = try JSONDecoder().decode(AppState.self, from: Data(oldIndex.utf8))
        let app = WindowsApplication(containerID: UUID(), name: "Editor", executablePath: "/fixture/Editor.exe", workingDirectory: "/fixture")
        state.applications = [app]
        let steamKey = app.containerID.uuidString + ":123"
        XCTAssertEqual(state.kind(for: steamKey, default: .game), .game)
        state.classify(steamKey, as: .application, default: .game)
        state.classify(app.catalogKey, as: .game, default: .application)
        let saved = try JSONDecoder().decode(AppState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(saved.applications, [app])
        XCTAssertEqual(saved.kind(for: steamKey, default: .game), .application)
        XCTAssertEqual(saved.kind(for: app.catalogKey, default: .application), .game)
        state.classify(steamKey, as: .game, default: .game)
        state.classify(app.catalogKey, as: .application, default: .application)
        XCTAssertNil(state.contentKinds)
    }
}
