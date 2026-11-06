import Foundation
import HarborCore

/// The launch record is independent of the user-assigned display kind.
enum CatalogRecord {
    case steam(GameRecord)
    case local(WindowsApplication)

    enum ID: Hashable {
        case steam(String), local(UUID)
    }

    var id: ID {
        switch self {
        case .steam(let game): .steam(game.id)
        case .local(let app): .local(app.id)
        }
    }

    var source: CatalogSource {
        switch self {
        case .steam: .steam
        case .local: .local
        }
    }

    var containerID: UUID {
        switch self {
        case .steam(let game): game.containerID
        case .local(let app): app.containerID
        }
    }

    var name: String {
        switch self {
        case .steam(let game): game.name
        case .local(let app): app.name
        }
    }

    var searchIdentifier: String {
        switch self {
        case .steam(let game): game.appID
        case .local(let app): URL(fileURLWithPath: app.executablePath).lastPathComponent
        }
    }
}

enum CatalogStatus: String, CaseIterable {
    case installed = "已安装"
    case unverified = "未验证"
    case starting = "正在启动"
    case windowDetected = "已检测到窗口"
    case failed = "上次启动失败"
    case offline = "磁盘离线"
    case incomplete = "安装未完成"
    case missing = "文件待确认"
    case unreadable = "EXE 不可读"
    case noEnvironment = "环境不可用"
    case conflict = "游戏库冲突"

    static func resolve(_ record: CatalogRecord, outcome: LaunchOutcome?,
                        hasEnvironment: Bool, hasConflict: Bool, unreadable: Bool) -> Self {
        if outcome == .pending { return .starting }
        if outcome == .windowDetected { return .windowDetected }
        guard hasEnvironment else { return .noEnvironment }
        switch record {
        case .steam(let game):
            switch game.availability {
            case .offline: return .offline
            case .incomplete: return .incomplete
            case .missing: return .missing
            case .ready:
                if hasConflict { return .conflict }
                return outcome == .failed ? .failed : .installed
            }
        case .local:
            if unreadable { return .unreadable }
            return outcome == .failed ? .failed : .unverified
        }
    }
}

struct UnifiedCatalogEntry: Identifiable {
    let record: CatalogRecord
    let kind: CatalogKind
    let environment: String
    let status: CatalogStatus
    let favorite: Bool

    var id: CatalogRecord.ID { record.id }
    var name: String { record.name }
    var sourceTitle: String { record.source.title }
    var kindTitle: String { kind.title }
    var statusTitle: String { status.rawValue }

    @MainActor init(record: CatalogRecord, model: AppModel, unreadablePaths: Set<String>) {
        self.record = record
        let container = model.container(record.containerID)
        environment = container?.name ?? "环境不可用"
        let outcome: LaunchOutcome?
        let conflict: Bool
        let unreadable: Bool
        switch record {
        case .steam(let game):
            kind = model.contentKind(for: game)
            favorite = model.state.favorites.contains(game.id)
            outcome = model.progress(for: game)?.outcome
            conflict = container.map(model.hasLibraryConflict) ?? false
            unreadable = false
        case .local(let app):
            kind = model.contentKind(for: app)
            favorite = model.state.favorites.contains(app.catalogKey)
            outcome = model.applicationProgress(app)?.outcome
            conflict = false
            unreadable = unreadablePaths.contains(app.executablePath)
        }
        status = .resolve(record, outcome: outcome, hasEnvironment: container != nil,
                          hasConflict: conflict, unreadable: unreadable)
    }
}

struct UnifiedCatalogFilter: Equatable {
    var query = ""
    var kind: CatalogKind?
    var environmentID: UUID?
    var status: CatalogStatus?
    var favoritesOnly = false

    func includes(_ entry: UnifiedCatalogEntry) -> Bool {
        guard kind == nil || kind == entry.kind,
              environmentID == nil || environmentID == entry.record.containerID,
              status == nil || status == entry.status,
              !favoritesOnly || entry.favorite else { return false }
        let words = query.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return true }
        let fields = [entry.name, entry.sourceTitle, entry.kindTitle, entry.environment,
                      entry.statusTitle, entry.record.searchIdentifier]
        return words.allSatisfy { word in fields.contains { $0.localizedStandardContains(String(word)) } }
    }
}
