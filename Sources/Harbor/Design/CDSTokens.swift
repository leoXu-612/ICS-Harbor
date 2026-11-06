import SwiftUI
import AppKit

// Harbor's semantic colors resolve against the current window appearance.
enum CDSColor {
    // Sidebar, canvas, grouped content, controls, and floating panels.
    static let surface0 = dynamic(light: 0xE8EFF4, dark: 0x0C1723)
    static let surface1 = dynamic(light: 0xF5F8FA, dark: 0x101D2A)
    static let surface2 = dynamic(light: 0xFFFFFF, dark: 0x19293A)
    static let surface3 = dynamic(light: 0xF0F5F8, dark: 0x223447)
    static let surfacePopover = dynamic(light: 0xFFFFFF, dark: 0x283B4E)

    static let marine = dynamic(light: 0x095C80, dark: 0x90D9FA)
    static let marineHover = dynamic(light: 0x074E71, dark: 0xAFE6FF)
    static let marinePressed = dynamic(light: 0x073F5C, dark: 0x70C1E8)
    static let selectedRow = dynamic(light: 0xD5EAF4, dark: 0x213E52)
    static let marineSubtle = dynamicAlpha(light: 0x247EA9, lightAlpha: 0.11,
                                           dark: 0x83D1FA, darkAlpha: 0.12)

    // Older scenes use the clay names for the app tint, labels, and selections.
    static let clay = marine
    static let clayHover = marineHover
    static let clayPressed = marinePressed
    static let claySubtle = marineSubtle

    static let textPrimary = dynamic(light: 0x142636, dark: 0xEDF5FA)
    static let textSecondary = dynamic(light: 0x384F61, dark: 0xC3D3E1)
    static let textMuted = dynamic(light: 0x465F71, dark: 0xA3B9CA)
    static let textOnAccent = dynamic(light: 0xFFFFFF, dark: 0x0A2232)

    static let border = dynamicAlpha(light: 0x264B65, lightAlpha: 0.22,
                                     dark: 0xB5D8F1, darkAlpha: 0.20)
    static let borderStrong = dynamicAlpha(light: 0x264B65, lightAlpha: 0.44,
                                           dark: 0xB5D8F1, darkAlpha: 0.40)
    static let borderHairline = dynamicAlpha(light: 0x264B65, lightAlpha: 0.15,
                                             dark: 0xB5D8F1, darkAlpha: 0.14)

    static let fillGhostHover = dynamicAlpha(light: 0x264B65, lightAlpha: 0.07,
                                             dark: 0xB5D8F1, darkAlpha: 0.07)
    static let fillGhostSelected = selectedRow
    static let fillSecondary = dynamicAlpha(light: 0x264B65, lightAlpha: 0.09,
                                            dark: 0xB5D8F1, darkAlpha: 0.10)
    static let fillSecondaryHover = dynamicAlpha(light: 0x264B65, lightAlpha: 0.14,
                                                 dark: 0xB5D8F1, darkAlpha: 0.16)
    static let fillTertiary = dynamicAlpha(light: 0x264B65, lightAlpha: 0.04,
                                           dark: 0xB5D8F1, darkAlpha: 0.05)

    static let segmentedTrack = fillTertiary
    static let segmentedThumb = marine

    // Green denotes a healthy or running service; blue denotes interaction.
    static let signal = dynamic(light: 0x216345, dark: 0x8AD7AE)
    static let warning = dynamic(light: 0x794A10, dark: 0xF1C581)
    static let fault = dynamic(light: 0xA02F3E, dark: 0xFFA7AA)
    static let info = marine
    static let scrim = dynamicAlpha(light: 0x081522, lightAlpha: 0.28,
                                    dark: 0x040C15, darkAlpha: 0.56)

    // MARK: 构造工具

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        dynamicAlpha(light: light, lightAlpha: 1, dark: dark, darkAlpha: 1)
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

// MARK: - SF typography

enum CDSType {
    // Keep the same SF hierarchy in either appearance, especially for small labels.
    static func compensated(_ weight: Font.Weight, dark: Bool) -> Font.Weight { weight }
}

extension View {
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
    let size: CGFloat
    let weight: Font.Weight
    let tracking: CGFloat?
    let mono: Bool

    func body(content: Content) -> some View {
        content
            .font(mono
                  ? .system(size: size, weight: weight, design: .monospaced)
                  : .system(size: size, weight: weight))
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
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 兼容层：把旧品牌名映射到 CDS（其余代码无需改动）

extension Color {
    static let harbor = CDSColor.marine
    static let harborAction = CDSColor.marine
    static let harborSignal = CDSColor.signal
    static let harborWarning = CDSColor.warning
    static let harborFault = CDSColor.fault
}
