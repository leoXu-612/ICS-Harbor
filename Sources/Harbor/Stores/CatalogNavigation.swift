import SwiftUI
import HarborCore

enum CatalogSource: String, CaseIterable, Identifiable {
    case steam, local, epic, gog
    var id: Self { self }
    var title: String { switch self {
    case .steam: "Steam"
    case .local: "本地导入"
    case .epic: "Epic Games"
    case .gog: "GOG"
    }}
    var symbol: String { switch self {
    case .steam: "circle.hexagongrid.fill"
    case .local: "tray.and.arrow.down"
    case .epic: "shield.lefthalf.filled"
    case .gog: "square.grid.3x3.square"
    }}
    var isAvailable: Bool { self == .steam || self == .local }
}

enum AppSection: String, CaseIterable, Identifiable {
    case library, steam, local, epic, gog, containers, presets, activity, guide
    var id: Self { self }
    var source: CatalogSource? { CatalogSource(rawValue: rawValue) }
    var title: String {
        if let source { return source.title }
        switch self {
        case .library: return "全部内容"
        case .containers: return "运行环境"
        case .presets: return "参数说明"
        case .activity: return "任务与诊断"
        case .guide: return "使用指南"
        default: return rawValue
        }
    }
    var symbol: String {
        if let source { return source.symbol }
        switch self {
        case .library: return "square.grid.2x2"
        case .containers: return "square.3.layers.3d"
        case .activity: return "waveform.path.ecg"
        case .guide: return "book"
        default: return "slider.horizontal.3"
        }
    }
}

extension AppModel {
    func navigate(_ target: AppSection) {
        sourceSettingsVisible = target.source.map { !$0.isAvailable } ?? false
        section = target
        selectedGameID = nil; selectedApplicationID = nil
    }
    func openSourceSettings(_ source: CatalogSource) {
        guard let target = AppSection(rawValue: source.rawValue) else { return }
        navigate(target)
        sourceSettingsVisible = true
    }

    func contentKind(for game: GameRecord) -> CatalogKind { state.kind(for: game.id, default: .game) }
    func contentKind(for app: WindowsApplication) -> CatalogKind { state.kind(for: app.catalogKey, default: .application) }
    func setContentKind(_ kind: CatalogKind, for game: GameRecord) { classify(kind, key: game.id, fallback: .game) }
    func setContentKind(_ kind: CatalogKind, for app: WindowsApplication) { classify(kind, key: app.catalogKey, fallback: .application) }
    private func classify(_ kind: CatalogKind, key: String, fallback: CatalogKind) {
        let previous = state.contentKinds
        state.classify(key, as: kind, default: fallback)
        if !save() { state.contentKinds = previous }
    }
    func toggleFavorite(_ app: WindowsApplication) {
        let old = state.favorites
        if !state.favorites.insert(app.catalogKey).inserted { state.favorites.remove(app.catalogKey) }
        if !save() { state.favorites = old }
    }
}
