import Foundation

public enum RuntimeControl {
    private struct Approval: Codable { var containerID: UUID; var wrapperPath: String; var approvedAt: Date }
    private static func directory(_ container: ContainerRecord, root: URL) -> URL {
        root.appendingPathComponent("RuntimeControls").appendingPathComponent(container.id.uuidString)
    }
    private static func canonical(_ container: ContainerRecord) -> String {
        URL(fileURLWithPath: container.wrapperPath).standardizedFileURL.resolvingSymlinksInPath().path
    }
    public static func isAuthorized(_ container: ContainerRecord, root: URL) -> Bool {
        if container.origin == .managed { return true }
        let folder = directory(container, root: root)
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("approval.json")),
              let approval = try? JSONDecoder().decode(Approval.self, from: data),
              approval.containerID == container.id, approval.wrapperPath == canonical(container),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("baseline.plist").path) else { return false }
        return true
    }
    /// Explicit opt-in creates a durable baseline; it never changes the wrapper.
    public static func authorizeLinked(_ container: ContainerRecord, root: URL, busy: Bool) throws {
        guard container.origin == .linked else { return }
        guard !busy else { throw HarborError.protected("请先正常退出这个环境中的 Steam 和其他 Windows 程序，再保存原始配置。") }
        if isAuthorized(container, root: root) { return }
        let target = directory(container, root: root)
        guard !FileManager.default.fileExists(atPath: target.path) else { throw HarborError.protected("已有不匹配的授权备份，未覆盖。请先检查备份路径。") }
        let source = try Data(contentsOf: URL(fileURLWithPath: container.wrapperPath + "/Contents/Info.plist"))
        guard (try PropertyListSerialization.propertyList(from: source, format: nil)) is [String: Any] else { throw HarborError.invalid("环境配置不是有效的属性列表，未授权。") }
        let stage = target.deletingLastPathComponent().appendingPathComponent(".approval-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try source.write(to: stage.appendingPathComponent("baseline.plist"), options: .atomic)
        let approval = Approval(containerID: container.id, wrapperPath: canonical(container), approvedAt: Date())
        try JSONEncoder().encode(approval).write(to: stage.appendingPathComponent("approval.json"), options: .atomic)
        for name in ["baseline.plist", "approval.json"] { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stage.appendingPathComponent(name).path) }
        guard try Data(contentsOf: stage.appendingPathComponent("baseline.plist")) == source else { throw HarborError.unavailable("备份字节验证失败，原配置未改变。") }
        try FileManager.default.moveItem(at: stage, to: target)
    }
    public static func baseline(_ container: ContainerRecord, root: URL) throws -> [String: Any] {
        let file: URL
        if container.origin == .managed {
            guard (try? String(contentsOfFile: container.wrapperPath + "/Contents/HarborManagedRuntime", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) == container.id.uuidString else {
                throw HarborError.protected("托管标记不匹配，未修改运行时。")
            }
            file = URL(fileURLWithPath: container.wrapperPath + "/Contents/HarborBaseline.plist")
        } else {
            guard isAuthorized(container, root: root) else { throw HarborError.protected("关联环境尚未允许图形参数管理。请先确认并备份原始配置。") }
            file = directory(container, root: root).appendingPathComponent("baseline.plist")
        }
        guard let dictionary = try PropertyListSerialization.propertyList(from: Data(contentsOf: file), format: nil) as? [String: Any] else { throw HarborError.invalid("原始参数备份不可解析，未修改配置。") }
        return dictionary
    }
    public static func rendererName(_ dictionary: [String: Any]) -> String {
        (dictionary["D3DMETAL"] as? NSNumber)?.boolValue == true ? "D3DMetal" : (dictionary["DXVK"] as? NSNumber)?.boolValue == true ? "DXVK" : "DXMT"
    }
    public static func effectiveRenderer(_ preset: GamePreset, baseline: [String: Any]) -> String {
        preset.renderer == .inherit ? rendererName(baseline) : preset.renderer == .dxmt ? "DXMT" : "DXVK"
    }
}

public struct DXMTCapabilities: Sendable {
    public var frameLimit: Bool
    public var forceSDR: Bool
    public var handleAltTab: Bool
    public static func read(_ container: ContainerRecord) -> DXMTCapabilities {
        let root = container.wrapperPath + "/Contents/Frameworks/renderer/dxmt/wine/"
        let files = ["x86_64-windows", "i386-windows"].compactMap { arch -> Data? in
            try? Data(contentsOf: URL(fileURLWithPath: root + arch + "/d3d11.dll"), options: .mappedIfSafe)
        }
        func supports(_ key: String) -> Bool { !files.isEmpty && files.allSatisfy { $0.range(of: Data(key.utf8)) != nil } }
        return DXMTCapabilities(frameLimit: supports("d3d11.preferredMaxFrameRate"), forceSDR: supports("dxgi.forceSDR"), handleAltTab: supports("dxgi.handleAltTab"))
    }
    public func validate(_ preset: GamePreset, renderer: String) throws {
        guard preset.hasDXMTOverrides else { return }
        guard renderer == "DXMT" else { throw HarborError.invalid("当前后端不是 DXMT。请切换后端，或清除 DXMT 专用参数。") }
        guard (preset.frameLimit == .inherit || frameLimit), (preset.forceSDR == .inherit || forceSDR), (preset.handleAltTab == .inherit || handleAltTab) else {
            throw HarborError.unavailable("此环境的 DXMT 文件未包含所选参数，未应用。不会自动升级或替换图形组件。")
        }
    }
}
