import Foundation

public enum Renderer: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit, dxmt, dxvk
    public var id: String { rawValue }
    public var title: String { switch self { case .inherit: return "继承原始配置"; case .dxmt: return "DXMT"; case .dxvk: return "DXVK" } }
    public var subtitle: String { switch self { case .inherit: return "恢复该环境备份的原始参数"; case .dxmt: return "Direct3D 10/11 → Metal"; case .dxvk: return "对照测试 · 兼容性因游戏而异" } }
}
public enum SyncMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit, enabled, msync, esync, disabled
    public var id: String { rawValue }
    public var title: String {
        switch self { case .inherit: return "继承原始配置"; case .enabled: return "M-Sync + E-Sync（原双开方式）"; case .msync: return "仅 M-Sync"; case .esync: return "仅 E-Sync"; case .disabled: return "全部关闭" }
    }
}
public enum ParameterOverride: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit, enabled, disabled
    public var id: String { rawValue }
    public var title: String { switch self { case .inherit: return "继承"; case .enabled: return "开启"; case .disabled: return "关闭" } }
    public var boolValue: Bool? { self == .inherit ? nil : self == .enabled }
}
public enum FrameLimit: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit, unlimited, fps30, fps60, fps90, fps120, fps144, fps165, fps240
    public var id: String { rawValue }
    public var value: Int? {
        switch self { case .inherit: return nil; case .unlimited: return 0; case .fps30: return 30; case .fps60: return 60; case .fps90: return 90; case .fps120: return 120; case .fps144: return 144; case .fps165: return 165; case .fps240: return 240 }
    }
    public var title: String { self == .inherit ? "继承" : self == .unlimited ? "不限制" : "\(value ?? 0) FPS" }
}
public enum WineLogLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case inherit, errors, warnings
    public var id: String { rawValue }
    public var title: String { switch self { case .inherit: return "继承原始配置"; case .errors: return "仅错误"; case .warnings: return "错误与警告" } }
    public var channels: String? { self == .inherit ? nil : self == .errors ? "-all,err+all" : "-all,err+all,warn+all" }
}
public enum LaunchWaitThreshold: Int, Codable, CaseIterable, Identifiable, Sendable {
    case seconds30 = 30, seconds45 = 45, seconds90 = 90, seconds180 = 180
    public var id: Int { rawValue }
    public var title: String { "\(rawValue) 秒无新状态" }
}

public struct GamePreset: Codable, Equatable, Sendable {
    public var renderer: Renderer = .inherit
    public var sync: SyncMode = .inherit
    public var hud: ParameterOverride = .inherit
    public var logging: WineLogLevel = .inherit
    public var frameLimit: FrameLimit = .inherit
    public var forceSDR: ParameterOverride = .inherit
    public var handleAltTab: ParameterOverride = .inherit
    public var showProgress = true
    public var focusOnWindow = false
    public var waitThreshold: LaunchWaitThreshold = .seconds45
    public init(renderer: Renderer = .inherit, sync: SyncMode = .inherit, metalHUD: Bool = false) {
        self.renderer = renderer; self.sync = sync; hud = metalHUD ? .enabled : .inherit
    }
    // Kept for source callers; serialized old false values inherit the original
    // baseline, which matches the old linked-container protection behaviour.
    public var metalHUD: Bool { get { hud == .enabled } set { hud = newValue ? .enabled : .disabled } }
    public var hasDXMTOverrides: Bool { frameLimit != .inherit || forceSDR != .inherit || handleAltTab != .inherit }
    public var modifiesRuntime: Bool { renderer != .inherit || sync != .inherit || hud != .inherit || logging != .inherit || hasDXMTOverrides }
    public var summary: String {
        var parts: [String] = []
        if renderer != .inherit { parts.append(renderer.title) }
        if frameLimit != .inherit { parts.append(frameLimit.title) }
        if sync != .inherit { parts.append(sync == .enabled ? "双同步" : sync == .msync ? "M-Sync" : sync == .esync ? "E-Sync" : "同步关闭") }
        if hud != .inherit { parts.append(hud == .enabled ? "HUD 开" : "HUD 关") }
        if parts.isEmpty { return modifiesRuntime ? "自定义运行参数" : "继承原始配置" }
        return parts.joined(separator: " · ")
    }
    public mutating func resetDXMT() { frameLimit = .inherit; forceSDR = .inherit; handleAltTab = .inherit }
    /// Values are generated only from finite enums; no shell or user commands.
    public var runtimeEnvironment: [String: String] {
        var env: [String: String] = [:], options: [String] = []
        if let value = frameLimit.value { options.append("d3d11.preferredMaxFrameRate=\(value)") }
        if let value = forceSDR.boolValue { options.append("dxgi.forceSDR=\(value ? "True" : "False")") }
        if let value = handleAltTab.boolValue { options.append("dxgi.handleAltTab=\(value ? "True" : "False")") }
        if !options.isEmpty { env["DXMT_CONFIG"] = options.joined(separator: ";") }
        if let value = hud.boolValue { env["MTL_HUD_ENABLED"] = value ? "1" : "0" }
        return env
    }
    enum CodingKeys: String, CodingKey { case renderer, sync, metalHUD, hud, logging, frameLimit, forceSDR, handleAltTab, showProgress, focusOnWindow, waitThreshold }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        renderer = try c.decodeIfPresent(Renderer.self, forKey: .renderer) ?? .inherit
        sync = try c.decodeIfPresent(SyncMode.self, forKey: .sync) ?? .inherit
        hud = try c.decodeIfPresent(ParameterOverride.self, forKey: .hud) ?? ((try c.decodeIfPresent(Bool.self, forKey: .metalHUD) ?? false) ? .enabled : .inherit)
        logging = try c.decodeIfPresent(WineLogLevel.self, forKey: .logging) ?? .inherit
        frameLimit = try c.decodeIfPresent(FrameLimit.self, forKey: .frameLimit) ?? .inherit
        forceSDR = try c.decodeIfPresent(ParameterOverride.self, forKey: .forceSDR) ?? .inherit
        handleAltTab = try c.decodeIfPresent(ParameterOverride.self, forKey: .handleAltTab) ?? .inherit
        showProgress = try c.decodeIfPresent(Bool.self, forKey: .showProgress) ?? true
        focusOnWindow = try c.decodeIfPresent(Bool.self, forKey: .focusOnWindow) ?? false
        waitThreshold = try c.decodeIfPresent(LaunchWaitThreshold.self, forKey: .waitThreshold) ?? .seconds45
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(renderer, forKey: .renderer); try c.encode(sync, forKey: .sync)
        try c.encode(hud, forKey: .hud); try c.encode(hud == .enabled, forKey: .metalHUD)
        try c.encode(logging, forKey: .logging); try c.encode(frameLimit, forKey: .frameLimit)
        try c.encode(forceSDR, forKey: .forceSDR); try c.encode(handleAltTab, forKey: .handleAltTab)
        try c.encode(showProgress, forKey: .showProgress); try c.encode(focusOnWindow, forKey: .focusOnWindow)
        try c.encode(waitThreshold, forKey: .waitThreshold)
    }
}
