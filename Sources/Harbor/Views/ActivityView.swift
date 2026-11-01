import SwiftUI
import HarborCore

struct ActivityView: View {
    @Bindable var model: AppModel
    @State private var expanded: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CDSSpacing.roomy) {
                CDSPageHeader(title: "启动记录",
                              subtitle: "先看当前在等哪一步，再决定继续等待还是检查环境。") {
                    Button("导出诊断", systemImage: "square.and.arrow.up") { model.exportDiagnostics() }
                        .cdsButton(.outline, size: .sm)
                }

                if model.state.activity.isEmpty {
                    CDSSurface(padding: CDSSpacing.section) {
                        CDSIntro(symbol: "checklist",
                                 title: "没有进行中的任务",
                                 message: "启动 Steam、游戏或创建环境后，进度会出现在这里。")
                    }
                }

                VStack(spacing: CDSSpacing.snug) {
                    ForEach(model.state.activity) { task in
                        taskRow(task)
                    }
                }

                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "lock.shield").font(.system(size: 10)).padding(.top, 1)
                    Text("状态来自本机的进程、窗口元数据和 Steam 白名单日志事件；不保存连接日志中的账号或票据。窗口出现不代表联机对局已通过。")
                        .cdsType(10.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(CDSColor.textMuted)
                .padding(.top, 2)
            }
            .padding(CDSSpacing.page)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CDSColor.surface1)
    }

    @ViewBuilder
    private func taskRow(_ task: ActivityRecord) -> some View {
        if let progress = model.launchProgress[task.id] ?? task.launch {
            VStack(alignment: .leading, spacing: 6) {
                Text(task.createdAt.formatted(date: .abbreviated, time: .shortened))
                    .cdsType(10, mono: true)
                    .foregroundStyle(CDSColor.textMuted)
                LaunchProgressView(model: model, progress: progress)
            }
        } else {
            CDSSurface(level: .two, radius: CDSRadius.xl, padding: CDSSpacing.base) {
                VStack(alignment: .leading, spacing: CDSSpacing.snug) {
                    HStack(spacing: CDSSpacing.snug) {
                        CDSIconTile(symbol: symbol(task.state), size: 32, tint: color(task.state))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).cdsType(12.5, .semibold)
                            Text(task.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .cdsType(10, mono: true)
                                .foregroundStyle(CDSColor.textMuted)
                        }
                        Spacer(minLength: CDSSpacing.tight)
                        HStack(spacing: 5) {
                            CDSStatusDot(kind: dot(task.state), size: 5)
                            Text(title(task.state)).cdsType(10.5)
                        }
                        .foregroundStyle(color(task.state))
                    }

                    Text(task.detail)
                        .cdsType(11)
                        .foregroundStyle(CDSColor.textSecondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    if task.state == .running {
                        if let progress = model.taskProgress {
                            CDSProgressBar(fraction: progress)
                        } else {
                            ProgressView().controlSize(.small).tint(CDSColor.clay)
                        }
                        Text(model.activeStage)
                            .cdsType(10.5)
                            .foregroundStyle(CDSColor.textMuted)
                            .lineLimit(2)
                    }

                    if !task.log.isEmpty {
                        DisclosureGroup("本地日志",
                                        isExpanded: Binding(get: { expanded == task.id },
                                                            set: { expanded = $0 ? task.id : nil })) {
                            ScrollView([.horizontal, .vertical]) {
                                Text(task.log)
                                    .cdsType(9.5, mono: true)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                            }
                            .frame(height: 170)
                            .background(CDSColor.surface3,
                                        in: RoundedRectangle(cornerRadius: CDSRadius.lg, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: CDSRadius.lg, style: .continuous)
                                    .strokeBorder(CDSColor.border, lineWidth: 1)
                            }
                            .padding(.top, 4)
                        }
                        .font(.system(size: 11))
                    }
                }
            }
        }
    }

    private func symbol(_ state: TaskState) -> String {
        switch state {
        case .running: "arrow.down.circle"
        case .succeeded: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .requested: "paperplane"
        }
    }

    private func color(_ state: TaskState) -> Color {
        switch state {
        case .running, .requested: CDSColor.clay
        case .succeeded: CDSColor.signal
        case .failed: CDSColor.warning
        }
    }

    private func dot(_ state: TaskState) -> CDSStatusDot.Kind {
        switch state {
        case .running, .succeeded: .live
        case .requested: .attention
        case .failed: .fault
        }
    }

    private func title(_ state: TaskState) -> String {
        switch state {
        case .running: "执行中"
        case .succeeded: "动作完成"
        case .failed: "需处理"
        case .requested: "已发送请求"
        }
    }
}
