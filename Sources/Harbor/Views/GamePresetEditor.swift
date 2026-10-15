import SwiftUI
import HarborCore

struct GamePresetEditor: View {
    @Bindable var model: AppModel
    let game: GameRecord
    @Environment(\.dismiss) private var dismiss
    @State private var draft = GamePreset()
    @State private var capabilities: DXMTCapabilities?
    private var container: ContainerRecord? { model.container(game.containerID) }
    private var allowed: Bool { container.map { model.canCustomize($0) } ?? false }
    private var effectiveRenderer: String {
        if draft.renderer != .inherit { return draft.renderer == .dxmt ? "DXMT" : "DXVK" }
        return container.map { model.originalRenderer($0) } ?? "待确认"
    }
    private var validation: String? {
        guard draft.hasDXMTOverrides else { return nil }
        guard let capabilities else { return "正在检查本地 DXMT 是否支持这些参数…" }
        do { try capabilities.validate(draft, renderer: effectiveRenderer); return nil }
        catch { return error.localizedDescription }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("游戏参数").font(.title2.weight(.semibold))
                    Text(game.name).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                if draft != model.preset(game.id) { Text("未保存").font(.caption).foregroundStyle(.orange) }
            }.padding(22)
            Form {
                Section("生效范围") {
                    Text("按游戏保存，运行时参数应用到整个 Wine 会话。Steam 及其他 Windows 程序须先正常退出；保存预设本身不改运行中的环境。")
                        .font(.callout).foregroundStyle(.secondary)
                    if let container, !allowed {
                        Label("关联环境尚未授权参数管理", systemImage: "lock.shield").font(.callout.weight(.medium))
                        Button("备份并允许管理此环境…") { model.authorizeRuntimeParameters(container) }
                        Text("只备份和管理有限图形参数，不改变关联身份，不动存档、键位或插件。下面的启动行为无需这项授权。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Label("原始参数可恢复 · 修改前另存备份", systemImage: "checkmark.shield").font(.caption).foregroundStyle(Color.harborSignal)
                    }
                }
                Section("显示与性能") {
                    Picker("图形后端", selection: $draft.renderer) {
                        ForEach(Renderer.allCases) { Text($0.title).tag($0) }
                    }.disabled(!allowed)
                    LabeledContent("有效后端", value: effectiveRenderer)
                    Picker("DXMT 帧率上限", selection: $draft.frameLimit) {
                        ForEach(FrameLimit.allCases) { Text($0.title).tag($0) }
                    }.disabled(!allowed || effectiveRenderer != "DXMT" || capabilities?.frameLimit != true)
                    Picker("DXMT 强制 SDR", selection: $draft.forceSDR) {
                        ForEach(ParameterOverride.allCases) { Text($0.title).tag($0) }
                    }.disabled(!allowed || effectiveRenderer != "DXMT" || capabilities?.forceSDR != true)
                    Text("限帧不是保证帧率，实际节奏受显示器刷新率影响。强制 SDR 用于排查 HDR 异常；关闭它不代表启用 HDR。分辨率、画质及窗口模式请在游戏内设置。")
                        .font(.caption).foregroundStyle(.secondary)
                    if let validation {
                        Text(validation).font(.caption).foregroundStyle(.orange)
                        Button("清除 DXMT 专用参数") { draft.resetDXMT() }.controlSize(.small)
                    }
                }
                Section("同步与兼容性") {
                    Picker("同步方式", selection: $draft.sync) {
                        ForEach(SyncMode.allCases) { Text($0.title).tag($0) }
                    }.disabled(!allowed)
                    Text("M-Sync 与 E-Sync 分别控制 Wine 的同步路径，不是垂直同步。原双开方式保留用于兼容旧预设；性能与稳定性需逐游戏验证。")
                        .font(.caption).foregroundStyle(.secondary)
                    Picker("DXMT 全屏切换处理", selection: $draft.handleAltTab) {
                        ForEach(ParameterOverride.allCases) { Text($0.title).tag($0) }
                    }.disabled(!allowed || effectiveRenderer != "DXMT" || capabilities?.handleAltTab != true)
                    Text("让 DXMT 处理独占全屏下的 Alt/Cmd + Tab。游戏自行处理时通常保持继承。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("诊断") {
                    Picker("Metal 性能浮层", selection: $draft.hud) {
                        ForEach(ParameterOverride.allCases) { Text($0.title).tag($0) }
                    }.disabled(!allowed)
                    Picker("Wine 日志等级", selection: $draft.logging) {
                        ForEach(WineLogLevel.allCases) { Text($0.title).tag($0) }
                    }.disabled(!allowed)
                    Text("性能浮层的显示取决于后端与系统。错误与警告日志仅用于排查，可能增大本地日志；不会自动上传。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("启动行为 · 只影响 Harbor") {
                    Toggle("自动展示启动进度", isOn: $draft.showProgress)
                    Toggle("窗口出现后尝试切到前台", isOn: $draft.focusOnWindow)
                    Picker("等待提醒", selection: $draft.waitThreshold) {
                        ForEach(LaunchWaitThreshold.allCases) { Text($0.title).tag($0) }
                    }
                    Text("提醒不会强制关闭程序。置前请求由 macOS / Wine 决定；关闭自动进度后，仍可在“启动与任务”查看。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            Divider()
            HStack {
                Button("恢复默认") { draft = GamePreset() }
                Button("载入上次保存") { if let previous = model.state.previousPresets[game.id] { draft = previous } }
                    .disabled(model.state.previousPresets[game.id] == nil)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存预设") { if model.savePreset(draft, for: game) { dismiss() } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                    .disabled(draft == model.preset(game.id) || validation != nil || (!allowed && draft.modifiesRuntime))
            }.padding(18)
        }.frame(width: 660, height: 720)
            .onAppear { draft = model.preset(game.id) }
            .task {
                guard let container else { return }
                capabilities = await Task.detached(priority: .utility) { DXMTCapabilities.read(container) }.value
            }
    }
}
