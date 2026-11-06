import Foundation

public enum CatalogKind: String, Codable, CaseIterable, Sendable {
    case game, application
    public var title: String { self == .game ? "游戏" : "应用" }
}
public extension WindowsApplication {
    var catalogKey: String { "local:" + id.uuidString }
}
public extension AppState {
    func kind(for key: String, default fallback: CatalogKind) -> CatalogKind {
        contentKinds?[key] ?? fallback
    }
    mutating func classify(_ key: String, as kind: CatalogKind, default fallback: CatalogKind) {
        var overrides = contentKinds ?? [:]
        overrides[key] = kind == fallback ? nil : kind
        contentKinds = overrides.isEmpty ? nil : overrides
    }
}
