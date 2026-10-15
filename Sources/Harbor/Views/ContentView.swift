import SwiftUI
import HarborCore

struct ContentView: View {
    @Bindable var model: AppModel
    private var inspectorVisible: Binding<Bool> { Binding(get: { model.section == .library && model.selectedGameID != nil }, set: { if !$0 { model.selectedGameID = nil } }) }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 11) {
                    Image(systemName: "sailboat.fill").font(.system(size: 22)).foregroundStyle(Color.harbor)
                    VStack(alignment: .leading, spacing: 3) { Text("Harbor").font(.system(size: 18, weight: .semibold, design: .rounded)); Text("Windows 应用与游戏").font(.system(size: 10)).foregroundStyle(.secondary) }
                }.padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 18)
                List(selection: $model.section) {
                    Section {
                        ForEach(AppSection.allCases) { item in
                            HStack {
                                Label(item.title, systemImage: item.symbol)
                                if item == .activity && model.pendingLaunchCount > 0 { Spacer(); Text("\(model.pendingLaunchCount)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                            }.tag(item)
                        }
                    }
                }.listStyle(.sidebar)
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 9) {
                    Label(model.offlineCount > 0 ? "有磁盘未连接" : "文件保留原位", systemImage: model.offlineCount > 0 ? "externaldrive.badge.exclamationmark" : "checkmark.shield").font(.caption).foregroundStyle(.secondary)
                    Text("\(model.state.containers.count) 个容器 · \(model.applications.count) 个应用 · \(model.games.count) 款游戏").font(.caption2).foregroundStyle(.tertiary)
                    Divider().padding(.vertical, 5)
                    SettingsLink { Label("设置", systemImage: "gearshape").font(.callout) }.buttonStyle(.plain)
                    Text("本地预览 · 0.4.0").font(.system(size: 10)).foregroundStyle(.tertiary).padding(.top, 3)
                }.padding(20)
            }.navigationSplitViewColumnWidth(min: 185, ideal: 205, max: 240)
        } detail: {
            VStack(spacing: 0) {
                if let progress = model.currentLaunch, model.section != .activity,
                   !(model.section == .applications && progress.applicationID != nil && progress.applicationID == model.selectedApplicationID) {
                    LaunchProgressView(model: model, progress: progress, compact: true).padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 2)
                }
                if let notice = model.notice {
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "info.circle.fill").foregroundStyle(Color.harbor)
                        Text(notice).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                        Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("关闭提示")
                    }.padding(13).background(Color.harbor.opacity(0.07))
                }
                Group {
                    switch model.section {
                    case .library: LibraryView(model: model)
                    case .applications: ApplicationsView(model: model)
                    case .containers: ContainersView(model: model)
                    case .presets: PresetsView(model: model)
                    case .activity: ActivityView(model: model)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if model.isWorking {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text(model.activeStage).font(.caption).lineLimit(1)
                        Spacer(); Button("查看任务") { model.section = .activity }.buttonStyle(.plain).font(.caption).foregroundStyle(Color.harbor)
                    }.padding(.horizontal, 20).padding(.vertical, 10).background(.bar)
                }
            }
            .toolbar {
                ToolbarItemGroup {
                    Button { Task { await model.refresh() } } label: { Label("刷新", systemImage: "arrow.clockwise") }.help("刷新本机应用与游戏记录").disabled(model.isRefreshing)
                    Menu {
                        Button("安装 Windows 软件…", systemImage: "shippingbox") { model.showInstallApplication = true }
                        Button("添加已安装 EXE…", systemImage: "app.badge") { model.addApplication() }
                        Divider()
                        Button("新建托管容器…", systemImage: "shippingbox") { model.showCreate = true }
                        Button("关联现有 Wine 容器…", systemImage: "link") { model.linkContainer() }
                    } label: { Label("添加容器", systemImage: "plus") }
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
}
