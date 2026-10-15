import SwiftUI
import HarborCore

struct LaunchProgressView: View {
    @Bindable var model: AppModel
    var progress: LaunchProgress
    var compact = false
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: progress.isPending ? 1 : 12)) { timeline in
            let slow = progress.isTakingLong(at: timeline.date)
            Surface(padding: compact ? 16 : 20) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 11).fill(tint(slow).opacity(0.11)).frame(width: 40, height: 40)
                            Image(systemName: progress.outcome == .failed ? "exclamationmark.triangle" : progress.isObservedRunning ? "checkmark" : "point.3.connected.trianglepath.dotted")
                                .font(.system(size: 18, weight: .medium)).foregroundStyle(tint(slow))
                        }.accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(progress.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            HStack(spacing: 7) {
                                if progress.isPending && !reducedMotion { ProgressView().controlSize(.mini) }
                                Text(slow ? "等待较久 · \(progress.heading)" : progress.heading).font(.callout).foregroundStyle(tint(slow))
                            }
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 4) {
                            Text(Format.duration(progress.elapsed(at: timeline.date))).font(.system(size: 18, weight: .medium, design: .rounded)).monospacedDigit()
                            Text(progress.isPending ? "已等待" : "本次启动").font(.caption2).foregroundStyle(.secondary)
                        }.accessibilityLabel("已等待 \(Int(progress.elapsed(at: timeline.date))) 秒")
                        if !progress.isPending && compact {
                            Button { model.dismissProgress() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help("收起启动状态")
                        }
                    }
                    VStack(spacing: 8) {
                        ProgressView(value: Double(progress.completedCount), total: Double(progress.checkpoints.count))
                            .tint(tint(slow))
                            .accessibilityLabel("启动检查点")
                            .accessibilityValue("已确认 \(progress.completedCount) 项，共 \(progress.checkpoints.count) 项；不是耗时百分比")
                        HStack(spacing: 2) {
                            ForEach(progress.checkpoints, id: \.self) { step in
                                Label(step.title, systemImage: progress.completed.contains(step) ? "checkmark.circle.fill" : step.symbol)
                                    .font(.system(size: 10, weight: progress.current == step ? .semibold : .regular))
                                    .foregroundStyle(progress.completed.contains(step) ? Color.harborSignal : progress.current == step ? tint(slow) : .secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Text("\(progress.completedCount)/\(progress.checkpoints.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    if let transfer = progress.transfer {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Steam 下载记录").font(.caption)
                                Spacer()
                                Text("\(Format.bytes(transfer.completed)) / \(Format.bytes(transfer.total)) · \(Int(transfer.fraction * 100))%").font(.caption.monospacedDigit())
                            }
                            ProgressView(value: transfer.fraction).tint(.harbor)
                            Text("记录于 \(transfer.recordedAt.formatted(date: .omitted, time: .standard))；Steam 未写入新计数时，此数值不会变化。").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if slow || !compact || progress.outcome == .failed {
                        Text(slow ? (progress.isStandalone ? "尚未收到新状态，不等同于程序卡死。请检查安装器或系统权限提示；这里不会强制退出程序。" : progress.current == .files ? "磁盘读取或系统授权尚未返回，不等同于程序卡死。若 macOS 弹出磁盘访问确认，请先处理；无需重新下载游戏。" : "尚未收到新状态，不等同于程序卡死。可以打开 Steam 查看登录或更新提示，也可以继续等待。") : progress.explanation)
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: 12) {
                        if progress.isStandalone {
                            Label("独立 Windows 程序 · 不依赖 Steam", systemImage: "app").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Label((progress.isPending || progress.isObservedRunning) ? progress.connection.title : "最后记录：\(progress.connection.title)", systemImage: progress.connection == .online ? "network" : "network.slash")
                            .font(.caption).foregroundStyle(progress.connection == .online ? Color.harborSignal : .secondary)
                            .help("仅表示 Steam 登录服务器的日志状态，不是游戏对局连接状态。已结束任务保留最后一次观测结果。")
                        }
                        Spacer(minLength: 4)
                        if progress.targetPID != nil || progress.steamPID != nil {
                            Button(progress.isObservedRunning || progress.isStandalone ? "显示窗口" : "显示 Steam") { model.focusLaunch(progress.id, preferSteam: !progress.isStandalone && !progress.isObservedRunning) }.controlSize(.small).disabled(model.launchProgress[progress.id] == nil || progress.outcome == .exited)
                        }
                        if compact { Button("详情") { model.presentProgress(progress.id) }.controlSize(.small) }
                        if progress.isPending {
                            Button("停止跟踪") { model.stopTracking(progress.id) }.buttonStyle(.link).font(.caption)
                                .help("只停止观察，不强制关闭 Windows 程序。")
                        }
                    }
                    if !compact {
                        HStack {
                            if let date = progress.checkedAt {
                                Text("\(max(0, Int(timeline.date.timeIntervalSince(date)))) 秒前检查").monospacedDigit()
                            } else { Text(progress.isPending ? "等待第一次进程检查" : "本次未进入进程检查") }
                            Spacer()
                            Text("状态条表示检查点，不预测剩余时间")
                        }.font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
            .animation(reducedMotion ? nil : .spring(response: 0.3, dampingFraction: 1), value: progress.completed)
        }
    }
    private func tint(_ slow: Bool) -> Color {
        if progress.outcome == .failed { return .harborFault }
        if slow { return .harborWarning }
        if progress.isObservedRunning { return .harborSignal }
        return .harbor
    }
}
