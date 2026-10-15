import Foundation

public enum LaunchPolicy {
    public static func validate(game: GameRecord, container: ContainerRecord, preset: GamePreset, busy: Bool, linkedAuthorized: Bool = false) throws {
        guard SteamScanner.isAppID(game.appID) else { throw HarborError.invalid("Steam App ID 不合法。") }
        guard game.containerID == container.id else { throw HarborError.invalid("游戏与容器不匹配。") }
        guard game.availability == .ready else { throw HarborError.unavailable("\(game.availability.title)。请先连接游戏磁盘并在 Steam 确认安装状态。") }
        if preset.modifiesRuntime {
            guard container.origin == .managed || linkedAuthorized else { throw HarborError.protected("此游戏关联的是外部容器。请先允许并备份图形参数管理，或继续继承原始配置。") }
            guard !busy else { throw HarborError.protected("此容器仍有后台进程。先在游戏内保存并退出 Steam，再应用预设。Harbor 不会中断正在运行的游戏。") }
        }
    }
    public static func batch(appID: String?) throws -> String {
        let suffix: String
        if let appID {
            guard SteamScanner.isAppID(appID) else { throw HarborError.invalid("Steam App ID 不合法。") }
            suffix = " -applaunch " + appID
        } else { suffix = "" }
        return "@echo off\r\n\"C:\\Program Files (x86)\\Steam\\Steam.exe\"" + suffix + "\r\n"
    }
    public static let shutdownBatch = "@echo off\r\n\"C:\\Program Files (x86)\\Steam\\Steam.exe\" -shutdown\r\n"

    public static func applying(_ preset: GamePreset, to dictionary: [String: Any]) -> [String: Any] {
        var result = dictionary
        if preset.renderer != .inherit {
            result["D3DMETAL"] = 0
            result["DXVK"] = preset.renderer == .dxvk ? 1 : 0
        }
        if preset.sync != .inherit {
            result["WINEESYNC"] = preset.sync == .enabled || preset.sync == .esync ? 1 : 0
            result["WINEMSYNC"] = preset.sync == .enabled || preset.sync == .msync ? 1 : 0
        }
        if let value = preset.hud.boolValue { result["METAL_HUD"] = value ? 1 : 0 }
        if let value = preset.logging.channels { result["WINEDEBUG"] = value }
        // This key is only Harbor's session ledger; Sikarugir does not execute it.
        // It prevents a warm Steam from silently retaining a previous game's env.
        result["HarborSessionEnvironment"] = preset.runtimeEnvironment.isEmpty ? nil : preset.runtimeEnvironment
        return result
    }
    public static func apply(_ preset: GamePreset, container: ContainerRecord, backupRoot: URL, busy: Bool) throws {
        if container.origin == .linked && !RuntimeControl.isAuthorized(container, root: backupRoot) {
            guard !preset.modifiesRuntime else { throw HarborError.protected("未授权修改关联容器的图形配置。") }
            return
        }
        let baseline = try RuntimeControl.baseline(container, root: backupRoot)
        if preset.hasDXMTOverrides { try DXMTCapabilities.read(container).validate(preset, renderer: RuntimeControl.effectiveRenderer(preset, baseline: baseline)) }
        let file = URL(fileURLWithPath: container.wrapperPath + "/Contents/Info.plist")
        let previous = try Data(contentsOf: file)
        guard let plist = try PropertyListSerialization.propertyList(from: previous, format: nil) as? [String: Any] else { throw HarborError.invalid("运行时配置不可解析。") }
        // Inherited fields come from this container's original baseline, not the last game.
        // Only managed graphics keys change; all unrelated current settings remain intact.
        let desired = applying(preset, to: baseline)
        var updated = plist
        for key in ["D3DMETAL", "DXVK", "WINEESYNC", "WINEMSYNC", "METAL_HUD", "WINEDEBUG", "HarborSessionEnvironment"] { updated[key] = desired[key] }
        guard !NSDictionary(dictionary: updated).isEqual(to: plist) else { return }
        guard !busy else { throw HarborError.protected("切换或恢复预设需要先结束这个托管容器。运行中的环境未被修改。") }
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let backup = backupRoot.appendingPathComponent(container.id.uuidString + "-" + UUID().uuidString + ".plist")
        try previous.write(to: backup, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        try PropertyListSerialization.data(fromPropertyList: updated, format: .xml, options: 0).write(to: file, options: .atomic)
    }
}
