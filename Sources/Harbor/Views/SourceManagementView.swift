import SwiftUI
import HarborCore

/// The source page supplies the title and the content/settings tabs.
struct SourceManagementView: View {
    let model: AppModel
    let source: CatalogSource

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CDSSpacing.section) {
                switch source {
                case .steam: steamSettings
                case .local: localSettings
                case .epic, .gog: upcomingSettings
                }
            }
            .padding(CDSSpacing.page)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(source)
    }

    private var steamEnvironments: [ContainerRecord] {
        model.state.containers.filter { $0.preparesSteam || model.runtime[$0.id]?.hasSteam == true }
    }

    @ViewBuilder private var steamSettings: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.snug) {
            CDSSectionHeader(title: "来源连接能力", subtitle: "通过环境中的 Windows Steam 接入。") {
                Button(model.isRefreshing ? "正在刷新…" : "刷新本机索引", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .cdsButton(.outline, size: .sm)
                .disabled(model.isRefreshing || model.isWorking)
                .help("重新扫描所有环境的 Steam 清单，同时按已保存的绑定检查缺失盘符。")
            }
            capability("doc.text.magnifyingglass", "读取本机游戏库清单", "只列出环境已登记的内容，不同步账号的云端收藏。")
            capability("macwindow", "通过 Steam 启动", "安装、更新和登录在各环境自己的 Steam 客户端中完成。")
        }

        VStack(alignment: .leading, spacing: CDSSpacing.snug) {
            CDSSectionHeader(title: "使用此来源的环境", subtitle: "展开环境，查看客户端状态或管理会话。") {
                Menu {
                    Button("关联已有环境…") { model.linkContainer() }
                    Button("创建 Steam 环境…") { model.presentCreate(.steam) }
                        .disabled(model.isWorking)
                } label: { Label("添加环境", systemImage: "plus") }
                .fixedSize()
            }
            if steamEnvironments.isEmpty {
                note(model.lastRefreshedAt == nil && !model.state.containers.isEmpty ? "正在读取环境信息…" : "尚未发现使用 Steam 的环境。可关联已有环境，或创建独立环境。")
            } else {
                ForEach(steamEnvironments) { container in
                    SteamSessionControls(model: model, container: container)
                }
            }

            // General-purpose managed environments are candidates, not connected Steam sources.
            let candidates = model.state.containers.filter {
                $0.origin == .managed && !$0.preparesSteam && model.runtime[$0.id]?.hasSteam == false
            }
            if !candidates.isEmpty {
                DisclosureGroup("在其他托管环境中安装 Steam") {
                    VStack(spacing: CDSSpacing.tight) {
                        ForEach(candidates) { container in
                            SteamSessionControls(model: model, container: container)
                        }
                    }
                    .padding(.top, CDSSpacing.tight)
                }
                .font(.callout)
            }
        }
    }

    @ViewBuilder private var localSettings: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.snug) {
            CDSSectionHeader(title: "本地程序接入")
            TaskHint(title: "导入已安装的 EXE", message: "选择程序和运行环境，只登记启动入口，文件留在原处。",
                     symbol: "square.and.arrow.down", actionTitle: "选择程序…") { model.addApplication() }
                .disabled(model.state.containers.isEmpty)
            TaskHint(title: "运行 EXE 或 MSI 安装包", message: "在已准备的托管环境中安装。安装结束后，再导入实际程序的 EXE。",
                     symbol: "shippingbox", actionTitle: "选择安装包…") { model.showInstallApplication = true }
                .disabled(!model.state.containers.contains(where: { $0.origin == .managed }) || model.isWorking)
            if !model.state.containers.contains(where: { $0.origin == .managed }) {
                Button("创建通用运行环境…", systemImage: "plus") { model.presentCreate() }
                    .cdsButton(.outline, size: .sm)
                    .disabled(model.isWorking)
            }
            Button("管理运行环境", systemImage: "square.3.layers.3d") { model.navigate(.containers) }
                .cdsButton(.ghost, size: .sm)
        }

        VStack(alignment: .leading, spacing: CDSSpacing.snug) {
            CDSSectionHeader(title: "已登记的入口", subtitle: "编辑名称、程序路径、工作目录或启动参数。")
            if model.applications.isEmpty {
                note("尚未登记本地程序。")
            } else {
                ForEach(model.applications.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { app in
                    HStack(spacing: CDSSpacing.snug) {
                        Image(systemName: "macwindow").foregroundStyle(CDSColor.textSecondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.name).cdsType(13, .medium)
                            note(model.container(app.containerID)?.name ?? "环境不可用")
                            Text(Format.path(app.executablePath)).cdsType(10, mono: true)
                                .foregroundStyle(CDSColor.textMuted).lineLimit(1).truncationMode(.middle)
                                .help(app.executablePath)
                        }
                        Spacer()
                        Button("编辑入口…") { model.editApplication(app) }.cdsButton(.outline, size: .sm)
                    }
                    CDSHairline()
                }
            }
        }
    }

    private var upcomingSettings: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.snug) {
            CDSSectionHeader(title: "\(source.title) 尚未接入")
            note("Harbor 目前不能连接此商店账号，也不能读取其游戏库或同步安装状态。")
            CDSHairline().padding(.vertical, 4)
            TaskHint(title: "已有 Windows 程序或离线安装包",
                     message: "可通过本地导入登记 EXE，或在托管环境中运行安装包。需要商店客户端或授权的程序仍受原有要求限制。",
                     symbol: "square.and.arrow.down", actionTitle: "本地导入设置") {
                model.openSourceSettings(.local)
            }
        }
    }

    private func capability(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: CDSSpacing.snug) {
            CDSIconTile(symbol: symbol, size: 30, tint: CDSColor.signal)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).cdsType(13, .medium)
                note(detail)
            }
        }
    }

    private func note(_ value: String) -> some View {
        Text(value).cdsType(11.5).foregroundStyle(CDSColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
