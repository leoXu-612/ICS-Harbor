import SwiftUI
import HarborCore

struct EnvironmentCard: View {
    let model: AppModel
    let container: ContainerRecord
    @State private var showBinding = false

    private var info: RuntimeInfo? { model.runtime[container.id] }
    private var signal: LaunchEvidence? { model.containerSignals[container.id] }
    private var pending: LaunchProgress? { model.pendingLaunch(in: container.id) }
    private var occupied: Bool {
        model.busy.contains(container.id) || signal?.runtimeRunning == true || signal?.steamPID != nil || signal?.gamePID != nil
    }
    private var canMaintain: Bool { info != nil && !occupied && pending == nil && !model.isWorking }
    private var prepared: Bool {
        container.origin == .managed ? info?.applicationReady == true : info?.initialized == true
    }
    private var hasSteam: Bool { info?.hasSteam == true }
    private var games: [GameRecord] { model.games.filter { $0.containerID == container.id } }
    private var apps: [WindowsApplication] { model.applications.filter { $0.containerID == container.id } }
    private var bindings: [DriveBinding] { model.state.bindings.filter { $0.containerID == container.id } }
    private var libraries: [LibraryRecord] { model.libraries.filter { $0.containerID == container.id } }
    private var status: String {
        if occupied { return "检测到进程" }
        if pending != nil { return "有启动请求" }
        guard info != nil else { return "等待检查" }
        if !prepared { return container.origin == .managed ? "待准备" : "未检测到已初始化的环境" }
        return "未检测到占用"
    }

    var body: some View {
        CDSSurface(level: .two) {
            VStack(alignment: .leading, spacing: CDSSpacing.base) {
                HStack(spacing: CDSSpacing.snug) {
                    CDSIconTile(symbol: "square.3.layers.3d", size: 38)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(container.name).cdsType(17, .semibold)
                        Text(container.origin == .linked ? "已关联的外部环境" : "Harbor 托管环境")
                            .cdsType(11).foregroundStyle(CDSColor.textSecondary)
                    }
                    Spacer()
                    CDSStatusDot(kind: occupied || pending != nil ? .attention : .idle, size: 5)
                    Text(status).cdsType(11).foregroundStyle(CDSColor.textSecondary)
                }
                if occupied || pending != nil {
                    CDSNotice(text: occupancyDetail, symbol: "exclamationmark.triangle", tone: CDSColor.warning)
                }
                if model.hasLibraryConflict(container) { LibraryConflictNotice() }

                linkedContent
                CDSHairline()
                DisclosureGroup("引擎与维护") { maintenance.padding(.top, CDSSpacing.snug) }
                DisclosureGroup("磁盘与游戏库") { disks.padding(.top, CDSSpacing.snug) }
            }
            .cdsType(12)
        }
        .sheet(isPresented: $showBinding) { BindDriveView(model: model, fixedContainer: container) }
    }

    private var occupancyDetail: String {
        var evidence: [String] = []
        if let pid = signal?.steamPID { evidence.append("Steam 客户端（PID \(pid)）") }
        // A checkpoint is historical. Name a process only if the latest sample still saw its PID.
        let observed = model.launchProgress.values.filter {
            $0.containerID == container.id && !$0.isSteamClient && ($0.isPending || $0.isObservedRunning)
                && $0.checkedAt != nil && $0.checkedAt == $0.lastProcessSeenAt && $0.targetPID != nil
        }
        for launch in observed.sorted(by: { $0.startedAt < $1.startedAt }) {
            if let pid = launch.targetPID { evidence.append("\(launch.title)（PID \(pid)）") }
        }
        if let pending { evidence.append("启动请求：\(pending.title)") }
        if evidence.isEmpty { evidence.append("检测到此环境中的 Wine 进程") }
        return evidence.joined(separator: " · ") + "。更改图形参数前，请先保存并正常退出程序。"
    }

    private var linkedContent: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.tight) {
            CDSSectionHeader(title: "关联内容", subtitle: model.lastRefreshedAt == nil
                             ? "本地入口已登记，Steam 索引待检查。"
                             : "此环境共用一套引擎与磁盘映射：\(games.count) 个 Steam 条目，\(apps.count) 个本地入口。")
            if hasSteam {
                contentRow("Steam 客户端", symbol: "macwindow", detail: signal?.steamPID != nil ? "检测到进程 · 接入设置" : "已发现程序 · 接入设置") {
                    model.openSourceSettings(.steam)
                }
            }
            if !games.isEmpty {
                DisclosureGroup("Steam 条目 · \(games.count)") {
                    ForEach(games) { game in
                        contentRow(game.name, symbol: "gamecontroller", detail: game.availability.title) {
                            model.navigate(.steam)
                            model.selectedGameID = game.id
                        }
                    }
                }
            }
            if !apps.isEmpty {
                DisclosureGroup("本地入口 · \(apps.count)") {
                    ForEach(apps) { app in
                        contentRow(app.name, symbol: "macwindow", detail: "本地导入") {
                            model.navigate(.local)
                            model.selectedApplicationID = app.id
                        }
                    }
                }
            }
            HStack(spacing: CDSSpacing.tight) {
                if !hasSteam && (container.preparesSteam || container.origin == .managed) {
                    Button("Steam 接入设置", systemImage: "arrow.up.forward") { model.openSourceSettings(.steam) }
                        .cdsButton(.ghost, size: .sm)
                }
                Button("本地导入设置", systemImage: "arrow.up.forward") { model.openSourceSettings(.local) }
                    .cdsButton(.ghost, size: .sm)
            }
        }
    }

    private func contentRow(_ name: String, symbol: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: CDSSpacing.tight) {
                Label(name, systemImage: symbol).cdsType(12, .medium)
                Spacer()
                Text(detail).cdsType(10.5).foregroundStyle(CDSColor.textSecondary)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(CDSColor.textMuted)
            }
            .padding(8)
            .background(CDSColor.fillTertiary, in: RoundedRectangle(cornerRadius: CDSRadius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var maintenance: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.tight) {
            CDSKeyValue(label: "环境路径", value: Format.path(container.wrapperPath), mono: true)
            CDSKeyValue(label: "Wine 引擎", value: info?.engine ?? "待检查")
            CDSKeyValue(label: "图形后端", value: info?.renderer ?? "待检查")

            HStack(spacing: CDSSpacing.tight) {
                Button("显示环境文件", systemImage: "folder") { model.reveal(container.wrapperPath) }
                    .cdsButton(.outline, size: .sm)
                if info != nil && !prepared && container.origin == .managed {
                    Button("准备 Wine 环境") { model.provision(container, installSteam: false) }
                        .cdsButton(.outline, size: .sm)
                        .disabled(!canMaintain)
                }
                Menu("维护操作") {
                    if model.canCustomize(container) {
                        Button("恢复原始图形参数…") { model.restoreRuntimeParameters(container) }
                            .disabled(!canMaintain)
                    } else {
                        Button("备份并允许管理图形参数…") { model.authorizeRuntimeParameters(container) }
                            .disabled(!canMaintain)
                    }
                    Divider()
                    if container.origin == .managed {
                        Button("强制结束此环境…", role: .destructive) { model.endManagedRuntime(container) }
                            .disabled(!occupied || model.isWorking || pending != nil)
                    }
                    Button("移除记录，保留文件…", role: .destructive) { model.forgetContainer(container) }
                        .disabled(!canMaintain)
                }
                .fixedSize()
            }
        }
    }

    private var disks: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.snug) {
            ForEach(libraries) { library in
                VStack(alignment: .leading, spacing: 3) {
                    CDSKeyValue(label: "\(library.drive): · Steam 库", value: "\(library.registeredCount) 个登记条目")
                    Text(library.windowsPath).cdsType(11, mono: true).textSelection(.enabled)
                    if let path = library.unixPath {
                        Text(Format.path(path)).cdsType(10.5, mono: true).foregroundStyle(CDSColor.textSecondary)
                            .textSelection(.enabled)
                    }
                    if model.conflictingLibraries.contains(library.id) {
                        Label("与原生 Steam 共用此目录", systemImage: "exclamationmark.triangle").foregroundStyle(CDSColor.fault)
                    }
                    if !library.isOnline {
                        Label("磁盘离线或目录不可读", systemImage: "externaldrive").foregroundStyle(CDSColor.warning)
                    }
                }
                CDSHairline()
            }
            if bindings.isEmpty {
                Text("此环境没有保存的外置盘绑定。").foregroundStyle(CDSColor.textSecondary)
            }
            ForEach(bindings) { binding in
                HStack(spacing: CDSSpacing.tight) {
                    Label("\(binding.letter): · \(binding.volumeName)", systemImage: "externaldrive")
                    Spacer()
                    if DriveMapper.target(for: binding, volumes: model.volumes) != nil {
                        Button("检查并恢复…") { model.repair(binding) }
                            .cdsButton(.outline, size: .sm).disabled(!canMaintain)
                    } else {
                        Text("未找到绑定目标").foregroundStyle(CDSColor.warning)
                    }
                }
            }
            Button("绑定缺失盘符…", systemImage: "link") { showBinding = true }
                .cdsButton(.outline, size: .sm)
                .disabled(!canMaintain)
        }
    }
}
