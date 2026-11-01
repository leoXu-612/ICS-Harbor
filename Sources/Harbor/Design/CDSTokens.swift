import SwiftUI
import AppKit

// ============================================================================
// Claude Design System (CDS) — SwiftUI Native Token Layer
//
// 令牌来源：open-claude-ui (MIT) 对 Claude Desktop 的逆向提取结果：
//   · 35 阶暖灰 / 陶土色阶、Surface 0–3 微对比梯度
//   · 0.5px 发丝边（视网膜补偿）、8 / 10 / 12 / 16 / 20 精密圆角矩阵
//   · 双环浮层架构、四套生产级弹簧参数
//   · 暗色模式视网膜光渗字重逆补偿（500→465 / 600→560 / 700→660）
//
// 本层只做取值映射，不做 SwiftUI 控件。控件见 CDSControls.swift。
// ============================================================================

// MARK: - 颜色令牌

enum CDSColor {
    /// Surface 0 — 侧边栏 / 底层画布
    static let surface0 = dynamic(light: 0xF9F9F7, dark: 0x0B0B0B)
    /// Surface 1 — 主内容画布
    static let surface1 = dynamic(light: 0xFCFCFB, dark: 0x151515)
    /// Surface 2 — 卡片 / 消息表面
    static let surface2 = dynamic(light: 0xFFFFFF, dark: 0x1A1A19)
    /// Surface 3 — 输入框 / 高层浮层
    static let surface3 = dynamic(light: 0xFFFFFF, dark: 0x20201F)
    /// 弹出层（暗色下抬升一阶）
    static let surfacePopover = dynamic(light: 0xFFFFFF, dark: 0x2C2C2A)

    /// 品牌陶土橙（浅色 #d97757 / 暗色保持同一色相）
    static let clay = dynamic(light: 0xD97757, dark: 0xD97757)
    static let clayHover = dynamic(light: 0xCC5A36, dark: 0xE08264)
    static let clayPressed = dynamic(light: 0xB9502E, dark: 0xC96F4E)
    /// 陶土极浅背景（选中态 / 弱强调块）
    static let claySubtle = dynamicAlpha(light: 0xD97757, lightAlpha: 0.10,
                                         dark: 0xD97757, darkAlpha: 0.16)

    static let textPrimary = dynamic(light: 0x151515, dark: 0xF5F5F5)
    static let textSecondary = dynamic(light: 0x525252, dark: 0xA3A3A3)
    static let textMuted = dynamic(light: 0x6E6E6E, dark: 0x8F8F8F)
    static let textOnAccent = Color.white

    /// 发丝边 / 强发丝边（Alpha 阶梯 10% / 20%，暗色 9% / 18%）
    static let border = dynamicAlpha(light: 0x080808, lightAlpha: 0.10,
                                     dark: 0xFFFFFF, darkAlpha: 0.09)
    static let borderStrong = dynamicAlpha(light: 0x080808, lightAlpha: 0.20,
                                           dark: 0xFFFFFF, darkAlpha: 0.18)
    static let borderHairline = dynamicAlpha(light: 0x080808, lightAlpha: 0.07,
                                             dark: 0xFFFFFF, darkAlpha: 0.06)

    /// 交互填充阶梯
    static let fillGhostHover = dynamicAlpha(light: 0x080808, lightAlpha: 0.05,
                                             dark: 0xFFFFFF, darkAlpha: 0.05)
    static let fillGhostSelected = dynamicAlpha(light: 0x080808, lightAlpha: 0.10,
                                               dark: 0xFFFFFF, darkAlpha: 0.09)
    static let fillSecondary = dynamicAlpha(light: 0x080808, lightAlpha: 0.10,
                                           dark: 0xFFFFFF, darkAlpha: 0.09)
    static let fillSecondaryHover = dynamicAlpha(light: 0x151515, lightAlpha: 0.14,
                                                 dark: 0xFFFFFF, darkAlpha: 0.14)
    static let fillTertiary = dynamicAlpha(light: 0x080808, lightAlpha: 0.04,
                                          dark: 0xFFFFFF, darkAlpha: 0.04)

    /// 分段控件轨道与滑块
    static let segmentedTrack = dynamicAlpha(light: 0x080808, lightAlpha: 0.06,
                                             dark: 0xFFFFFF, darkAlpha: 0.08)
    static let segmentedThumb = dynamic(light: 0xFFFFFF, dark: 0x35352F)

    /// 语义状态色 —— 与陶土色同温度的低饱和选择
    static let signal = dynamic(light: 0x2F7D5A, dark: 0x6FBF95)
    static let warning = dynamic(light: 0xA9701F, dark: 0xD9A441)
    static let fault = dynamic(light: 0xC0392B, dark: 0xF87171)
    static let info = dynamic(light: 0x2A78D6, dark: 0x6BA6E8)

    /// 遮罩 / 分区底
    static let scrim = dynamicAlpha(light: 0x000000, lightAlpha: 0.28,
                                    dark: 0x000000, darkAlpha: 0.55)

    // MARK: 构造工具

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = isDark(appearance) ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }

    private static func dynamicAlpha(light: UInt32, lightAlpha: CGFloat,
                                     dark: UInt32, darkAlpha: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let (hex, alpha) = isDark(appearance) ? (dark, darkAlpha) : (light, lightAlpha)
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: alpha)
        })
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

// MARK: - 圆角 / 间距 / 海拔

enum CDSRadius {
    static let xs: CGFloat = 2
    static let sm: CGFloat = 4
    static let md: CGFloat = 6
    static let lg: CGFloat = 8
    static let panel: CGFloat = 10
    static let xl: CGFloat = 12
    static let dialog: CGFloat = 16
    static let bubble: CGFloat = 18
    static let composer: CGFloat = 20
    static let pill: CGFloat = 999
}

enum CDSSpacing {
    static let hair: CGFloat = 4
    static let tight: CGFloat = 8
    static let snug: CGFloat = 12
    static let base: CGFloat = 16
    static let roomy: CGFloat = 20
    static let section: CGFloat = 28
    static let page: CGFloat = 24
}

enum CDSElevation {
    case none, sm, md, lg, popover
}

// MARK: - 物理弹簧（对应 CDS 四套生产预设）

enum CDSMotion {
    /// 麦克风 / 语音条：高频微弹，ζ≈0.612
    static let bouncy = Animation.interpolatingSpring(stiffness: 600, damping: 30)
    /// 控件咬合 / 悬停反馈：ζ≈0.98
    static let snappy = Animation.interpolatingSpring(stiffness: 320, damping: 28)
    /// 面板滑入 / 折叠展开
    static let gentle = Animation.interpolatingSpring(stiffness: 380, damping: 18)
    /// 精确吸附（double-click 吸附、拖拽落位）
    static let heavySnap = Animation.interpolatingSpring(stiffness: 1200, damping: 80)

    /// 触觉微震：120ms 几何咬合
    static let press = Animation.easeOut(duration: 0.12)

    static func honoring(_ reduceMotion: Bool, _ animation: Animation) -> Animation? {
        reduceMotion ? nil : animation
    }
}

// MARK: - 排版（暗色字重逆补偿）

enum CDSType {
    /// CDS 光学补偿：暗色下 500→465、600→560、700→660。
    /// SwiftUI 无法设定可变字重轴，按最近一档下调实现等效补偿。
    static func compensated(_ weight: Font.Weight, dark: Bool) -> Font.Weight {
        guard dark else { return weight }
        switch weight {
        case .medium: return .regular
        case .semibold: return .medium
        case .bold: return .semibold
        case .heavy, .black: return .bold
        default: return weight
        }
    }
}

// MARK: - View 扩展

extension View {
    /// CDS 字体：默认 SF 系统无衬线（Editorial Warmth，不使用圆体）。
    func cdsType(_ size: CGFloat,
                 _ weight: Font.Weight = .regular,
                 tracking: CGFloat? = nil,
                 mono: Bool = false) -> some View {
        modifier(CDSTypeModifier(size: size, weight: weight, tracking: tracking, mono: mono))
    }

    func cdsShadow(_ level: CDSElevation) -> some View {
        modifier(CDSShadowModifier(level: level))
    }

    /// 发丝边：真 1 物理像素（视网膜屏 0.5pt）。
    func cdsHairlineBorder(radius: CGFloat,
                           color: Color = CDSColor.border,
                           width: CGFloat? = nil) -> some View {
        modifier(CDSHairlineModifier(radius: radius, color: color, width: width))
    }
}

private struct CDSTypeModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat?
    let mono: Bool

    func body(content: Content) -> some View {
        let resolved = CDSType.compensated(weight, dark: scheme == .dark)
        return content
            .font(mono
                  ? .system(size: size, weight: resolved, design: .monospaced)
                  : .system(size: size, weight: resolved))
            .tracking(tracking ?? defaultTracking)
    }

    /// 大字号收紧字距，小字号保持中性；不越过 -0.04em 下限。
    private var defaultTracking: CGFloat {
        switch size {
        case 22...: return -0.4
        case 17..<22: return -0.2
        default: return 0
        }
    }
}

private struct CDSShadowModifier: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    let level: CDSElevation

    func body(content: Content) -> some View {
        content.shadow(color: shadowColor, radius: radius, x: 0, y: offset)
    }

    private var shadowColor: Color {
        let dark = scheme == .dark
        switch level {
        case .none: return .clear
        case .sm: return .black.opacity(dark ? 0.40 : 0.07)
        case .md: return .black.opacity(dark ? 0.48 : 0.09)
        case .lg: return .black.opacity(dark ? 0.55 : 0.11)
        case .popover: return .black.opacity(dark ? 0.65 : 0.14)
        }
    }

    private var radius: CGFloat {
        switch level {
        case .none: return 0
        case .sm: return 3
        case .md: return 10
        case .lg: return 18
        case .popover: return 26
        }
    }

    private var offset: CGFloat {
        switch level {
        case .none: return 0
        case .sm: return 1
        case .md: return 3
        case .lg: return 6
        case .popover: return 10
        }
    }
}

private struct CDSHairlineModifier: ViewModifier {
    @Environment(\.displayScale) private var displayScale
    let radius: CGFloat
    let color: Color
    let width: CGFloat?

    func body(content: Content) -> some View {
        content.overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(color, lineWidth: width ?? max(1 / displayScale, 0.5))
        }
    }
}

// MARK: - 兼容层：把旧品牌名映射到 CDS（其余代码无需改动）

extension Color {
    /// 旧品牌色 → 陶土橙
    static let harbor = CDSColor.clay
    static let harborAction = CDSColor.clay
    static let harborSignal = CDSColor.signal
    static let harborWarning = CDSColor.warning
    static let harborFault = CDSColor.fault
}
