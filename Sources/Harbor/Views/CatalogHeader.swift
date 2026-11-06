import SwiftUI
import HarborCore

struct CatalogHeader: View {
    let model: AppModel
    let source: CatalogSource?
    @Binding var filter: UnifiedCatalogFilter
    let showTraffic: () -> Void
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.snug) {
            HStack(spacing: CDSSpacing.snug) {
                Text(source == nil ? "全部内容" : "来源内容")
                    .cdsType(22, .semibold).lineLimit(1).layoutPriority(1)
                Spacer(minLength: 0)
                searchField.frame(minWidth: 110, maxWidth: 255)
                Menu {
                    if source == nil || source == .local {
                        Button("添加已有 EXE…") { model.addApplication() }.disabled(model.state.containers.isEmpty)
                        Button("安装 Windows 软件…") { model.guideApplicationSetup() }
                        Button("查看运行概览…", action: showTraffic)
                        Divider()
                    }
                    if source == nil || source == .steam {
                        Button("创建 Steam 环境…") { model.presentCreate(.steam) }
                    }
                    Button("关联已有环境…") { model.linkContainer() }
                    Button("管理运行环境") { model.navigate(.containers) }
                    Button("刷新目录") { Task { await model.refresh() } }.disabled(model.isRefreshing)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .fixedSize()
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .accessibilityLabel("目录操作")
                .help("目录操作")
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: CDSSpacing.tight) {
                    kindMenu
                    environmentMenu
                    statusMenu
                    favoriteToggle
                }
                HStack {
                    Menu("筛选条件") { kindMenu; environmentMenu; statusMenu }
                    favoriteToggle
                }
            }
            .controlSize(.small)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CDSSpacing.base)
        .padding(.vertical, CDSSpacing.base)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Button { searchFocused = true } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.plain)
                .keyboardShortcut("f", modifiers: .command)
                .accessibilityLabel("搜索目录")
            TextField("搜索名称、来源或 ID", text: $filter.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel("搜索目录")
            if !filter.query.isEmpty {
                Button { filter.query = ""; searchFocused = true } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(CDSColor.surface3, in: RoundedRectangle(cornerRadius: CDSRadius.lg))
        .overlay {
            RoundedRectangle(cornerRadius: CDSRadius.lg)
                .strokeBorder(searchFocused ? CDSColor.clay : CDSColor.border)
                .allowsHitTesting(false)
        }
    }

    private var kindMenu: some View {
        Menu(filter.kind?.title ?? "类型") {
            Picker("类型", selection: $filter.kind) {
                Text("所有类型").tag(CatalogKind?.none)
                Text(CatalogKind.game.title).tag(Optional(CatalogKind.game))
                Text(CatalogKind.application.title).tag(Optional(CatalogKind.application))
            }
            .pickerStyle(.inline)
        }
        .fixedSize()
        .accessibilityLabel("类型：\(filter.kind?.title ?? "全部")")
    }

    private var environmentMenu: some View {
        let name = filter.environmentID.map { model.container($0)?.name ?? "环境不可用" }
        return Menu {
            Picker("环境", selection: $filter.environmentID) {
                Text("所有环境").tag(UUID?.none)
                ForEach(model.state.containers) { Text($0.name).tag(Optional($0.id)) }
            }
            .pickerStyle(.inline)
        } label: {
            Text(name ?? "环境").lineLimit(1).truncationMode(.tail)
        }
        .frame(maxWidth: name == nil ? 60 : 130)
        .accessibilityLabel("环境：\(name ?? "全部")")
    }

    private var statusMenu: some View {
        Menu(filter.status?.rawValue ?? "状态") {
            Picker("状态", selection: $filter.status) {
                Text("所有状态").tag(CatalogStatus?.none)
                ForEach(CatalogStatus.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }
            .pickerStyle(.inline)
        }
        .fixedSize()
        .accessibilityLabel("状态：\(filter.status?.rawValue ?? "全部")")
    }

    private var favoriteToggle: some View {
        Toggle(isOn: $filter.favoritesOnly) {
            Label("收藏", systemImage: filter.favoritesOnly ? "star.fill" : "star")
        }
        .toggleStyle(.button)
        .tint(CDSColor.clay)
        .help("只显示已收藏的内容")
        .fixedSize()
    }
}

struct CatalogEmptyView: View {
    let model: AppModel
    let source: CatalogSource?
    let hasEntries: Bool
    let clear: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: CDSSpacing.base) {
                if let source, !source.isAvailable {
                    CDSIntro(symbol: source.symbol, title: "\(source.title) 尚未接入",
                             message: "此来源暂时不能读取清单或启动内容。可以从 Steam 或本地导入添加已有内容。")
                } else if hasEntries {
                    CDSIntro(symbol: "line.3.horizontal.decrease.circle", title: "没有匹配的内容",
                             message: "试试其他名称、Steam App ID 或 EXE 文件名，或清除筛选以查看当前来源。")
                    Button("清除搜索和筛选", action: clear).cdsButton(.outline, size: .md)
                } else if model.isRefreshing && source != .local {
                    ProgressView()
                    Text("正在读取本机清单…").foregroundStyle(.secondary)
                } else if source == .local {
                    ApplicationSetupView(model: model)
                } else if source == .steam {
                    CDSIntro(symbol: "gamecontroller", title: "还没有 Steam 内容",
                             message: "关联已有的 Wine 环境，或在环境中的 Steam 安装内容后刷新目录。")
                    HStack {
                        Button("关联已有环境…") { model.linkContainer() }.cdsButton(.primary, size: .md)
                        Button("创建 Steam 环境…") { model.presentCreate(.steam) }.cdsButton(.outline, size: .md)
                    }
                } else {
                    CDSIntro(symbol: "square.grid.2x2", title: "目录中还没有内容",
                             message: "关联 Wine 环境可读取 Steam 清单。已有本地程序也可以添加 EXE 入口，文件会留在原处。")
                    HStack {
                        Button("关联已有环境…") { model.linkContainer() }.cdsButton(.primary, size: .md)
                        if model.state.containers.isEmpty {
                            Button("创建运行环境…") { model.presentCreate() }.cdsButton(.outline, size: .md)
                        } else {
                            Button("添加已有 EXE…") { model.addApplication() }.cdsButton(.outline, size: .md)
                        }
                    }
                }
            }
            .padding(CDSSpacing.section)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
