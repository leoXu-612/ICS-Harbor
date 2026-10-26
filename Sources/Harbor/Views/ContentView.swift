import SwiftUI
import HarborCore

struct ContentView: View {
    @Bindable var model: AppModel
    private var inspectorVisible: Binding<Bool> { Binding(get: { model.section == .library && model.selectedGameID != nil }, set: { if !$0 { model.selectedGameID = nil } }) }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "sailboat.fill").font(.system(size: 24)).foregroundStyle(Color.harbor).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Harbor").font(.system(size: 21, weight: .semibold, design: .rounded))
                        Text("Windows 应用与游戏").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 18).padding(.top, 24).padding(.bottom, 20)
                List(selection: $model.section) {
                    Section("资料库") { sidebarRow(.library); sidebarRow(.applications) }
                    Section("管理") { sidebarRow(.containers); sidebarRow(.activity) }
                    Section("帮助") { sidebarRow(.guide); sidebarRow(.presets) }
                }.listStyle(.sidebar).tint(.harborAction)
                VStack(alignment: .leading, spacing: 12) {
                    if !model.conflictingLibraries.isEmpty {
                        Button { model.section = .containers } label: { Label("有库冲突待处理", systemImage: "exclamationmark.shield") }.buttonStyle(.plain).foregroundStyle(Color.harborFault)
                    } else { Label("索引保留在本机", systemImage: "checkmark.shield").foregroundStyle(.secondary) }
                    Text("\(model.state.containers.count) 个环境 · \(model.applications.count) 个应用 · \(model.games.count) 款游戏").foregroundStyle(.secondary)
                    Divider()
                    HStack {
                        SettingsLink { Label("设置", systemImage: "gearshape") }.buttonStyle(.plain)
                        Spacer(); Text(AppPaths.version).foregroundStyle(.secondary).monospacedDigit()
                    }
                }.font(.system(size: 12)).padding(18)
            }.navigationSplitViewColumnWidth(min: 190, ideal: 215, max: 250)
        } detail: {
            VStack(spacing: 0) {
                if let progress = model.currentLaunch, model.section != .activity,
                   !(model.section == .applications && progress.applicationID != nil && progress.applicationID == model.selectedApplicationID) {
                    LaunchProgressView(model: model, progress: progress, compact: true).padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 2)
                }
                if let notice = model.notice {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary).accessibilityHidden(true)
                        Text(notice).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
                        Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless).accessibilityLabel("关闭提示")
                    }.padding(.horizontal, 28).padding(.vertical, 12).background(.quaternary.opacity(0.25))
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
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.isWorking {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.activeStage).font(.caption).lineLimit(2)
                        Spacer(); Button("查看进度") { model.section = .activity }.controlSize(.small)
                    }.padding(.horizontal, 24).padding(.vertical, 12).background(.bar)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button { Task { await model.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.help("重新读取环境与磁盘状态").disabled(model.isRefreshing)
                    Button { model.section = .guide } label: { Label("指南", systemImage: "questionmark.circle") }.labelStyle(.titleAndIcon)
                    Menu {
                        Button("安装 Windows 软件…", systemImage: "shippingbox") { model.section = .applications; model.guideApplicationSetup() }
                        Button("添加已有 EXE…", systemImage: "app.badge") { model.addApplication() }.disabled(model.state.containers.isEmpty)
                        Divider()
                        Button("创建运行环境…", systemImage: "plus.rectangle.on.folder") { model.presentCreate() }
                        Button("关联现有 Wine 环境…", systemImage: "link") { model.linkContainer() }
                    } label: { Label("添加", systemImage: "plus") }.labelStyle(.titleAndIcon).help("添加应用或运行环境")
                    if model.section == .library && model.selectedGameID != nil {
                        Button { model.selectedGameID = nil } label: { Label("关闭详情", systemImage: "sidebar.trailing") }.help("关闭游戏详情")
                    }
                }
            }
            .inspector(isPresented: inspectorVisible) {
                if let game = model.selectedGame { GameInspector(model: model, game: game).id(game.id).inspectorColumnWidth(min: 300, ideal: 320, max: 380) }
            }
        }
        .navigationTitle(model.section.title)
        .frame(minWidth: 980, minHeight: 680)
        .tint(.harbor)
        .sheet(isPresented: $model.showCreate) { CreateContainerView(model: model) }
        .sheet(isPresented: $model.showBind) { BindDriveView(model: model) }
        .sheet(isPresented: $model.showAddApplication) { ApplicationEditor(model: model) }
        .sheet(isPresented: $model.showInstallApplication) { InstallApplicationView(model: model) }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }
    private func sidebarRow(_ item: AppSection) -> some View {
        HStack {
            Label(item.title, systemImage: item.symbol).font(.system(size: 13))
            if item == .activity && model.pendingLaunchCount > 0 { Spacer(); Text("\(model.pendingLaunchCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
        }.padding(.vertical, 3).tag(item)
    }
}
