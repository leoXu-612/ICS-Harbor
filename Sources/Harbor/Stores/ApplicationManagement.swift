import Foundation
import HarborCore

extension AppModel {
    var applications: [WindowsApplication] { state.applications ?? [] }
    var selectedApplication: WindowsApplication? { applications.first { $0.id == selectedApplicationID } }
    func addApplication() { editingApplication = nil; showAddApplication = true }
    func editApplication(_ app: WindowsApplication) { editingApplication = app; showAddApplication = true }
    @discardableResult func saveApplication(_ app: WindowsApplication) -> Bool {
        guard let container = container(app.containerID) else { return false }
        do {
            try WindowsCommand.validate(app, container: container)
            let old = state.applications
            var values = applications
            if let index = values.firstIndex(where: { $0.id == app.id }) { values[index] = app }
            else {
                guard !values.contains(where: { $0.containerID == app.containerID && $0.executablePath == app.executablePath }) else { throw HarborError.invalid("此环境中已经添加了这个 EXE，请编辑现有入口。") }
                values.append(app)
            }
            state.applications = values
            guard save() else { state.applications = old; return false }
            selectedApplicationID = app.id; section = .applications
            notice = "已保存应用入口，未复制或移动程序文件。"; return true
        } catch { errorMessage = error.localizedDescription; return false }
    }
    func forgetApplication(_ app: WindowsApplication) {
        guard Panels.confirm(title: "移除 \(app.name) 的入口？", message: "只移除 Harbor 中的启动记录，程序、文档与设置全部保留。这不是卸载。", action: "移除入口") else { return }
        let old = state.applications
        state.applications?.removeAll { $0.id == app.id }
        if save() { selectedApplicationID = nil } else { state.applications = old }
    }
    func applicationProgress(_ app: WindowsApplication) -> LaunchProgress? {
        launchProgress.values.filter { $0.applicationID == app.id }.max { $0.startedAt < $1.startedAt }
    }
    func launchApplication(_ app: WindowsApplication) {
        guard let container = container(app.containerID) else { return }
        beginStandalone(container: container, app: app, installerURL: nil)
    }
    func installApplication(_ url: URL, container: ContainerRecord) {
        beginStandalone(container: container, app: nil, installerURL: url)
    }
    private func beginStandalone(container: ContainerRecord, app: WindowsApplication?, installerURL: URL?) {
        guard !isWorking else { errorMessage = "请等待组件准备任务完成。"; return }
        if let pending = pendingLaunch(in: container.id) { presentProgress(pending.id); return }
        let installing = installerURL != nil
        let file = installerURL ?? URL(fileURLWithPath: app!.executablePath)
        var record = ActivityRecord(title: (installing ? "安装 · " : "启动 · ") + (app?.name ?? file.lastPathComponent), detail: "正在检查文件与运行环境", state: .requested)
        var progress = LaunchProgress(id: record.id, containerID: container.id, appID: nil, title: app?.name ?? file.lastPathComponent)
        progress.standalone = true; progress.installer = installing; progress.applicationID = app?.id
        record.launch = progress; launchProgress[record.id] = progress; focusedLaunchID = record.id
        state.activity.insert(record, at: 0); state.activity = Array(state.activity.prefix(80)); save()
        let requests = AppPaths.requests, backups = AppPaths.backups
        Task {
            let plan = await Task.detached(priority: .userInitiated) { () -> Result<(URL, URL, String), Error> in
                do {
                    guard FileManager.default.isExecutableFile(atPath: container.launcher), RuntimeInfo.read(container).initialized else { throw HarborError.unavailable("请先完成这个运行环境的准备。") }
                    let busy = ProcessProbe.isBusy(container, entries: ProcessProbe.entries())
                    if installing {
                        guard container.origin == .managed,
                              (try? String(contentsOfFile: container.wrapperPath + "/Contents/HarborManagedRuntime", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) == container.id.uuidString else {
                            throw HarborError.protected("安装新软件请使用 Harbor 托管环境，避免改动关联游戏容器。已安装的 EXE 可以只导入启动入口。")
                        }
                        guard !busy else { throw HarborError.protected("安装前请先保存并退出这个环境中的 Windows 程序。Harbor 不会为安装而关闭它们。") }
                        try WindowsCommand.validateFile(file, installer: true)
                    } else if let app { try WindowsCommand.validate(app, container: container) }
                    let executable = try WindowsCommand.windowsPath(file, container: container)
                    guard executable.lowercased() != "c:\\program files (x86)\\steam\\steam.exe" else { throw HarborError.invalid("Steam 请从运行环境页启动，以保留游戏库冲突检查和连接状态。") }
                    let working = try WindowsCommand.windowsPath(URL(fileURLWithPath: app?.workingDirectory ?? file.deletingLastPathComponent().path), container: container)
                    try FileManager.default.createDirectory(at: requests, withIntermediateDirectories: true)
                    let script = requests.appendingPathComponent(record.id.uuidString + ".cmd")
                    let result = requests.appendingPathComponent(record.id.uuidString + ".exit")
                    let resultPath = try WindowsCommand.windowsPath(result, container: container)
                    let text = try WindowsCommand.batch(executable: executable, workingDirectory: working, arguments: app?.arguments ?? [], installer: installing, resultPath: resultPath)
                    try LaunchPolicy.apply(.init(), container: container, backupRoot: backups, busy: busy)
                    try text.write(to: script, atomically: true, encoding: .utf8)
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: script.path)
                    return .success((script, result, installing && file.pathExtension.lowercased() == "msi" ? "C:\\windows\\system32\\msiexec.exe" : executable))
                } catch { return .failure(error) }
            }.value
            guard self.launchProgress[record.id]?.isPending == true else { return }
            switch plan {
            case .failure(let error): self.failLaunch(record.id, reason: error.localizedDescription)
            case .success(let (script, result, executable)):
                self.launchProgress[record.id]?.checkedFiles(at: Date())
                self.launchTargets[record.id] = LaunchProbeTarget(container: container, game: nil, since: progress.startedAt, executable: executable, completionPath: result.path)
                let observed = await Task.detached { LaunchProbe.sample([record.id: LaunchProbeTarget(container: container, game: nil, since: progress.startedAt, executable: executable)]) }.value
                if !installing, let evidence = observed[record.id], evidence.gamePID != nil {
                    self.launchProgress[record.id]?.observe(evidence, at: Date()); self.saveLaunchSnapshot(record.id); self.focusLaunch(record.id); return
                }
                self.saveLaunchSnapshot(record.id)
                self.run(title: record.title, executable: container.launcher, arguments: ["WSS-installer", script.path], success: "请求已发送；等待实际 Windows 进程与窗口。", requested: true, activityID: record.id)
            }
        }
    }
}
