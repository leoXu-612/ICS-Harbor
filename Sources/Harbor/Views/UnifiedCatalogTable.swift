import SwiftUI
import HarborCore

struct UnifiedCatalogTable: View {
    let model: AppModel
    let rows: [UnifiedCatalogEntry]
    @Binding var selection: CatalogRecord.ID?
    @Binding var sort: [KeyPathComparator<UnifiedCatalogEntry>]

    var body: some View {
        GeometryReader { geometry in
            catalog(width: geometry.size.width)
        }
    }

    // Give metadata its share of a wide window; leave the name column flexible.
    private func catalog(width: CGFloat) -> some View {
        Table(rows, selection: $selection, sortOrder: $sort) {
            TableColumn("名称", value: \.name) { entry in
                HStack(spacing: 8) {
                    switch entry.record {
                    case .steam(let game):
                        LocalArtwork(path: game.coverPath ?? game.heroPath)
                            .frame(width: 32, height: 36)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: CDSRadius.md))
                    case .local(let app):
                        WindowsApplicationIcon(executablePath: app.executablePath)
                    }
                    Text(entry.name).cdsType(12.5, .medium).lineLimit(1)
                    if entry.favorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9)).foregroundStyle(.secondary)
                            .accessibilityLabel("已收藏")
                    }
                }
                .padding(.vertical, 4)
                .help(entry.name)
            }
            .width(min: 110, ideal: 210)
            TableColumn("来源", value: \.sourceTitle) { entry in
                Label(entry.sourceTitle, systemImage: entry.record.source.symbol)
                    .labelStyle(.titleAndIcon).lineLimit(1)
            }
            .width(max(88, width * 0.16))
            TableColumn("类型", value: \.kindTitle)
                .width(max(40, width * 0.09))
            TableColumn("环境", value: \.environment) { entry in
                Text(entry.environment).lineLimit(1).help(entry.environment)
            }
            .width(max(72, width * 0.17))
            TableColumn("状态", value: \.statusTitle) { entry in
                CatalogStatusLabel(status: entry.status)
            }
            .width(max(85, width * 0.15))
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: CatalogRecord.ID.self) { ids in
            if let entry = rows.first(where: { ids.contains($0.id) }) {
                Button("显示详情", systemImage: "sidebar.trailing") { selection = entry.id }
                switch entry.record {
                case .steam(let game):
                    if let progress = model.progress(for: game), progress.isObservedRunning {
                        Button("显示窗口", systemImage: "macwindow") { model.focusLaunch(progress.id) }
                    } else {
                        Button("通过 Steam 启动", systemImage: "play.fill") { model.launchGame(game) }
                            .disabled(game.availability != .ready || entry.status == .conflict
                                      || model.isWorking || model.pendingLaunch(in: game.containerID) != nil)
                    }
                    if let path = game.installDirectory {
                        Button("显示安装目录", systemImage: "folder") { model.reveal(path) }
                    }
                case .local(let app):
                    Button("启动 EXE", systemImage: "play.fill") { model.launchApplication(app) }
                        .disabled(model.isWorking || model.pendingLaunch(in: app.containerID) != nil)
                    Button("启动设置…") { model.editApplication(app) }
                    Button("显示 EXE 文件", systemImage: "folder") { model.reveal(app.executablePath) }
                }
                Divider()
                CatalogItemControls(model: model, entry: entry)
            }
        } primaryAction: { ids in
            if let id = ids.first { selection = id }
        }
        .accessibilityLabel("内容目录")
    }
}

struct CatalogItemControls: View {
    let model: AppModel
    let entry: UnifiedCatalogEntry

    var body: some View {
        Button(entry.favorite ? "取消收藏" : "加入收藏",
               systemImage: entry.favorite ? "star.slash" : "star") {
            switch entry.record {
            case .steam(let game): model.toggleFavorite(game)
            case .local(let app): model.toggleFavorite(app)
            }
        }
        Menu("划分为") {
            Picker("类型", selection: Binding(get: { entry.kind }, set: { kind in
                switch entry.record {
                case .steam(let game): model.setContentKind(kind, for: game)
                case .local(let app): model.setContentKind(kind, for: app)
                }
            })) {
                Text(CatalogKind.game.title).tag(CatalogKind.game)
                Text(CatalogKind.application.title).tag(CatalogKind.application)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

struct CatalogStatusLabel: View {
    let status: CatalogStatus

    private var color: Color {
        switch status {
        case .installed, .windowDetected: CDSColor.signal
        case .starting: CDSColor.clay
        case .conflict, .failed: CDSColor.fault
        case .incomplete, .unreadable, .noEnvironment: CDSColor.warning
        case .offline, .missing, .unverified: CDSColor.textMuted
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6).accessibilityHidden(true)
            Text(status.rawValue).lineLimit(1)
        }
        .help(status == .unverified ? "已登记程序入口，尚无当前运行窗口的证据。" : status.rawValue)
    }
}
