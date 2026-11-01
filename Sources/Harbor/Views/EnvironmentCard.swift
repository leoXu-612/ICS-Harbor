import SwiftUI
import HarborCore

struct EnvironmentCard: View {
    @Bindable var model: AppModel
    let container: ContainerRecord
    @State private var detailsExpanded = false

    private var info: RuntimeInfo? { model.runtime[container.id] }
    private var conflict: Bool { model.hasLibraryConflict(container) }
    private var prepared: Bool {
        container.origin == .managed ? info?.applicationReady == true : info?.initialized == true
    }
    private var status: String {
        info == nil ? "正在检查"
            : !prepared ? "待准备"
            : model.busy.contains(container.id) ? "运行中" : "已停止"
    }
    private var statusDot: CDSStatusDot.Kind {
        info == nil ? .idle : !prepared ? .attention : model.busy.contains(container.id) ? .live : .idle
    }

    var body: some View {
        CDSSurface(level: .two, radius: CDSRadius.xl, padding: CDSSpacing.roomy) {
            VStack(alignment: .leading, spacing: CDSSpacing.roomy) {
                header
                if conflict { LibraryConflictNotice() }

                if !prepared && container.origin == .managed {
                    TaskHint(title: "这个环境还需要准备",
                             message: "继续之前的准备任务，不会另建或覆盖容器。",
                             actionTitle: "继续准备") { model.provision(container) }
                        .disabled(model.isWorking || model.busy.contains(container.id))
                }

                if info?.hasSteam == true || container.preparesSteam {
                    SteamSessionControls(model: model, container: container)
                } else {
                    TaskHint(title: "通用 Windows 环境",
                             message: "不需要 Steam。到应用页安装软件，或添加已经安装的 EXE。",
                             symbol: "macwindow",
                             actionTitle: "前往应用页") { model.section = .applications }
                    DisclosureGroup("可选：在此环境安装 Steam") {
                        SteamSessionControls(model: model, container: container)
                            .padding(.top, CDSSpacing.snug)
                    }
                    .font(.system(size: 11.5))
                }

                CDSHairline()

                DisclosureGroup("磁盘、游戏库与技术信息", isExpanded: $detailsExpanded) {
                    technicalDetails.padding(.top, CDSSpacing.base)
                }
                .font(.system(size: 12, weight: .medium))
            }
        }
        .onAppear { detailsExpanded = conflict }
        .onChange(of: conflict) { _, value in if value { detailsExpanded = true } }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: CDSSpacing.snug) {
            CDSIconTile(symbol: container.origin == .linked ? "link" : "shippingbox", size: 38)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(container.name)
                    .cdsType(17, .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                Text(container.origin == .linked ? "已关联 · 保留原环境和文件" : "独立托管环境")
                    .cdsType(10.5)
                    .foregroundStyle(CDSColor.textSecondary)
            }

            Spacer(minLength: CDSSpacing.tight)

            HStack(spacing: 5) {
                CDSStatusDot(kind: statusDot, size: 5)
                Text(status).cdsType(10.5)
            }
            .foregroundStyle(model.busy.contains(container.id) ? CDSColor.signal : CDSColor.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(CDSColor.fillTertiary, in: Capsule())

            Menu {
                Button("显示环境文件", systemImage: "folder") { model.reveal(container.wrapperPath) }
                Divider()
                if model.canCustomize(container) {
                    Button("恢复原始图形参数…") { model.restoreRuntimeParameters(container) }
                        .disabled(model.busy.contains(container.id) || model.isWorking)
                } else {
                    Button("备份并允许图形参数管理…") { model.authorizeRuntimeParameters(container) }
                        .disabled(model.busy.contains(container.id) || model.isWorking)
                }
                Divider()
                if container.origin == .managed {
                    Button("强制结束此环境…", role: .destructive) { model.endManagedRuntime(container) }
                        .disabled(!model.busy.contains(container.id) || model.isWorking)
                }
                Button("移除记录，保留文件…", role: .destructive) { model.forgetContainer(container) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 12, weight: .medium))
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
            .accessibilityLabel("环境的高级操作")
        }
    }

    private var technicalDetails: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.base) {
            HStack(spacing: CDSSpacing.snug) {
                metadata("图形后端", info?.renderer ?? "待检查")
                metadata("运行引擎", info?.engine ?? "待检查")
            }

            ForEach(model.libraries.filter { $0.containerID == container.id }) { library in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: library.drive == "C" ? "internaldrive" : "externaldrive")
                            .font(.system(size: 11))
                            .foregroundStyle(CDSColor.textSecondary)
                        Text(library.drive == "C" ? "内置目录 · C:" : "\(volumeName(library)) · \(library.drive):")
                            .cdsType(11.5, .medium)
                        Spacer(minLength: CDSSpacing.tight)
                        Text("\(library.registeredCount) 款")
                            .cdsType(10, mono: true)
                            .foregroundStyle(CDSColor.textMuted)
                    }
                    Text(library.windowsPath)
                        .cdsType(9.5, mono: true)
                        .foregroundStyle(CDSColor.textMuted)
                        .textSelection(.enabled)
                    if model.conflictingLibraries.contains(library.id) {
                        Label("此库与原生 Steam 共用", systemImage: "exclamationmark.triangle")
                            .font(.system(size: 10))
                            .foregroundStyle(CDSColor.fault)
                    } else if !library.isOnline {
                        Label("磁盘离线或不可读", systemImage: "externaldrive.badge.exclamationmark")
                            .font(.system(size: 10))
                            .foregroundStyle(CDSColor.warning)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(CDSColor.fillTertiary,
                            in: RoundedRectangle(cornerRadius: CDSRadius.lg, style: .continuous))
            }

            Text("关联环境的索引和原文件不会因界面升级而迁移。修改图形参数需先备份，且环境必须停止。")
                .cdsType(10)
                .foregroundStyle(CDSColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func metadata(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).cdsType(9.5).foregroundStyle(CDSColor.textMuted)
            Text(text).cdsType(11.5, .medium).textSelection(.enabled).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CDSColor.fillTertiary,
                    in: RoundedRectangle(cornerRadius: CDSRadius.lg, style: .continuous))
    }

    private func volumeName(_ library: LibraryRecord) -> String {
        if let path = library.unixPath,
           let volume = model.volumes.first(where: { path == $0.path || path.hasPrefix($0.path + "/") }) {
            return volume.name
        }
        return library.mappedTarget.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "外置磁盘"
    }
}
