import Foundation
import AppKit
import HarborCore

extension AppModel {
    var currentLaunch: LaunchProgress? {
        if let id = focusedLaunchID, let value = launchProgress[id] { return value }
        return launchProgress.values.filter { $0.isPending && $0.automaticDisplay != false }.sorted { $0.startedAt > $1.startedAt }.first
    }
    var pendingLaunchCount: Int { launchProgress.values.filter(\.isPending).count }
    func pendingLaunch(in containerID: UUID) -> LaunchProgress? {
        launchProgress.values.first { $0.containerID == containerID && $0.isPending }
    }
    func progress(for game: GameRecord) -> LaunchProgress? {
        launchProgress.values.filter { $0.containerID == game.containerID && $0.appID == game.appID }.max { $0.startedAt < $1.startedAt }
    }
    func beginLaunch(container: ContainerRecord, game: GameRecord?) {
        guard !isWorking else { errorMessage = "请等待组件准备任务完成。"; return }
        if let pending = pendingLaunch(in: container.id) {
            focusedLaunchID = pending.id; notice = "这个环境已有启动请求，已显示其进度，没有重复启动。"; return
        }
        var record = ActivityRecord(title: "启动 \(game?.name ?? "Steam")", detail: "正在检查磁盘与配置", state: .requested)
        let preset = game.map { self.preset($0.id) } ?? GamePreset()
        var progress = LaunchProgress(id: record.id, containerID: container.id, appID: game?.appID, title: game?.name ?? "Steam")
        progress.automaticDisplay = preset.showProgress; progress.warningDelay = TimeInterval(preset.waitThreshold.rawValue)
        record.launch = progress; launchProgress[record.id] = progress
        focusedLaunchID = preset.showProgress ? record.id : nil
        let target = LaunchProbeTarget(container: container, game: game, since: progress.startedAt, focusOnWindow: preset.focusOnWindow)
        state.activity.insert(record, at: 0); state.activity = Array(state.activity.prefix(80)); notice = nil; save()
        let backupRoot = AppPaths.backups
        // Feedback is already visible before the first external-disk access.
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    guard FileManager.default.isExecutableFile(atPath: container.launcher), FileManager.default.fileExists(atPath: container.steamExecutable) else { throw HarborError.unavailable("尚未找到启动器或 Steam.exe，请先准备运行环境。") }
                    let libraries = SteamScanner.scan(container).libraries
                    let native = NSHomeDirectory() + "/Library/Application Support/Steam/steamapps/libraryfolders.vdf"
                    if let text = try? String(contentsOfFile: native, encoding: .utf8), !SteamScanner.nativeLibraryConflicts(libraries, nativeVDF: text).isEmpty {
                        throw HarborError.protected("此环境与 Mac 原生 Steam 共用游戏库。请先分开库目录，避免平台文件互相覆盖。")
                    }
                    let busy = ProcessProbe.isBusy(container, entries: ProcessProbe.entries())
                    if let game {
                        try LaunchPolicy.validate(game: game, container: container, preset: preset, busy: busy, linkedAuthorized: RuntimeControl.isAuthorized(container, root: backupRoot))
                        guard let path = game.installDirectory, FileManager.default.isReadableFile(atPath: path) else { throw HarborError.unavailable("游戏目录暂时不可读。请连接原磁盘并确认权限，未触发重新下载。") }
                    }
                    // A cold, client-only launch restores the original baseline.
                    // Showing an already-running Steam must not reset its session.
                    if game != nil || !busy {
                        try LaunchPolicy.apply(preset, container: container, backupRoot: backupRoot, busy: busy)
                    }
                    return nil
                } catch { return error.localizedDescription }
            }.value
            guard self.launchProgress[record.id]?.isPending == true else { return }
            if let error = result { self.failLaunch(record.id, reason: error); return }
            self.launchProgress[record.id]?.checkedFiles(at: Date())
            self.launchTargets[record.id] = target
            self.saveLaunchSnapshot(record.id)
            let existing = await Task.detached(priority: .utility) { LaunchProbe.sample([record.id: target]) }.value
            guard self.launchProgress[record.id]?.isPending == true else { return }
            if let evidence = existing[record.id] { self.launchProgress[record.id]?.observe(evidence, at: Date()) }
            self.saveLaunchSnapshot(record.id)
            if self.launchProgress[record.id]?.outcome == .windowDetected || (game != nil && existing[record.id]?.gamePID != nil) {
                self.focusLaunch(record.id); return
            }
            self.dispatchLaunch(container: container, game: game, activityID: record.id, runtimeEnvironment: preset.runtimeEnvironment)
        }
    }
    func pollLaunches(includeIdleContainers: Bool = false) async {
        guard !isPollingLaunches else { return }; isPollingLaunches = true
        var targets = launchTargets
        if includeIdleContainers {
            for container in state.containers { targets[container.id] = LaunchProbeTarget(container: container, game: nil, since: Date()) }
        }
        guard !targets.isEmpty else { isPollingLaunches = false; return }
        let capturedTargets = targets
        let sampled = await Task.detached(priority: .utility) { LaunchProbe.sample(capturedTargets) }.value
        let now = Date()
        for (id, evidence) in sampled {
            if let target = targets[id] { containerSignals[target.container.id] = evidence }
            guard var progress = launchProgress[id], launchTargets[id] != nil else { continue }
            let old = progress
            progress.observe(evidence, at: now); launchProgress[id] = progress
            if old.isPending && progress.isObservedRunning && targets[id]?.focusOnWindow == true { focusLaunch(id) }
            if old.completed != progress.completed || old.outcome != progress.outcome || old.connection != progress.connection || old.targetPID != progress.targetPID || old.steamPID != progress.steamPID || old.transfer?.completed != progress.transfer?.completed { saveLaunchSnapshot(id) }
            if !progress.isPending && !progress.isObservedRunning { launchTargets.removeValue(forKey: id) }
        }
        isPollingLaunches = false
    }
    func saveLaunchSnapshot(_ id: UUID) {
        guard let value = launchProgress[id], let index = state.activity.firstIndex(where: { $0.id == id }) else { return }
        state.activity[index].launch = value
        state.activity[index].detail = value.heading + "。" + value.explanation
        state.activity[index].state = value.outcome == .failed ? .failed : value.outcome == .windowDetected || (value.isStandalone && value.outcome == .exited) ? .succeeded : .requested
        save()
    }
    func failLaunch(_ id: UUID, reason: String) {
        launchProgress[id]?.fail(reason, at: Date()); launchTargets.removeValue(forKey: id)
        saveLaunchSnapshot(id)
    }
    func stopTracking(_ id: UUID) {
        launchProgress[id]?.stop(at: Date()); launchTargets.removeValue(forKey: id)
        saveLaunchSnapshot(id)
    }
    func focusLaunch(_ id: UUID, preferSteam: Bool = false) {
        guard let progress = launchProgress[id], let container = container(progress.containerID) else { return }
        if let pid = preferSteam ? progress.steamPID : (progress.targetPID ?? progress.steamPID), LaunchProbe.owns(pid, container: container), let app = NSRunningApplication(processIdentifier: pid) {
            _ = app.activate(options: [.activateAllWindows])
        } else { notice = "还没有观察到对应窗口。请查看启动阶段或 Steam 的提示。" }
    }
    func presentProgress(_ id: UUID) { focusedLaunchID = id; section = .activity }
    func dismissProgress() { focusedLaunchID = nil }
}
