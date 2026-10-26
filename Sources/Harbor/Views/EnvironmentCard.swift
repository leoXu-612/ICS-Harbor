import SwiftUI
import HarborCore

struct EnvironmentCard: View {
    @Bindable var model: AppModel
    let container: ContainerRecord
    @State private var detailsExpanded = false
    private var info: RuntimeInfo? { model.runtime[container.id] }
    private var conflict: Bool { model.hasLibraryConflict(container) }
    private var prepared: Bool { container.origin == .managed ? info?.applicationReady == true : info?.initialized == true }
    private var status: String { info == nil ? "正在检查" : !prepared ? "待准备" : model.busy.contains(container.id) ? "运行中" : "已停止" }
    var body: some View {
        Surface(padding: 24) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: container.origin == .linked ? "link" : "shippingbox").font(.system(size: 25)).foregroundStyle(Color.harbor).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(container.name).font(.system(size: 20, weight: .semibold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                        Text(container.origin == .linked ? "已关联 · 保留原环境和文件" : "独立托管环境").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Pill(title: status, symbol: model.busy.contains(container.id) ? "play.circle" : "pause.circle", color: model.busy.contains(container.id) ? .harborSignal : .secondary)
                    Menu {
                        Button("显示环境文件", systemImage: "folder") { model.reveal(container.wrapperPath) }
                        Divider()
                        if model.canCustomize(container) {
                            Button("恢复原始图形参数…") { model.restoreRuntimeParameters(container) }.disabled(model.busy.contains(container.id) || model.isWorking)
                        } else {
                            Button("备份并允许图形参数管理…") { model.authorizeRuntimeParameters(container) }.disabled(model.busy.contains(container.id) || model.isWorking)
                        }
                        Divider()
                        if container.origin == .managed {
                            Button("强制结束此环境…", role: .destructive) { model.endManagedRuntime(container) }.disabled(!model.busy.contains(container.id) || model.isWorking)
                        }
                        Button("移除记录，保留文件…", role: .destructive) { model.forgetContainer(container) }
                    } label: { Image(systemName: "ellipsis.circle") }.menuStyle(.borderlessButton).frame(width: 24).accessibilityLabel("环境的高级操作")
                }
                if conflict { LibraryConflictNotice() }
                if !prepared && container.origin == .managed {
                    TaskHint(title: "这个环境还需要准备", message: "继续之前的准备任务，不会另建或覆盖容器。", actionTitle: "继续准备") { model.provision(container) }
                        .disabled(model.isWorking || model.busy.contains(container.id))
                }
                if info?.hasSteam == true || container.preparesSteam {
                    SteamSessionControls(model: model, container: container)
                } else {
                    TaskHint(title: "通用 Windows 环境", message: "不需要 Steam。到应用页安装软件，或添加已经安装的 EXE。", symbol: "app", actionTitle: "前往应用页") { model.section = .applications }
                    DisclosureGroup("可选：在此环境安装 Steam") { SteamSessionControls(model: model, container: container).padding(.top, 12) }.font(.system(size: 13))
                }
                Divider()
                DisclosureGroup("磁盘、游戏库与技术信息", isExpanded: $detailsExpanded) {
                    VStack(alignment: .leading, spacing: 18) {
                        HStack(alignment: .top, spacing: 24) {
                            metadata("图形后端", info?.renderer ?? "待检查")
                            metadata("运行引擎", info?.engine ?? "待检查")
                        }
                        ForEach(model.libraries.filter { $0.containerID == container.id }) { library in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Label(library.drive == "C" ? "内置目录 · C:" : "\(volumeName(library)) · \(library.drive):", systemImage: library.drive == "C" ? "internaldrive" : "externaldrive").font(.system(size: 13, weight: .medium))
                                    Spacer(); Text("\(library.registeredCount) 款").font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Text(library.windowsPath).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                                if model.conflictingLibraries.contains(library.id) { Label("此库与原生 Steam 共用", systemImage: "exclamationmark.triangle").foregroundStyle(Color.harborFault).font(.system(size: 12)) }
                                else if !library.isOnline { Label("磁盘离线或不可读", systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(Color.harborWarning).font(.system(size: 12)) }
                            }
                        }
                        Text("关联环境的索引和原文件不会因界面升级而迁移。修改图形参数需先备份，且环境必须停止。").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(.top, 16)
                }.font(.system(size: 13, weight: .medium))
            }
        }.onAppear { detailsExpanded = conflict }.onChange(of: conflict) { _, value in if value { detailsExpanded = true } }
    }
    private func metadata(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 12)).foregroundStyle(.secondary); Text(text).font(.system(size: 13)).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func volumeName(_ library: LibraryRecord) -> String {
        if let path = library.unixPath, let volume = model.volumes.first(where: { path == $0.path || path.hasPrefix($0.path + "/") }) { return volume.name }
        return library.mappedTarget.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "外置磁盘"
    }
}
