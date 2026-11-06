import SwiftUI
import HarborCore

struct UnifiedCatalogView: View {
    let model: AppModel
    let source: CatalogSource?
    @State private var filter = UnifiedCatalogFilter()
    @State private var sort = [KeyPathComparator(\UnifiedCatalogEntry.name, comparator: .localizedStandard)]
    @State private var unreadablePaths: Set<String> = []
    @State private var showTraffic = false
    @State private var showWarnings = false
    @Environment(\.controlActiveState) private var activeState

    var body: some View {
        let entries = sourceEntries
        let rows = entries.filter(filter.includes).sorted(using: sort)
        let selected = visibleSelection(rows)
        let selectionState = SelectionState(game: model.selectedGameID, app: model.selectedApplicationID,
                                            visible: rows.map(\.id), keyWindow: activeState == .key)
        GeometryReader { geometry in
            let sideBySide = geometry.size.width >= 710
            HStack(spacing: 0) {
                if sideBySide || selected == nil {
                    VStack(alignment: .leading, spacing: 0) {
                        CatalogHeader(model: model, source: source, filter: $filter,
                                      showTraffic: { showTraffic = true })
                        Divider()
                        if !rows.isEmpty {
                            UnifiedCatalogTable(model: model, rows: rows,
                                                selection: Binding(get: { selected?.id }, set: select),
                                                sort: $sort)
                        } else {
                            CatalogEmptyView(model: model, source: source, hasEntries: !entries.isEmpty,
                                             clear: { filter = UnifiedCatalogFilter() })
                        }
                        Divider()
                        footer(visible: rows.count, total: entries.count)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let selected {
                    if sideBySide { Divider() }
                    inspector(selected)
                        .frame(width: sideBySide ? min(360, max(296, geometry.size.width * 0.33)) : geometry.size.width)
                }
            }
        }
        .background(CDSColor.surface1)
        .sheet(isPresented: $showTraffic) { CatalogTrafficSheet(model: model, application: nil) }
        .onChange(of: selectionState, initial: true) { old, current in
            // Other windows can have different filters on this shared AppModel.
            guard current.keyWindow else { return }
            let preferLocal = current.app != nil && (current.app != old.app || source == .local)
            select(visibleSelection(rows, preferLocal: preferLocal)?.id)
        }
        .task(id: fileCheck) {
            let paths = fileCheck.paths
            // A removable disk can stall a read; don't stat all EXEs on each keystroke.
            let unreadable = await Task.detached(priority: .utility) {
                Set(paths.filter { !FileManager.default.isReadableFile(atPath: $0) })
            }.value
            if !Task.isCancelled { unreadablePaths = unreadable }
        }
    }

    private var sourceEntries: [UnifiedCatalogEntry] {
        var records: [CatalogRecord] = []
        if source == nil || source == .steam { records += model.games.map(CatalogRecord.steam) }
        if source == nil || source == .local { records += model.applications.map(CatalogRecord.local) }
        return records.map { UnifiedCatalogEntry(record: $0, model: model, unreadablePaths: unreadablePaths) }
    }

    private struct FileCheck: Equatable {
        let paths: [String]
        let refreshed: Date?
    }
    private var fileCheck: FileCheck {
        FileCheck(paths: source == nil || source == .local ? model.applications.map(\.executablePath) : [],
                  refreshed: model.lastRefreshedAt)
    }

    private struct SelectionState: Equatable {
        let game: String?
        let app: UUID?
        let visible: [CatalogRecord.ID]
        let keyWindow: Bool
    }

    private func visibleSelection(_ rows: [UnifiedCatalogEntry], preferLocal: Bool = false) -> UnifiedCatalogEntry? {
        let steam = model.selectedGameID.map(CatalogRecord.ID.steam)
        let local = model.selectedApplicationID.map(CatalogRecord.ID.local)
        let ids = preferLocal ? [local, steam] : [steam, local]
        for case let id? in ids {
            if let entry = rows.first(where: { $0.id == id }) { return entry }
        }
        return nil
    }

    private func select(_ id: CatalogRecord.ID?) {
        switch id {
        case .steam(let gameID):
            if model.selectedApplicationID != nil { model.selectedApplicationID = nil }
            if model.selectedGameID != gameID { model.selectedGameID = gameID }
        case .local(let appID):
            if model.selectedGameID != nil { model.selectedGameID = nil }
            if model.selectedApplicationID != appID { model.selectedApplicationID = appID }
        case nil:
            if model.selectedGameID != nil { model.selectedGameID = nil }
            if model.selectedApplicationID != nil { model.selectedApplicationID = nil }
        }
    }

    private func inspector(_ entry: UnifiedCatalogEntry) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Label(entry.sourceTitle, systemImage: entry.record.source.symbol)
                Text("·")
                Text(entry.kindTitle)
                Spacer(minLength: 4)
                Menu {
                    CatalogItemControls(model: model, entry: entry)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("收藏与分类")
                .help("收藏与分类")
                Button { select(nil) } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .buttonStyle(.borderless)
                .help("关闭详情")
                .accessibilityLabel("关闭详情")
            }
            .cdsType(12, .medium)
            .foregroundStyle(CDSColor.textSecondary)
            .padding(.horizontal, CDSSpacing.base)
            .frame(height: 40)
            Divider()
            switch entry.record {
            case .steam(let game):
                GameInspector(model: model, game: game)
            case .local(let app):
                CatalogApplicationInspector(model: model, app: app, status: entry.status)
            }
        }
        .id(entry.id)
        .background(CDSColor.surface0)
    }

    private func footer(visible: Int, total: Int) -> some View {
        HStack(spacing: 8) {
            Text(visible == total ? "\(total) 项" : "显示 \(visible) / \(total) 项")
            if source == nil || source == .steam {
                if !model.conflictingLibraries.isEmpty {
                    Button("游戏库冲突") { model.navigate(.containers) }
                        .foregroundStyle(CDSColor.fault)
                }
                if model.offlineCount > 0 {
                    Button("\(model.offlineCount) 项磁盘离线") { model.navigate(.containers) }
                }
                if !model.warnings.isEmpty {
                    Button("扫描提示") { showWarnings.toggle() }
                        .popover(isPresented: $showWarnings) {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 10) {
                                    ForEach(model.warnings.indices, id: \.self) { Text(model.warnings[$0]) }
                                    Button("查看运行环境") { showWarnings = false; model.navigate(.containers) }
                                }
                                .padding()
                            }
                            .frame(width: 320, height: 180)
                            .background { FluoriteBackdrop(tone: CDSColor.surfacePopover) }
                        }
                }
            }
            Spacer(minLength: 4)
            if model.isRefreshing {
                ProgressView().controlSize(.mini)
                Text("正在刷新…")
            } else if let date = model.lastRefreshedAt {
                Text("刷新于 \(date.formatted(date: .omitted, time: .shortened))")
            }
        }
        .buttonStyle(.borderless)
        .cdsType(10.5)
        .foregroundStyle(CDSColor.textSecondary)
        .padding(.horizontal, CDSSpacing.base)
        .frame(height: 28)
    }
}
