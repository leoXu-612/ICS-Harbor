import SwiftUI
import HarborCore

struct ContentView: View {
    @Bindable var model: AppModel

    private var inspectorVisible: Binding<Bool> {
        Binding(get: { model.section == .library && model.selectedGameID != nil },
                set: { if !$0 { model.selectedGameID = nil } })
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 196, ideal: 212, max: 252)
        } detail: {
            detail
        }
        .navigationTitle("")
        .frame(minWidth: 1000, minHeight: 680)
        .tint(CDSColor.clay)
        .sheet(isPresented: $model.showCreate) { CreateContainerView(model: model) }
        .sheet(isPresented: $model.showBind) { BindDriveView(model: model) }
        .sheet(isPresented: $model.showAddApplication) { ApplicationEditor(model: model) }
        .sheet(isPresented: $model.showInstallApplication) { InstallApplicationView(model: model) }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil },
                                              set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    // MARK: 侧边栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    navGroup("资料库", items: [.library, .applications])
                    navGroup("管理", items: [.containers, .activity])
                    navGroup("帮助", items: [.guide, .presets])
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            Spacer(minLength: 8)
            footer
        }
        .background(CDSColor.surface0)
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous)
                    .fill(CDSColor.claySubtle)
                Image(systemName: "sailboat.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(CDSColor.clay)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Harbor").cdsType(15, .semibold, tracking: -0.2)
                Text("Windows 应用与游戏").cdsType(10).foregroundStyle(CDSColor.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func navGroup(_ title: String, items: [AppSection]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .cdsType(9.5, .medium, tracking: 0.6)
                .foregroundStyle(CDSColor.textMuted)
                .padding(.horizontal, 9)
                .padding(.bottom, 4)

            ForEach(items) { item in
                SidebarRow(
                    item: item,
                    selected: model.section == item,
                    badge: item == .activity && model.pendingLaunchCount > 0 ? model.pendingLaunchCount : nil
                ) {
                    withAnimation(CDSMotion.snappy) { model.section = item }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            CDSHairline(inset: 4)

            if !model.conflictingLibraries.isEmpty {
                Button {
                    model.section = .containers
                } label: {
                    HStack(spacing: 6) {
                        CDSStatusDot(kind: .fault, size: 5)
                        Text("有库冲突待处理").cdsType(10.5, .medium)
                    }
                    .foregroundStyle(CDSColor.fault)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            } else {
                HStack(spacing: 6) {
                    CDSStatusDot(kind: .live, size: 5)
                    Text("索引保留在本机").cdsType(10.5).foregroundStyle(CDSColor.textSecondary)
                }
                .padding(.leading, 4)
            }

            Text("\(model.state.containers.count) 个环境 · \(model.applications.count) 个应用 · \(model.games.count) 款游戏")
                .cdsType(10)
                .foregroundStyle(CDSColor.textMuted)
                .padding(.leading, 4)

            HStack(spacing: 10) {
                SettingsLink {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape").font(.system(size: 11))
                        Text("设置").cdsType(11.5, .medium)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(CDSColor.textSecondary)

                Spacer(minLength: 0)

                Text(AppPaths.version)
                    .cdsType(10, mono: true)
                    .foregroundStyle(CDSColor.textMuted)
            }
            .padding(.leading, 4)
            .padding(.top, 1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    // MARK: 详情区

    private var detail: some View {
        VStack(spacing: 0) {
            if let progress = model.currentLaunch, model.section != .activity,
               !(model.section == .applications && progress.applicationID != nil
                 && progress.applicationID == model.selectedApplicationID) {
                LaunchProgressView(model: model, progress: progress, compact: true)
                    .padding(.horizontal, CDSSpacing.page)
                    .padding(.top, 16)
                    .padding(.bottom, 2)
            }

            if let notice = model.notice {
                CDSNotice(text: notice, onClose: { model.notice = nil })
                    .padding(.horizontal, CDSSpacing.page)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Group {
                switch model.section {
                case .library: LibraryView(model: model)
                case .applications: ApplicationsView(model: model)
                case .containers: ContainersView(model: model)
                case .presets: PresetsView(model: model)
                case .activity: ActivityView(model: model)
                case .guide: GuideView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.isWorking {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small).tint(CDSColor.clay)
                    Text(model.activeStage)
                        .cdsType(11)
                        .foregroundStyle(CDSColor.textSecondary)
                        .lineLimit(2)
                    Spacer()
                    Button("查看进度") { model.section = .activity }
                        .cdsButton(.ghost, size: .xs)
                }
                .padding(.horizontal, CDSSpacing.roomy)
                .padding(.vertical, 9)
                .background(CDSColor.surface0)
                .overlay(alignment: .top) { CDSHairline() }
            }
        }
        .background(CDSColor.surface1)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("重新读取环境与磁盘状态")
                .disabled(model.isRefreshing)

                Button { model.section = .guide } label: {
                    Label("指南", systemImage: "questionmark.circle")
                }
                .labelStyle(.titleAndIcon)

                Menu {
                    Button("安装 Windows 软件…", systemImage: "shippingbox") {
                        model.section = .applications
                        model.guideApplicationSetup()
                    }
                    Button("添加已有 EXE…", systemImage: "app.badge") { model.addApplication() }
                        .disabled(model.state.containers.isEmpty)
                    Divider()
                    Button("创建运行环境…", systemImage: "plus.rectangle.on.folder") { model.presentCreate() }
                    Button("关联现有 Wine 环境…", systemImage: "link") { model.linkContainer() }
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .labelStyle(.titleAndIcon)
                .help("添加应用或运行环境")

                if model.section == .library && model.selectedGameID != nil {
                    Button { model.selectedGameID = nil } label: {
                        Label("关闭详情", systemImage: "sidebar.trailing")
                    }
                    .help("关闭游戏详情")
                }
            }
        }
        .inspector(isPresented: inspectorVisible) {
            if let game = model.selectedGame {
                GameInspector(model: model, game: game)
                    .id(game.id)
                    .inspectorColumnWidth(min: 300, ideal: 330, max: 400)
            }
        }
    }
}

// MARK: - 侧栏行

private struct SidebarRow: View {
    let item: AppSection
    let selected: Bool
    let badge: Int?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? CDSColor.clay : CDSColor.textSecondary)
                    .frame(width: 16)
                Text(item.title)
                    .cdsType(12.5, selected ? .medium : .regular)
                    .foregroundStyle(selected ? CDSColor.textPrimary : CDSColor.textSecondary)
                Spacer(minLength: 4)
                if let badge {
                    Text("\(badge)")
                        .cdsType(10, .medium, mono: true)
                        .foregroundStyle(CDSColor.clay)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(CDSColor.claySubtle, in: Capsule())
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                selected ? CDSColor.fillGhostSelected
                         : hovering ? CDSColor.fillGhostHover : .clear,
                in: RoundedRectangle(cornerRadius: CDSRadius.lg, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: CDSRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(CDSMotion.honoring(reduceMotion, CDSMotion.press), value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
