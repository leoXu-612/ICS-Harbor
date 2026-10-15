import SwiftUI
import HarborCore

struct ActivityView: View {
    @Bindable var model: AppModel
    @State private var expanded: UUID?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    PageHeading(title: "启动与任务", subtitle: "查看正在等待的步骤，以及已经确认的结果。")
                    Spacer()
                    Button("导出诊断", systemImage: "square.and.arrow.up") { model.exportDiagnostics() }
                }
                if model.state.activity.isEmpty {
                    Surface { EmptyState(symbol: "checklist", title: "没有进行中的任务", message: "启动 Steam、游戏或创建环境后，进度会出现在这里。") }
                }
                ForEach(model.state.activity) { task in
                    if let progress = model.launchProgress[task.id] ?? task.launch {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(task.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                            LaunchProgressView(model: model, progress: progress)
                        }
                    } else {
                        Surface {
                            VStack(alignment: .leading, spacing: 13) {
                                HStack(spacing: 11) {
                                    Image(systemName: symbol(task.state)).font(.title3).foregroundStyle(color(task.state))
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(task.title).font(.callout.weight(.semibold))
                                        Text(task.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Pill(title: title(task.state), color: color(task.state))
                                }
                                Text(task.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                                if task.state == .running {
                                    if let progress = model.taskProgress { ProgressView(value: progress) } else { ProgressView() }
                                    Text(model.activeStage).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                }
                                if !task.log.isEmpty {
                                    DisclosureGroup("本地日志", isExpanded: Binding(get: { expanded == task.id }, set: { expanded = $0 ? task.id : nil })) {
                                        ScrollView([.horizontal, .vertical]) {
                                            Text(task.log).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                                        }.frame(height: 180).background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8)).padding(.top, 6)
                                    }.font(.caption)
                                }
                            }
                        }
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield").foregroundStyle(.secondary)
                    Text("状态来自本机的进程、窗口元数据和 Steam 白名单日志事件；不保存连接日志中的账号或票据。窗口出现不代表联机对局已通过。").font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }.padding(24)
        }
    }
    private func symbol(_ state: TaskState) -> String { switch state { case .running: return "arrow.down.circle"; case .succeeded: return "checkmark.circle"; case .failed: return "exclamationmark.triangle"; case .requested: return "paperplane" } }
    private func color(_ state: TaskState) -> Color { switch state { case .running, .requested: return .harbor; case .succeeded: return .harborSignal; case .failed: return .orange } }
    private func title(_ state: TaskState) -> String { switch state { case .running: return "执行中"; case .succeeded: return "动作完成"; case .failed: return "需处理"; case .requested: return "已发送请求" } }
}
