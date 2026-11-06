import SwiftUI
import HarborCore

/// A Steam session belongs to exactly one Wine environment.
struct SteamSessionControls: View {
    let model: AppModel
    let container: ContainerRecord
    @State private var expanded = false

    private var runtime: RuntimeInfo? { model.runtime[container.id] }
    private var signal: LaunchEvidence? { model.containerSignals[container.id] }
    private var running: Bool { signal?.steamPID != nil }
    private var pending: LaunchProgress? { model.pendingLaunch(in: container.id) }
    private var conflict: Bool { model.hasLibraryConflict(container) }
    private var missing: Bool { runtime?.hasSteam == false }
    private var occupied: Bool { model.busy.contains(container.id) || signal?.runtimeRunning == true || running }
    private var status: String {
        if conflict { return "游戏库冲突" }
        if pending?.isSteamClient == true { return "启动请求处理中" }
        if running { return signal?.connection.title ?? "连接状态待确认" }
        guard runtime != nil else { return "等待检查" }
        if missing { return "未检测到 Steam" }
        return signal == nil ? "会话待确认" : "未检测到客户端进程"
    }

    var body: some View {
        CDSSurface(level: .two, padding: CDSSpacing.base) {
            DisclosureGroup(isExpanded: $expanded) {
                VStack(alignment: .leading, spacing: CDSSpacing.snug) {
                    if conflict { LibraryConflictNotice() }
                    if let pending {
                        Label("正在处理：\(pending.title)", systemImage: "hourglass")
                            .foregroundStyle(CDSColor.warning)
                    }
                    if missing && container.origin == .linked {
                        Text("请先在原环境中完成 Steam 安装。Harbor 不会重建关联环境。")
                    } else if missing {
                        Text("准备操作会在此环境中运行 Steam 安装器。请先退出该环境中的程序。")
                    } else {
                        Text("安装游戏、处理登录或更新请打开此客户端。请求退出前，请先保存并退出游戏。")
                    }
                    HStack(spacing: CDSSpacing.tight) {
                        if missing {
                            if container.origin == .managed {
                                Button("准备 Steam", systemImage: "shippingbox") {
                                    model.provision(container, installSteam: true)
                                }
                                .cdsButton(.primary, size: .sm)
                                .disabled(occupied || pending != nil || model.isWorking || conflict)
                            }
                        } else {
                            Button(running ? "显示 Steam" : "启动 Steam", systemImage: running ? "macwindow" : "play.fill") {
                                model.openSteam(container)
                            }
                            .cdsButton(.primary, size: .sm)
                            .disabled(runtime == nil || model.isWorking || pending != nil || conflict)
                        }
                        if !missing || running {
                            Button("正常退出 Steam…", systemImage: "power") { model.requestStop(container) }
                                .cdsButton(.outline, size: .sm)
                                .disabled(!running || model.isWorking || pending != nil)
                        }
                    }
                }
                .cdsType(11.5)
                .foregroundStyle(CDSColor.textSecondary)
                .padding(.top, CDSSpacing.snug)
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                HStack(spacing: CDSSpacing.tight) {
                    Image(systemName: "square.3.layers.3d").foregroundStyle(CDSColor.textSecondary)
                    Text(container.name).cdsType(13, .semibold)
                    Spacer(minLength: CDSSpacing.tight)
                    CDSStatusDot(kind: conflict ? .fault : running ? .live : .idle, size: 5)
                    Text(status).cdsType(11).foregroundStyle(CDSColor.textSecondary)
                }
            }
        }
    }
}
