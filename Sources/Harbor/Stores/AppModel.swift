import SwiftUI
import AppKit
import HarborCore
import OSLog
import Observation

enum AppSection: String, CaseIterable, Identifiable {
    case library, applications, containers, presets, activity
    var id: String { rawValue }
    var title: String { switch self { case .library: return "游戏库"; case .applications: return "Windows 应用"; case .containers: return "运行环境"; case .presets: return "游戏预设"; case .activity: return "启动与任务" } }
    var symbol: String { switch self { case .library: return "square.grid.2x2"; case .applications: return "app.badge"; case .containers: return "externaldrive"; case .presets: return "slider.horizontal.3"; case .activity: return "waveform.path.ecg" } }
}

@MainActor @Observable final class AppModel {
    var state = AppState()
    var games: [GameRecord] = []
    var libraries: [LibraryRecord] = []
    var volumes: [MountedVolume] = []
    var runtime: [UUID: RuntimeInfo] = [:]
    var runtimeAuthorized: Set<UUID> = []
    var busy: Set<UUID> = []
    var warnings: [String] = []
    var conflictingLibraries: Set<String> = []
    var errorMessage: String?
    var notice: String?
    var section: AppSection = .library
    var search = ""
    var favoritesOnly = false
    var selectedGameID: String?
    var showCreate = false
    var showBind = false
    var showAddApplication = false
    var showInstallApplication = false
    var selectedApplicationID: UUID?
    var editingApplication: WindowsApplication?
    var isRefreshing = false
    var activeTaskID: UUID?
    var activeStage = ""
    var taskProgress: Double?
    var launchProgress: [UUID: LaunchProgress] = [:]
    var containerSignals: [UUID: LaunchEvidence] = [:]
    var focusedLaunchID: UUID?
    var lastRefreshedAt: Date?
    @ObservationIgnored private let store = StateStore(root: AppPaths.root)
    @ObservationIgnored private var canPersist = true
    @ObservationIgnored private var activeProcess: Process?
    @ObservationIgnored private var requestProcesses: [UUID: Process] = [:]
    @ObservationIgnored var launchTargets: [UUID: LaunchProbeTarget] = [:]
    @ObservationIgnored var isPollingLaunches = false
    @ObservationIgnored private var launchTimer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var refreshTimer: Timer?
    @ObservationIgnored private let logger = Logger(subsystem: "local.harbor.desktop", category: "workflow")

    init() {
        let firstRun = !FileManager.default.fileExists(atPath: store.stateURL.path)
        do { state = try store.load() }
        catch { canPersist = false; errorMessage = "Harbor 配置无法读取，原文件未覆盖。\n\(error.localizedDescription)" }
        if !state.containers.isEmpty && state.containers.allSatisfy({ !$0.preparesSteam }) { section = .applications }
        if canPersist {
            for index in state.activity.indices where state.activity[index].state == .running {
                state.activity[index].state = .failed
                state.activity[index].detail = "上次会话未记录任务结束。已下载文件保留，请检查后重试；不会自动重建容器。"
            }
            for index in state.activity.indices where state.activity[index].launch?.isPending == true {
                state.activity[index].launch?.stop(at: Date())
                state.activity[index].detail = "Harbor 上次会话已结束，旧启动请求未自动重发。"
            }
            if firstRun { state.containers.append(contentsOf: ContainerDiscovery.discover()) }
            save()
        }
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in await self?.volumeChanged() }
            })
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 12, repeats: true) { [weak self] _ in Task { @MainActor in await self?.refresh() } }
        launchTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.launchProgress.values.contains(where: \.isPending) else { return }
                await self.pollLaunches()
            }
        }
        Task { await refresh() }
    }

    var selectedGame: GameRecord? { games.first { $0.id == selectedGameID } }
    var filteredGames: [GameRecord] {
        games.filter { (!favoritesOnly || state.favorites.contains($0.id)) && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.appID.contains(search)) }
            .sorted {
                let a = state.favorites.contains($0.id), b = state.favorites.contains($1.id)
                return a != b ? a : $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }
    var readyCount: Int { games.filter { $0.availability == .ready }.count }
    var offlineCount: Int { games.filter { $0.availability == .offline }.count }
    var isWorking: Bool { activeTaskID != nil }
    func container(_ id: UUID) -> ContainerRecord? { state.containers.first { $0.id == id } }
    func preset(_ id: String) -> GamePreset { state.presets[id] ?? .init() }

    @discardableResult func save() -> Bool {
        guard canPersist else { return false }
        do { try store.save(state); return true } catch { errorMessage = "无法保存 Harbor 配置：\(error.localizedDescription)"; return false }
    }
    func refresh() async {
        guard !isRefreshing else { return }; isRefreshing = true
        let containers = state.containers
        let backupRoot = AppPaths.backups
        // Do not let a volume-permission dialog hide the independently readable
        // runtime and process status behind a pending library scan.
        let status = await Task.detached(priority: .utility) {
            (containers.map { ($0.id, RuntimeInfo.read($0)) }, ProcessProbe.entries(), containers.filter { RuntimeControl.isAuthorized($0, root: backupRoot) }.map(\.id))
        }.value
        runtime = Dictionary(uniqueKeysWithValues: status.0)
        runtimeAuthorized = Set(status.2)
        busy = Set(containers.filter { ProcessProbe.isBusy($0, entries: status.1) }.map(\.id))
        await pollLaunches(includeIdleContainers: true)
        let steamContainers = containers.filter { $0.preparesSteam || runtime[$0.id]?.hasSteam == true }
        let result = await Task.detached(priority: .utility) {
            (steamContainers.map { SteamScanner.scan($0) }, VolumeScanner.mounted())
        }.value
        games = result.0.flatMap(\.games); libraries = result.0.flatMap(\.libraries)
        warnings = result.0.flatMap(\.warnings)
        conflictingLibraries = detectConflicts(libraries)
        if !conflictingLibraries.isEmpty { warnings.append("检测到原生 Mac Steam 与 Wine 登记了同一游戏库。相关启动已阻止，请先分开库目录；不会自动删除或移动文件。") }
        volumes = result.1
        lastRefreshedAt = Date(); isRefreshing = false
    }
    private func volumeChanged() async {
        let before = offlineCount
        await refresh()
        guard offlineCount != before else { return }
        notice = offlineCount > before ? "有游戏磁盘离线，未触发重新下载。连接后可再次刷新。" : "磁盘已重新连接，游戏库记录已刷新。"
    }
    func toggleFavorite(_ game: GameRecord) { if state.favorites.contains(game.id) { state.favorites.remove(game.id) } else { state.favorites.insert(game.id) }; save() }
    func canCustomize(_ container: ContainerRecord) -> Bool { container.origin == .managed || runtimeAuthorized.contains(container.id) }
    func originalRenderer(_ container: ContainerRecord) -> String {
        if let baseline = try? RuntimeControl.baseline(container, root: AppPaths.backups) { return RuntimeControl.rendererName(baseline) }
        return runtime[container.id]?.renderer ?? "待确认"
    }
    func authorizeRuntimeParameters(_ container: ContainerRecord) {
        guard Panels.confirm(title: "允许管理 \(container.name) 的图形参数？", message: "会先验证并备份原始 Info.plist。仅修改图形后端、同步、HUD、日志级别及 Harbor 会话标记；不改存档、键位、插件、登录资料或启动脚本。配置只在环境停止后应用，关联身份不会改变。", action: "备份并允许") else { return }
        do {
            try RuntimeControl.authorizeLinked(container, root: AppPaths.backups, busy: ProcessProbe.isBusy(container, entries: ProcessProbe.entries()))
            runtimeAuthorized.insert(container.id)
            notice = "原始配置已备份并验证。现在可保存图形参数；保存不会立即改动运行中的环境。"
        } catch { errorMessage = error.localizedDescription }
    }
    func restoreRuntimeParameters(_ container: ContainerRecord) {
        guard Panels.confirm(title: "恢复原始图形参数？", message: "只恢复 Harbor 管理的参数，保留其他现有配置。请先正常退出此环境中的 Windows 程序；已保存的逐游戏预设仍保留，下一次启动游戏时可能再次应用。", action: "恢复原始参数") else { return }
        do {
            try LaunchPolicy.apply(.init(), container: container, backupRoot: AppPaths.backups, busy: ProcessProbe.isBusy(container, entries: ProcessProbe.entries()))
            notice = "原始图形参数已恢复，游戏和存档未改变。"; Task { await refresh() }
        } catch { errorMessage = error.localizedDescription }
    }
    @discardableResult func savePreset(_ value: GamePreset, for game: GameRecord) -> Bool {
        guard canPersist, let container = container(game.containerID) else { return false }
        if !canCustomize(container) && value.modifiesRuntime { errorMessage = "请先允许并备份此环境的图形参数管理。启动行为选项无需这项授权。"; return false }
        if value.hasDXMTOverrides {
            do {
                let baseline = try RuntimeControl.baseline(container, root: AppPaths.backups)
                try DXMTCapabilities.read(container).validate(value, renderer: RuntimeControl.effectiveRenderer(value, baseline: baseline))
            } catch { errorMessage = error.localizedDescription; return false }
        }
        let old = state.presets[game.id], oldPrevious = state.previousPresets[game.id]
        state.previousPresets[game.id] = preset(game.id)
        state.presets[game.id] = value
        guard save() else { state.presets[game.id] = old; state.previousPresets[game.id] = oldPrevious; return false }
        notice = "预设已保存。启动行为在下次请求生效；运行时参数只在环境停止后应用，不影响正在运行的游戏。"
        return true
    }
    func restorePreset(for game: GameRecord) {
        guard let previous = state.previousPresets[game.id] else { return }
        let current = preset(game.id); state.presets[game.id] = previous; state.previousPresets[game.id] = current; save()
        notice = "已恢复上一次保存的预设。运行中配置未改变。"
    }
    func linkContainer() {
        guard let url = Panels.chooseWrapper() else { return }
        do {
            let discovered = try ContainerDiscovery.validateWrapper(url)
            if state.containers.contains(where: { URL(fileURLWithPath: $0.wrapperPath).standardizedFileURL == url.standardizedFileURL }) { notice = "这个容器已经关联。"; return }
            state.containers.append(discovered); save(); Task { await refresh() }
        } catch { errorMessage = error.localizedDescription }
    }
    func createContainer(name: String, purpose: ContainerPurpose = .steam) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, cleaned.count <= 60 else { errorMessage = "容器名称需要 1–60 个字符。"; return }
        guard !isWorking else { errorMessage = "请等待当前组件任务完成。"; return }
        let id = UUID()
        let path = AppPaths.containers.appendingPathComponent(id.uuidString).appendingPathComponent("Runtime.app").path
        var record = ContainerRecord(id: id, name: cleaned, wrapperPath: path, origin: .managed)
        record.purpose = purpose
        state.containers.append(record); save(); showCreate = false; section = .activity
        provision(record)
    }
    func provision(_ container: ContainerRecord, installSteam: Bool? = nil) {
        guard container.origin == .managed else { errorMessage = "不会重建关联的外部容器。"; return }
        guard let bootstrap = AppPaths.bootstrap else { errorMessage = "安装资源包缺失，请重新解压或构建 Harbor。未修改容器。"; return }
        if ProcessProbe.isBusy(container, entries: ProcessProbe.entries()) {
            errorMessage = "此容器还有后台进程。请先完成或关闭其 Steam 安装器，再重试准备任务。"; return
        }
        var env = ProcessInfo.processInfo.environment
        env["HARBOR_APP_DIR"] = container.wrapperPath; env["HARBOR_CACHE_DIR"] = AppPaths.cache.path
        env["HARBOR_CONTAINER_ID"] = container.id.uuidString
        let steam = installSteam ?? container.preparesSteam
        run(title: "准备 \(container.name)", executable: "/bin/bash", arguments: [bootstrap.path, steam ? "install" : "prepare"], environment: env, success: steam ? "运行时检查通过，Steam 安装请求已发出。请本人完成安装、许可和登录；这不代表游戏已经可玩。" : "通用 Windows 环境已准备，未安装 Steam。可在 Windows 应用页安装 EXE/MSI 或导入已有 EXE。")
    }
    func openSteam(_ container: ContainerRecord) {
        guard FileManager.default.fileExists(atPath: container.steamExecutable) else {
            if container.origin == .managed { provision(container, installSteam: true) } else { errorMessage = "关联容器中未找到默认路径的 Steam.exe；请先在原容器中完成 Steam 安装。" }
            return
        }
        beginLaunch(container: container, game: nil)
    }
    func launchGame(_ game: GameRecord) {
        guard let container = container(game.containerID) else { return }
        beginLaunch(container: container, game: game)
    }
    private func detectConflicts(_ libraries: [LibraryRecord]) -> Set<String> {
        let file = NSHomeDirectory() + "/Library/Application Support/Steam/steamapps/libraryfolders.vdf"
        guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { return [] }
        return SteamScanner.nativeLibraryConflicts(libraries, nativeVDF: text)
    }
    func dispatchLaunch(container: ContainerRecord, game: GameRecord?, activityID: UUID, runtimeEnvironment: [String: String] = [:]) {
        do {
            guard !isWorking else { throw HarborError.unavailable("请等待当前任务结束。") }
            try FileManager.default.createDirectory(at: AppPaths.requests, withIntermediateDirectories: true)
            let file = AppPaths.requests.appendingPathComponent(UUID().uuidString + ".cmd")
            try LaunchPolicy.batch(appID: game?.appID).write(to: file, atomically: true, encoding: .utf8)
            var environment = ProcessInfo.processInfo.environment
            environment.merge(runtimeEnvironment) { _, selected in selected }
            run(title: "启动 \(game?.name ?? "Steam")", executable: container.launcher, arguments: ["WSS-installer", file.path], environment: environment, success: "启动请求已发送，等待实际进程与窗口。", requested: true, activityID: activityID)
        } catch { failLaunch(activityID, reason: error.localizedDescription) }
    }
    func requestStop(_ container: ContainerRecord) {
        guard Panels.confirm(title: "正常退出 \(container.name)？", message: "请先在游戏内保存并退出。这里只请求 Steam 正常退出，不强杀 Wine，也不影响其他容器。", action: "请求退出") else { return }
        do {
            try FileManager.default.createDirectory(at: AppPaths.requests, withIntermediateDirectories: true)
            let file = AppPaths.requests.appendingPathComponent(UUID().uuidString + ".cmd")
            try LaunchPolicy.shutdownBatch.write(to: file, atomically: true, encoding: .utf8)
            run(title: "退出 Steam", executable: container.launcher, arguments: ["WSS-installer", file.path], success: "已发送正常退出请求；如果仍在运行，请在 Steam 菜单中选择 Exit。", requested: true)
        } catch { errorMessage = error.localizedDescription }
    }
    func endManagedRuntime(_ container: ContainerRecord) {
        guard container.origin == .managed,
              (try? String(contentsOfFile: container.wrapperPath + "/Contents/HarborManagedRuntime", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) == container.id.uuidString else { return }
        guard Panels.confirm(title: "强制结束 \(container.name)？", message: "会关闭这个托管容器中的所有 Windows 程序，未保存的进度可能丢失。请先保存并退出游戏。其他容器不受影响。结束后才可切换图形预设。", action: "已保存，结束此环境") else { return }
        run(title: "结束托管环境", executable: container.launcher, arguments: ["WSS-wineserverkill"], success: "已请求结束此托管环境。请以容器页的实时进程状态为准。", requested: true)
    }
    func forgetContainer(_ container: ContainerRecord) {
        guard !isWorking, pendingLaunch(in: container.id) == nil, !ProcessProbe.isBusy(container, entries: ProcessProbe.entries()) else { errorMessage = "请先结束此容器的运行任务，再移除记录。"; return }
        guard Panels.confirm(title: "从 Harbor 移除 \(container.name)？", message: "只移除列表记录和 Harbor 的应用入口、游戏预设、收藏、磁盘绑定。容器文件、应用、游戏和存档全部保留；之后可重新关联。", action: "移除记录，保留文件") else { return }
        state.containers.removeAll { $0.id == container.id }
        state.applications?.removeAll { $0.containerID == container.id }
        let prefix = container.id.uuidString + ":"
        state.presets = state.presets.filter { !$0.key.hasPrefix(prefix) }
        state.previousPresets = state.previousPresets.filter { !$0.key.hasPrefix(prefix) }
        state.favorites = state.favorites.filter { !$0.hasPrefix(prefix) }
        state.bindings.removeAll { $0.containerID == container.id }
        selectedGameID = nil; save(); notice = "记录已移除，原文件保留在原位置。"
        Task { await refresh() }
    }
    func bindDrive(container: ContainerRecord, letter: String, volume: MountedVolume) {
        guard let uuid = volume.uuid else { errorMessage = "无法读取卷标识，未建立自动恢复绑定。"; return }
        guard Panels.confirm(title: "绑定 \(letter.uppercased()): → \(volume.name)？", message: "只会创建缺失的盘符链接，不替换已有映射、不改写 Steam 库配置、不停止程序。Steam 可能需要正常退出后重开，才能重新识别这个库。", action: "建立映射") else { return }
        do {
            try DriveMapper.createMissingLink(container: container, letter: letter, target: URL(fileURLWithPath: volume.path), allowLinkedRepair: true)
            let binding = DriveBinding(containerID: container.id, letter: letter.uppercased(), volumeUUID: uuid, volumeName: volume.name)
            state.bindings.removeAll { $0.id == binding.id }; state.bindings.append(binding); save()
            notice = "盘符已映射。是否登记为 Steam 游戏库，需要在 Wine Steam 内确认。"; showBind = false; Task { await refresh() }
        } catch { errorMessage = error.localizedDescription }
    }
    func repair(_ binding: DriveBinding) {
        guard let container = container(binding.containerID), let target = DriveMapper.target(for: binding, volumes: volumes) else { errorMessage = "没有发现该卷标识对应的磁盘，请先连接原磁盘。"; return }
        guard Panels.confirm(title: "恢复 \(binding.letter): 映射？", message: "按保存的卷标识恢复到 \(target.path)。仅修复缺失链接，不替换其他路径。", action: "恢复") else { return }
        do { try DriveMapper.createMissingLink(container: container, letter: binding.letter, target: target, allowLinkedRepair: true); notice = "映射已恢复；请在 Steam 中确认库已识别。"; Task { await refresh() } }
        catch { errorMessage = error.localizedDescription }
    }

    func run(title: String, executable: String, arguments: [String], environment: [String:String]? = nil, success: String, requested: Bool = false, activityID: UUID? = nil) {
        guard !isWorking else { errorMessage = "请等待当前任务结束。"; return }
        let record = activityID.flatMap { id in state.activity.first { $0.id == id } } ?? ActivityRecord(title: title, detail: "正在执行…")
        if activityID == nil { state.activity.insert(record, at: 0); state.activity = Array(state.activity.prefix(80)) }
        activeTaskID = record.id; activeStage = title; taskProgress = nil; save()
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.environment = environment; process.standardOutput = pipe; process.standardError = pipe
        var requestOutput: FileHandle?
        if requested {
            do {
                try FileManager.default.createDirectory(at: AppPaths.root.appendingPathComponent("Logs"), withIntermediateDirectories: true)
                let log = AppPaths.root.appendingPathComponent("Logs/\(record.id.uuidString).log")
                FileManager.default.createFile(atPath: log.path, contents: nil)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: log.path)
                requestOutput = try FileHandle(forWritingTo: log)
                process.standardOutput = requestOutput; process.standardError = requestOutput
            } catch {
                activeTaskID = nil; activeStage = ""; errorMessage = error.localizedDescription
                if let index = state.activity.firstIndex(where: { $0.id == record.id }) { state.activity[index].state = .failed; state.activity[index].detail = error.localizedDescription }
                if activityID != nil { failLaunch(record.id, reason: error.localizedDescription) }
                save(); return
            }
        }
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            let text = LogRedactor.redact(String(decoding: data, as: UTF8.self))
            Task { @MainActor in self?.appendLog(text, id: record.id) }
        }
        process.terminationHandler = { [weak self] stopped in
            Task { @MainActor in
                guard let self else { return }
                if let index = self.state.activity.firstIndex(where: { $0.id == record.id }) {
                    if activityID != nil {
                        if stopped.terminationStatus != 0, self.launchProgress[record.id]?.isPending == true {
                            self.failLaunch(record.id, reason: "启动器退出（\(stopped.terminationStatus)）。可查看 Steam 提示或诊断；不会自动重启。")
                        }
                    } else {
                        self.state.activity[index].state = stopped.terminationStatus == 0 ? (requested ? .requested : .succeeded) : .failed
                        self.state.activity[index].detail = stopped.terminationStatus == 0 ? success : "任务未完成（退出码 \(stopped.terminationStatus)）。原文件保留，可查看日志后重试。"
                    }
                }
                self.requestProcesses.removeValue(forKey: record.id)
                if self.activeTaskID == record.id { self.activeProcess = nil; self.activeTaskID = nil; self.activeStage = ""; self.taskProgress = nil }
                self.save(); await self.refresh()
                self.logger.info("Task completed with exit \(stopped.terminationStatus)")
            }
        }
        do {
            activeProcess = process; try process.run(); try? requestOutput?.close(); logger.info("Task started: \(title, privacy: .public)")
            if requested {
                pipe.fileHandleForReading.readabilityHandler = nil
                requestProcesses[record.id] = process
                if let index = state.activity.firstIndex(where: { $0.id == record.id }) { state.activity[index].state = .requested }
                activeTaskID = nil; activeProcess = nil; activeStage = ""
                if activityID == nil { notice = success; if let index = state.activity.firstIndex(where: { $0.id == record.id }) { state.activity[index].detail = success } }
                save(); Task { await self.pollLaunches() }
            }
        }
        catch {
            pipe.fileHandleForReading.readabilityHandler = nil; try? requestOutput?.close()
            if let index = state.activity.firstIndex(where: { $0.id == record.id }) { state.activity[index].state = .failed; state.activity[index].detail = error.localizedDescription }
            activeTaskID = nil; activeProcess = nil; errorMessage = error.localizedDescription; save()
            if activityID != nil { failLaunch(record.id, reason: error.localizedDescription) }
        }
    }
    private func appendLog(_ text: String, id: UUID) {
        guard let index = state.activity.firstIndex(where: { $0.id == id }) else { return }
        state.activity[index].log = String((state.activity[index].log + text).suffix(24_000))
        if text.contains("下载官方文件") { taskProgress = nil }
        if let pattern = try? NSRegularExpression(pattern: #"(\d{1,3}(?:\.\d+)?)%"#),
           let match = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
           let range = Range(match.range(at: 1), in: text), let percent = Double(text[range]), percent <= 100 {
            taskProgress = percent / 100
            activeStage = String(format: "正在下载当前组件 · %.1f%%", percent)
        } else if let last = text.components(separatedBy: .newlines).last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }), last.count < 160, !last.contains("###") { activeStage = last; taskProgress = nil }
    }
    func exportDiagnostics() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
        let overview = "Harbor \(version) · 本地诊断\n系统：\(ProcessInfo.processInfo.operatingSystemVersionString)\n容器：\(state.containers.count) · 游戏记录：\(games.count) · 已安装：\(readyCount) · 离线：\(offlineCount)\n"
        let containers = state.containers.map { "\($0.name) | \($0.displayOrigin) | \(Format.path($0.wrapperPath))" }.joined(separator: "\n")
        let tasks = state.activity.prefix(15).map { "\n\($0.title) [\($0.state.rawValue)]\n\($0.detail)\n\($0.log)" }.joined(separator: "\n")
        do { try Panels.exportText(LogRedactor.redact(overview + containers + "\n" + warnings.joined(separator: "\n") + tasks)) }
        catch { errorMessage = error.localizedDescription }
    }
    func reveal(_ path: String) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
}
