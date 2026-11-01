import SwiftUI

// ============================================================================
// CDS 控件层 —— 按钮阶梯、分段胶囊、发丝分隔、状态指示、卡片与字段
// 所有数值来自 open-claude-ui 的令牌层，不在此处另造一套。
// ============================================================================

// MARK: - 按钮

struct CDSButtonStyle: ButtonStyle {
    enum Variant { case primary, secondary, ghost, outline, danger }
    enum Size { case xs, sm, md, lg }

    var variant: Variant = .secondary
    var size: Size = .sm
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        ButtonBody(configuration: configuration, variant: variant, size: size, fullWidth: fullWidth)
    }

    struct ButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let variant: Variant
        let size: Size
        let fullWidth: Bool

        @Environment(\.isEnabled) private var enabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: fontSize, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, hPadding)
                .frame(height: height)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .foregroundStyle(foreground)
                .background(background, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
                .overlay {
                    if variant == .outline {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(CDSColor.border, lineWidth: 1)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
                .opacity(enabled ? (configuration.isPressed ? 0.86 : 1) : 0.45)
                .animation(reduceMotion ? nil : CDSMotion.press, value: configuration.isPressed)
                .animation(reduceMotion ? nil : CDSMotion.snappy, value: hovering)
                .onHover { hovering = $0 }
        }

        private var height: CGFloat {
            switch size { case .xs: 24; case .sm: 28; case .md: 32; case .lg: 38 }
        }

        private var fontSize: CGFloat {
            switch size { case .xs: 11; case .sm: 12; case .md: 13; case .lg: 13.5 }
        }

        private var hPadding: CGFloat {
            switch size { case .xs: 8; case .sm: 10; case .md: 13; case .lg: 16 }
        }

        private var radius: CGFloat {
            switch size { case .xs, .sm: CDSRadius.md; case .md, .lg: CDSRadius.lg }
        }

        private var foreground: Color {
            switch variant {
            case .primary: return CDSColor.textOnAccent
            case .secondary: return CDSColor.textPrimary
            case .ghost, .outline: return CDSColor.textPrimary
            case .danger: return CDSColor.fault
            }
        }

        private var background: Color {
            switch variant {
            case .primary:
                return configuration.isPressed ? CDSColor.clayPressed
                     : hovering ? CDSColor.clayHover : CDSColor.clay
            case .secondary:
                return hovering ? CDSColor.fillSecondaryHover : CDSColor.fillSecondary
            case .ghost:
                return hovering ? CDSColor.fillGhostHover : .clear
            case .outline:
                return hovering ? CDSColor.fillGhostHover : .clear
            case .danger:
                return hovering ? CDSColor.fault.opacity(0.16) : CDSColor.fault.opacity(0.10)
            }
        }
    }
}

extension View {
    func cdsButton(_ variant: CDSButtonStyle.Variant = .secondary,
                   size: CDSButtonStyle.Size = .sm,
                   fullWidth: Bool = false) -> some View {
        buttonStyle(CDSButtonStyle(variant: variant, size: size, fullWidth: fullWidth))
    }
}

/// 旧命名兼容：分区磁贴按压反馈
struct HarborTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.985 : 1)
            .opacity(!enabled ? 0.5 : configuration.isPressed ? 0.85 : 1)
            .animation(CDSMotion.honoring(reducedMotion, CDSMotion.press), value: configuration.isPressed)
    }
}

// MARK: - 表面

struct CDSSurface<Content: View>: View {
    enum Level { case zero, one, two, three
        var color: Color {
            switch self {
            case .zero: CDSColor.surface0
            case .one: CDSColor.surface1
            case .two: CDSColor.surface2
            case .three: CDSColor.surface3
            }
        }
    }

    var level: Level = .two
    var radius: CGFloat = CDSRadius.xl
    var padding: CGFloat = CDSSpacing.roomy
    var bordered = true
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(level.color, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(CDSColor.border, lineWidth: 1)
                }
            }
    }
}

// MARK: - 发丝分隔

struct CDSHairline: View {
    @Environment(\.displayScale) private var scale
    var inset: CGFloat = 0
    var color: Color = CDSColor.borderHairline

    var body: some View {
        Rectangle()
            .fill(color)
            .frame(height: max(1 / scale, 0.5))
            .padding(.leading, inset)
    }
}

// MARK: - 分段控制

struct CDSSegmented<Value: Hashable>: View {
    struct Item: Identifiable {
        let value: Value
        var title: String? = nil
        var symbol: String? = nil
        var id: Value { value }
    }

    @Binding var selection: Value
    var items: [Item]
    var compact = false
    @Namespace private var thumb

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                let active = item.value == selection
                Button {
                    withAnimation(CDSMotion.snappy) { selection = item.value }
                } label: {
                    HStack(spacing: 5) {
                        if let symbol = item.symbol {
                            Image(systemName: symbol).font(.system(size: compact ? 10 : 11, weight: .medium))
                        }
                        if let title = item.title {
                            Text(title).font(.system(size: compact ? 11 : 12, weight: .medium))
                        }
                    }
                    .foregroundStyle(active ? CDSColor.textPrimary : CDSColor.textSecondary)
                    .padding(.horizontal, compact ? 8 : 11)
                    .padding(.vertical, compact ? 3 : 4)
                    .frame(maxWidth: .infinity)
                    .frame(height: compact ? 22 : 26)
                    .background {
                        if active {
                            RoundedRectangle(cornerRadius: CDSRadius.md, style: .continuous)
                                .fill(CDSColor.segmentedThumb)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                                .cdsShadow(.sm)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(CDSColor.segmentedTrack, in: RoundedRectangle(cornerRadius: CDSRadius.lg, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - 状态指示

struct CDSStatusDot: View {
    enum Kind {
        case idle, live, attention, fault
        var color: Color {
            switch self {
            case .idle: CDSColor.textMuted
            case .live: CDSColor.signal
            case .attention: CDSColor.warning
            case .fault: CDSColor.fault
            }
        }
        var period: Double { self == .live ? 1.2 : 2.4 }
    }

    var kind: Kind
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        ZStack {
            if kind == .live {
                Circle()
                    .stroke(kind.color.opacity(phase ? 0 : 0.35), lineWidth: 1)
                    .frame(width: size * 2.6, height: size * 2.6)
                    .scaleEffect(phase ? 1.25 : 0.7)
            }
            Circle()
                .fill(kind.color)
                .frame(width: size, height: size)
                .opacity(kind == .idle ? 0.55 : phase ? 1 : 0.45)
        }
        .frame(width: size * 2.6, height: size * 2.6)
        .onAppear(perform: start)
        .accessibilityHidden(true)
    }

    private func start() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: kind.period).repeatForever(autoreverses: true)) {
            phase = true
        }
    }
}

// MARK: - 胶囊标签

struct CDSPill: View {
    var title: String
    var symbol: String? = nil
    var color: Color = CDSColor.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 9, weight: .semibold)) }
            Text(title).font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(color.opacity(0.11), in: Capsule())
    }
}

// MARK: - 页头

struct CDSPageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CDSSpacing.base) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).cdsType(22, .semibold)
                Text(subtitle).cdsType(12.5).foregroundStyle(CDSColor.textSecondary)
            }
            Spacer(minLength: CDSSpacing.base)
            trailing
        }
    }
}

extension CDSPageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - 小节标题

struct CDSSectionHeader<Trailing: View>: View {
    var title: String
    var subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CDSSpacing.snug) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).cdsType(15, .semibold)
                if !subtitle.isEmpty {
                    Text(subtitle).cdsType(10.5).foregroundStyle(CDSColor.textSecondary)
                }
            }
            Spacer(minLength: CDSSpacing.snug)
            trailing
        }
    }
}

extension CDSSectionHeader where Trailing == EmptyView {
    init(title: String, subtitle: String = "") {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

// MARK: - 空状态

struct CDSIntro: View {
    var symbol: String
    var title: String
    var message: String
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        VStack(spacing: CDSSpacing.base) {
            ZStack {
                RoundedRectangle(cornerRadius: CDSRadius.dialog, style: .continuous)
                    .fill(CDSColor.claySubtle)
                    .frame(width: 56, height: 56)
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(CDSColor.clay)
            }
            VStack(spacing: 6) {
                Text(title).cdsType(16, .semibold)
                Text(message)
                    .cdsType(12.5)
                    .foregroundStyle(CDSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let action {
                Button(action.title, action: action.run)
                    .cdsButton(.primary, size: .md)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - 搜索 / 输入字段

struct CDSField: View {
    var prompt: String
    @Binding var text: String
    var symbol: String? = "magnifyingglass"

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: CDSSpacing.tight) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(focused ? CDSColor.clay : CDSColor.textMuted)
            }
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(CDSColor.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(CDSColor.surface3, in: RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous)
                .strokeBorder(focused ? CDSColor.clay : CDSColor.border,
                              lineWidth: focused ? 1.5 : 1)
        }
        .animation(CDSMotion.honoring(reduceMotion, CDSMotion.press), value: focused)
    }
}

// MARK: - 提示条

struct CDSNotice: View {
    var text: String
    var symbol: String = "info.circle.fill"
    var tone: Color = CDSColor.clay
    var onClose: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: CDSSpacing.tight) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(tone)
                .padding(.top, 1)
            Text(text)
                .cdsType(12)
                .foregroundStyle(CDSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(CDSColor.textMuted)
                .accessibilityLabel("关闭提示")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(tone.opacity(0.08), in: RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous)
                .strokeBorder(tone.opacity(0.18), lineWidth: 1)
        }
    }
}

// MARK: - 可选中卡片

struct CDSCardSurface: ViewModifier {
    var selected: Bool
    var hovering: Bool
    var radius: CGFloat = CDSRadius.xl

    func body(content: Content) -> some View {
        content
            .background(CDSColor.surface2, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(selected ? CDSColor.clay
                                  : hovering ? CDSColor.borderStrong : CDSColor.border,
                                  lineWidth: selected ? 2 : 1)
            }
    }
}

extension View {
    func cdsCard(selected: Bool = false, hovering: Bool = false, radius: CGFloat = CDSRadius.xl) -> some View {
        modifier(CDSCardSurface(selected: selected, hovering: hovering, radius: radius))
    }
}

// MARK: - 滚动边缘渐隐

struct CDSScrollFade<Content: View>: View {
    var fade: CGFloat = 14
    @ViewBuilder var content: Content
    @Environment(\.displayScale) private var scale

    var body: some View {
        content
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: fade)
                    Rectangle().fill(.black)
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: fade)
                }
            }
    }
}

// MARK: - 图标磁贴

struct CDSIconTile: View {
    var symbol: String
    var size: CGFloat = 34
    var tint: Color = CDSColor.clay

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(tint.opacity(0.12))
            Image(systemName: symbol)
                .font(.system(size: size * 0.44, weight: .medium))
                .foregroundStyle(tint)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - 键值行

struct CDSKeyValue: View {
    var label: String
    var value: String
    var mono = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CDSSpacing.snug) {
            Text(label)
                .cdsType(11.5)
                .foregroundStyle(CDSColor.textSecondary)
            Spacer(minLength: CDSSpacing.tight)
            Text(value)
                .cdsType(11.5, .medium, mono: mono)
                .foregroundStyle(CDSColor.textPrimary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}


// MARK: - 进度条

struct CDSProgressBar: View {
    var fraction: Double
    var tint: Color = CDSColor.clay
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(CDSColor.fillSecondary)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue("\(Int(fraction * 100))%")
    }
}

// MARK: - 弹窗表头

struct SheetHeader: View {
    var title: String
    var subtitle: String
    var symbol: String

    var body: some View {
        HStack(alignment: .top, spacing: CDSSpacing.snug) {
            CDSIconTile(symbol: symbol, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).cdsType(19, .semibold)
                Text(subtitle)
                    .cdsType(11.5)
                    .foregroundStyle(CDSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

func sheetHeader(title: String, subtitle: String, symbol: String) -> SheetHeader {
    SheetHeader(title: title, subtitle: subtitle, symbol: symbol)
}

// MARK: - 菜单按钮标签（Menu 不吸收 ButtonStyle，单独给表面）

struct CDSMenuLabel: View {
    var title: String
    var symbol: String = "plus"
    var variant: CDSButtonStyle.Variant = .primary

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            Text(title).font(.system(size: 13, weight: .medium))
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).opacity(0.75)
        }
        .foregroundStyle(variant == .primary ? CDSColor.textOnAccent : CDSColor.textPrimary)
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(variant == .primary ? CDSColor.clay : CDSColor.fillSecondary,
                    in: RoundedRectangle(cornerRadius: CDSRadius.lg, style: .continuous))
    }
}
