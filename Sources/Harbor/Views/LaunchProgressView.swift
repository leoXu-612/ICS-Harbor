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
            CDSSurface(level: .two, radius: CDSRadius.xl, padding: compact ? CDSSpacing.base : CDSSpacing.roomy) {
                VStack(alignment: .leading, spacing: CDSSpacing.snug) {
                    header(date: timeline.date, slow: slow)
                    checkpointBlock
                    if let transfer = progress.transfer { transferBlock(transfer) }
                    if slow || !compact || progress.outcome == .failed {
                        Text(slow ? (progress.isStandalone
                                     ? "尚未收到新状态，不等同于程序卡死。请检查安装器或系统权限提示；这里不会强制退出程序。"
                                     : progress.current == .files
                                       ? "磁盘读取或系统授权尚未返回，不等同于程序卡死。若 macOS 弹出磁盘访问确认，请先处理；无需重新下载游戏。"
                                       : "尚未收到新状态，不等同于程序卡死。可以打开 Steam 查看登录或更新提示，也可以继续等待。")
                                 : progress.explanation)
                            .cdsType(10.5)
                            .foregroundStyle(CDSColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    footer(date: timeline.date, slow: slow)
                }
            }
            .animation(CDSMotion.honoring(reducedMotion, CDSMotion.snappy), value: progress.completed)
        }
    }

    // MARK: 头部

    private func header(date: Date, slow: Bool) -> some View {
        HStack(alignment: .top, spacing: CDSSpacing.snug) {
            CDSIconTile(symbol: progress.outcome == .failed ? "exclamationmark.triangle"
                        : progress.isObservedRunning ? "checkmark" : "point.3.connected.trianglepath.dotted",
                        size: 34,
                        tint: tint(slow))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(progress.title).cdsType(13, .semibold).lineLimit(1)
                HStack(spacing: 6) {
                    if progress.isPending && !reducedMotion {
                        ProgressView().controlSize(.mini).tint(tint(slow))
                    }
                    CDSStatusDot(kind: progress.isPending ? .live : progress.outcome == .failed ? .fault : .live, size: 5)
                    Text(slow ? "等待较久 · \(progress.heading)" : progress.heading)
                        .cdsType(10.5)
                        .foregroundStyle(tint(slow))
                }
            }

            Spacer(minLength: 6)

            VStack(alignment: .trailing, spacing: 1) {
                Text(Format.duration(progress.elapsed(at: date)))
                    .cdsType(17, .medium, mono: true)
                    .foregroundStyle(CDSColor.textPrimary)
                Text(progress.isPending ? "已等待" : "本次启动")
                    .cdsType(9.5)
                    .foregroundStyle(CDSColor.textMuted)
            }
            .accessibilityLabel("已等待 \(Int(progress.elapsed(at: date))) 秒")

            if !progress.isPending && compact {
                Button { model.dismissProgress() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CDSColor.textMuted)
                .help("收起启动状态")
            }
        }
    }

    // MARK: 检查点

    private var checkpointBlock: some View {
        VStack(spacing: 7) {
            CDSProgressBar(
                fraction: progress.checkpoints.isEmpty ? 0
                    : Double(progress.completedCount) / Double(progress.checkpoints.count),
                tint: progress.outcome == .failed ? CDSColor.fault : CDSColor.clay
            )
            .accessibilityLabel("启动检查点")
            .accessibilityValue("已确认 \(progress.completedCount) 项，共 \(progress.checkpoints.count) 项；不是耗时百分比")

            HStack(spacing: 3) {
                ForEach(progress.checkpoints, id: \.self) { step in
                    let done = progress.completed.contains(step)
                    HStack(spacing: 3) {
                        Image(systemName: done ? "checkmark" : step.symbol)
                            .font(.system(size: 8, weight: done ? .bold : .regular))
                        Text(step.title)
                            .cdsType(9.5, progress.current == step ? .medium : .regular)
                            .lineLimit(1)
                    }
                    .foregroundStyle(done ? CDSColor.signal
                                     : progress.current == step ? CDSColor.textPrimary : CDSColor.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("\(progress.completedCount)/\(progress.checkpoints.count)")
                    .cdsType(9.5, mono: true)
                    .foregroundStyle(CDSColor.textMuted)
            }
        }
    }

    // MARK: 传输

    private func transferBlock(_ transfer: TransferProgress) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text("Steam 下载记录").cdsType(10).foregroundStyle(CDSColor.textSecondary)
                Spacer()
                Text("\(Format.bytes(transfer.completed)) / \(Format.bytes(transfer.total)) · \(Int(transfer.fraction * 100))%")
                    .cdsType(10, mono: true)
                    .foregroundStyle(CDSColor.textPrimary)
            }
            CDSProgressBar(fraction: transfer.fraction, tint: CDSColor.clay, height: 3)
            Text("记录于 \(transfer.recordedAt.formatted(date: .omitted, time: .standard))；Steam 未写入新计数时，此数值不会变化。")
                .cdsType(9.5)
                .foregroundStyle(CDSColor.textMuted)
        }
        .padding(.top, 2)
    }

    // MARK: 底部

    private func footer(date: Date, slow: Bool) -> some View {
        VStack(alignment: .leading, spacing: CDSSpacing.tight) {
            CDSHairline()
            HStack(spacing: CDSSpacing.snug) {
                if progress.isStandalone {
                    Label("独立 Windows 程序 · 不依赖 Steam", systemImage: "macwindow")
                        .font(.system(size: 10))
                        .foregroundStyle(CDSColor.textMuted)
                } else {
                    Label((progress.isPending || progress.isObservedRunning)
                          ? progress.connection.title
                          : "最后记录：\(progress.connection.title)",
                          systemImage: progress.connection == .online ? "network" : "network.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(progress.connection == .online ? CDSColor.signal : CDSColor.textMuted)
                        .help("仅表示 Steam 登录服务器的日志状态，不是游戏对局连接状态。已结束任务保留最后一次观测结果。")
                }

                Spacer(minLength: 4)

                if progress.targetPID != nil || progress.steamPID != nil {
                    Button(progress.isObservedRunning || progress.isStandalone ? "显示窗口" : "显示 Steam") {
                        model.focusLaunch(progress.id,
                                          preferSteam: !progress.isStandalone && !progress.isObservedRunning)
                    }
                    .cdsButton(.ghost, size: .xs)
                    .disabled(model.launchProgress[progress.id] == nil || progress.outcome == .exited)
                }

                if compact {
                    Button("详情") { model.presentProgress(progress.id) }
                        .cdsButton(.outline, size: .xs)
                }

                if progress.isPending {
                    Button("停止跟踪") { model.stopTracking(progress.id) }
                        .cdsButton(.ghost, size: .xs)
                        .help("只停止观察，不强制关闭 Windows 程序。")
                }
            }

            if !compact {
                HStack {
                    if let checked = progress.checkedAt {
                        Text("\(max(0, Int(date.timeIntervalSince(checked)))) 秒前检查")
                            .cdsType(9.5, mono: true)
                    } else {
                        Text(progress.isPending ? "等待第一次进程检查" : "本次未进入进程检查")
                            .cdsType(9.5)
                    }
                    Spacer()
                    Text("状态条表示检查点，不预测剩余时间")
                        .cdsType(9.5)
                }
                .foregroundStyle(CDSColor.textMuted)
            }
        }
    }

    private func tint(_ slow: Bool) -> Color {
        if progress.outcome == .failed { return CDSColor.fault }
        if slow { return CDSColor.warning }
        if progress.isObservedRunning { return CDSColor.signal }
        return CDSColor.clay
    }
}
