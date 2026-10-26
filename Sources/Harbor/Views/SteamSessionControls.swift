import SwiftUI
import HarborCore

/// Client lifecycle belongs to the environment, not to each game inspector.
struct SteamSessionControls: View {
    @Bindable var model: AppModel
    let container: ContainerRecord
    private var runtime: RuntimeInfo? { model.runtime[container.id] }
    private var signal: LaunchEvidence? { model.containerSignals[container.id] }
    private var running: Bool { signal?.steamPID != nil }
    private var pending: LaunchProgress? { model.pendingLaunch(in: container.id) }
    private var status: String {
        guard let runtime else { return "正在检查" }
        if !runtime.hasSteam { return "未检测到 Steam" }
        if pending?.isSteamClient == true { return "正在启动" }
        guard signal != nil else { return "状态待确认" }
        return running ? signal?.connection.title ?? "状态待确认" : "未运行"
    }
    private var launchTitle: String {
        guard let runtime else { return "检查 Steam…" }
        if pending?.isSteamClient == true { return "正在启动…" }
        if running { return "显示 Steam" }
        if runtime.hasSteam { return "启动 Steam" }
        return container.origin == .managed ? "准备 Steam" : "未安装 Steam"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Label("Steam", systemImage: "app").font(.system(size: 19, weight: .semibold))
                Text("客户端").font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Text(status).font(.caption).foregroundStyle(running && signal?.connection == .online ? Color.harborSignal : .secondary)
            }
            HStack(spacing: 10) {
                Button { model.openSteam(container) } label: {
                    Label(launchTitle, systemImage: running ? "macwindow" : pending != nil ? "hourglass" : "play.fill")
                }.buttonStyle(.borderedProminent).tint(.harborAction)
                    .disabled(runtime == nil || model.isWorking || pending != nil || (model.hasLibraryConflict(container) && !running) || (runtime?.hasSteam == false && container.origin == .linked))
                Button("正常退出 Steam", systemImage: "power") { model.requestStop(container) }
                    .disabled(!running || model.isWorking || pending != nil)
            }.controlSize(.large)
            Text(running ? "先保存并退出游戏，再正常退出 Steam。关闭 Harbor 不会停止这个环境。" : "安装新游戏、处理登录或更新提示，都从这里打开 Steam；已有游戏可从游戏库直接启动。")
                .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
