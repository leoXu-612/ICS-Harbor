import Foundation

public enum LaunchCheckpoint: String, Codable, CaseIterable, Sendable {
    case files, runtime, steam, game, program, window
    public var title: String {
        switch self { case .files: return "磁盘"; case .runtime: return "环境"; case .steam: return "Steam"; case .game: return "游戏"; case .program: return "程序"; case .window: return "窗口" }
    }
    public var symbol: String {
        switch self { case .files: return "externaldrive"; case .runtime: return "shippingbox"; case .steam: return "network"; case .game: return "gamecontroller"; case .program: return "app"; case .window: return "macwindow" }
    }
}
public enum LaunchOutcome: String, Codable, Sendable { case pending, windowDetected, exited, failed, stopped }
public enum SteamConnection: String, Codable, Sendable {
    case unknown, connecting, online, offline
    public var title: String {
        switch self { case .unknown: return "连接状态待确认"; case .connecting: return "Steam 正在连接"; case .online: return "Steam 已连接"; case .offline: return "Steam 尚未连接" }
    }
}
public struct TransferProgress: Codable, Equatable, Sendable {
    public var completed: Int64
    public var total: Int64
    public var recordedAt: Date
    public var fraction: Double { total > 0 ? min(1, max(0, Double(completed) / Double(total))) : 0 }
    public init(completed: Int64, total: Int64, recordedAt: Date) { self.completed = completed; self.total = total; self.recordedAt = recordedAt }
}
public struct LaunchEvidence: Sendable {
    public var runtimeRunning = false
    public var steamPID: Int32?
    public var steamWindowPID: Int32?
    public var gamePID: Int32?
    public var visibleWindowPIDs: Set<Int32> = []
    public var connection: SteamConnection = .unknown
    public var transfer: TransferProgress?
    public var diskError = false
    public var exitCode: Int?
    public init() {}
}

/// A ledger of observed checkpoints, not a prediction of time remaining.
public struct LaunchProgress: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var containerID: UUID
    public var appID: String?
    public var title: String
    public var startedAt: Date
    public var lastChangeAt: Date
    public var checkedAt: Date?
    public var endedAt: Date?
    public var completed: Set<LaunchCheckpoint> = []
    public var outcome: LaunchOutcome = .pending
    public var connection: SteamConnection = .unknown
    public var targetPID: Int32?
    public var lastProcessSeenAt: Date?
    public var steamPID: Int32?
    public var transfer: TransferProgress?
    public var failure: String?
    public var automaticDisplay: Bool?
    public var warningDelay: TimeInterval?
    public var standalone: Bool?
    public var installer: Bool?
    public var applicationID: UUID?
    public var exitCode: Int?
    public init(id: UUID = UUID(), containerID: UUID, appID: String?, title: String, now: Date = Date()) {
        self.id = id; self.containerID = containerID; self.appID = appID; self.title = title
        startedAt = now; lastChangeAt = now
    }
    public var isStandalone: Bool { standalone == true }
    public var isInstaller: Bool { installer == true }
    public var isSteamClient: Bool { !isStandalone && appID == nil }
    public var checkpoints: [LaunchCheckpoint] { isStandalone ? [.files, .runtime, .program, .window] : appID == nil ? [.files, .runtime, .steam, .window] : [.files, .runtime, .steam, .game, .window] }
    public var completedCount: Int { checkpoints.filter { completed.contains($0) }.count }
    public var fraction: Double { Double(completedCount) / Double(checkpoints.count) }
    public var current: LaunchCheckpoint? { checkpoints.first { !completed.contains($0) } }
    public var isPending: Bool { outcome == .pending }
    public var isObservedRunning: Bool { outcome == .windowDetected }
    public func elapsed(at now: Date) -> TimeInterval { max(0, (endedAt ?? now).timeIntervalSince(startedAt)) }
    public func isTakingLong(at now: Date) -> Bool { isPending && now.timeIntervalSince(lastChangeAt) >= (warningDelay ?? 45) }
    public var heading: String {
        switch outcome {
        case .windowDetected: return isStandalone ? (isInstaller ? "安装器窗口已出现" : "应用窗口已出现") : appID == nil ? "Steam 窗口已出现" : "游戏窗口已出现"
        case .exited: return isInstaller ? (exitCode == 1602 ? "安装已取消" : "安装器已结束") : "进程已退出"
        case .failed: return "启动需要处理"
        case .stopped: return "已停止跟踪"
        case .pending:
            if transfer != nil { return "等待 Steam 完成游戏更新" }
            switch current {
            case .files: return "正在检查磁盘与配置"
            case .runtime: return "正在启动运行环境"
            case .steam: return "正在等待 Steam"
            case .game: return "正在等待游戏进程"
            case .program: return isInstaller ? "正在等待安装器" : "正在等待应用进程"
            case .window, .none: return "正在等待窗口出现"
            }
        }
    }
    public var explanation: String {
        switch outcome {
        case .windowDetected: return isStandalone ? (isInstaller ? "请在安装器中完成安装。许可与登录由本人处理；窗口出现不代表安装成功。" : "观察到应用窗口；具体功能、保存和计算结果仍需实际验证。") : "窗口已交给你。游戏内加载、匹配、帧率与是否能游玩仍以实际画面为准。"
        case .exited:
            if isInstaller { return "安装器退出码：\(exitCode.map(String.init) ?? "未记录")。请检查安装结果，再用“添加已安装 EXE”保存启动入口；Harbor 不会自动重启或删除文件。" }
            return "观察到进程结束。Harbor 没有强制关闭它；若不是手动退出，可查看诊断。"
        case .failed: return failure ?? "请查看任务记录，原文件未被删除。"
        case .stopped: return "只停止观察，不关闭已经启动的 Windows 程序。"
        case .pending:
            if transfer != nil { return "下方百分比来自 Steam 已写出的下载计数，不是启动总进度。" }
            switch current {
            case .files: return "确认磁盘在线、库路径可读，以及预设是否能安全应用。"
            case .runtime: return "首次启动可能需要初始化；不会重复创建原来的容器。"
            case .steam: return "等待这个容器里的 Steam 进程。登录和许可仍由你完成。"
            case .game: return connection == .offline ? "Steam 连接尚未确认。可打开 Steam 检查登录、离线模式或更新提示。" : "Steam 可能在登录、更新或准备游戏。这里只观察，不强制重启。"
            case .program: return "直接运行此环境中的 Windows 程序，不启动 Steam。请留意安装器或系统权限提示。"
            case .window, .none: return "进程已存在，等待可见窗口。窗口被最小化或系统限制检测时，也可能停在这一步。"
            }
        }
    }
    public mutating func checkedFiles(at now: Date) { completed.insert(.files); lastChangeAt = now }
    public mutating func fail(_ reason: String, at now: Date) { outcome = .failed; failure = reason; endedAt = now; lastChangeAt = now }
    public mutating func stop(at now: Date) { outcome = .stopped; endedAt = now; lastChangeAt = now }
    public mutating func observe(_ evidence: LaunchEvidence, at now: Date) {
        guard outcome == .pending || outcome == .windowDetected else { return }
        let oldCompleted = completed, oldConnection = connection, oldTransfer = transfer
        checkedAt = now; connection = isStandalone ? .unknown : evidence.connection; steamPID = isStandalone ? nil : evidence.steamWindowPID ?? evidence.steamPID
        if isStandalone, let code = evidence.exitCode {
            exitCode = code
            if code == 0 || (isInstaller && [1602, 1641, 3010].contains(code)) { outcome = .exited; endedAt = endedAt ?? now; lastChangeAt = now }
            else { fail("Windows 程序退出码 \(code)。请查看程序提示或日志；原文件保留。", at: now) }
            return
        }
        if evidence.runtimeRunning { completed.insert(.runtime) }
        if !isStandalone && evidence.steamPID != nil { completed.insert(.runtime); completed.insert(.steam) }
        let pid = isSteamClient ? (evidence.steamWindowPID ?? evidence.steamPID) : evidence.gamePID
        if let pid {
            completed.insert(.runtime)
            targetPID = pid; lastProcessSeenAt = now
            if isStandalone { completed.insert(.program) } else if appID != nil { completed.insert(.game) }
            transfer = nil
            let visible = isSteamClient ? evidence.steamWindowPID.map { evidence.visibleWindowPIDs.contains($0) } == true : evidence.visibleWindowPIDs.contains(pid)
            if visible {
                completed.insert(.window); outcome = .windowDetected; endedAt = endedAt ?? now
            }
        } else if targetPID != nil, now.timeIntervalSince(lastProcessSeenAt ?? startedAt) >= 6 {
            outcome = .exited; endedAt = endedAt ?? now; lastChangeAt = now; transfer = nil
        } else {
            transfer = evidence.transfer
            if evidence.diskError { fail("Steam 报告磁盘写入失败。请检查外置盘与容器权限，不要先删除游戏或重新下载。", at: now) }
        }
        if completed != oldCompleted || connection != oldConnection || transfer?.completed != oldTransfer?.completed { lastChangeAt = now }
    }
}

public enum SteamSignals {
    private static func formatter() -> DateFormatter {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"; return formatter
    }
    private static func timestamp(_ line: String, formatter: DateFormatter) -> Date? {
        guard line.hasPrefix("["), let end = line.firstIndex(of: "]") else { return nil }
        return formatter.date(from: String(line[line.index(after: line.startIndex)..<end]))
    }
    /// Raw lines can contain credentials. Only the enum leaves this function.
    public static func connection(in text: String, since: Date) -> SteamConnection {
        var state: SteamConnection = .unknown
        let formatter = formatter()
        for part in text.split(whereSeparator: \.isNewline) {
            let line = String(part)
            let lower = line.lowercased()
            guard lower.contains("logonresponse") || lower.contains("logoff") || lower.contains("loggedoff") || lower.contains("disconnected") || lower.contains("connectionclosed") || lower.contains("connectionfailed") || lower.contains("connect()"),
                  let date = timestamp(line, formatter: formatter), date >= since else { continue }
            if lower.contains("logonresponse") {
                if line.range(of: #"\bOK\b"#, options: .regularExpression) != nil { state = .online }
                else if line.range(of: #"LogOnResponse\(\).*'[^']+'"#, options: [.regularExpression, .caseInsensitive]) != nil { state = .offline }
            } else if lower.contains("logoff") || lower.contains("loggedoff") || lower.contains("disconnected") || lower.contains("connectionclosed") || lower.contains("connectionfailed") { state = .offline }
            else if lower.contains("connect()") && state != .online { state = .connecting }
        }
        return state
    }
    public static func hasDiskFailure(in text: String, appID: String, since: Date) -> Bool {
        guard SteamScanner.isAppID(appID) else { return false }
        let formatter = formatter()
        let firstSecond = Date(timeIntervalSince1970: floor(since.timeIntervalSince1970))
        return text.split(whereSeparator: \.isNewline).contains { part in
            let line = String(part)
            guard line.contains("AppID \(appID) "), line.contains("Disk write failure") || line.contains("Install folder not writable"),
                  let date = timestamp(line, formatter: formatter), date >= firstSecond else { return false }
            return true
        }
    }
    public static func transfer(in manifest: String, recordedAt: Date) -> TransferProgress? {
        guard let root = try? VDFParser.parse(manifest), let app = root["AppState"],
              let total = Int64(app["BytesToDownload"]?.string ?? ""), total > 0,
              let done = Int64(app["BytesDownloaded"]?.string ?? ""), done >= 0,
              let flags = Int(app["StateFlags"]?.string ?? ""), flags != 4, done < total else { return nil }
        return TransferProgress(completed: done, total: total, recordedAt: recordedAt)
    }
}
