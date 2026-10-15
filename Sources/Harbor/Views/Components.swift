import SwiftUI
import HarborCore

extension Color {
    static let harbor = Color(red: 0.204, green: 0.412, blue: 0.937)
    static let harborSignal = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.31, green: 0.80, blue: 0.73, alpha: 1) : NSColor(red: 0.08, green: 0.49, blue: 0.45, alpha: 1) })
    static let harborWarning = Color.orange
    static let harborFault = Color.red
}
enum HarborMotion {
    static func feedback(reduced: Bool) -> Animation { reduced ? .easeOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 1) }
}
struct HarborTileButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reducedMotion ? 0.985 : 1)
            .opacity(!enabled ? 0.55 : configuration.isPressed ? 0.83 : 1)
            .animation(HarborMotion.feedback(reduced: reducedMotion), value: configuration.isPressed)
    }
}

struct Surface<Content: View>: View {
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding)
            .background(reducedTransparency ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.regularMaterial), in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.primary.opacity(contrast == .increased ? 0.35 : 0.07), lineWidth: 1) }
    }
}
struct Pill: View {
    var title: String
    var symbol: String? = nil
    var color: Color = .secondary
    var body: some View {
        HStack(spacing: 5) { if let symbol { Image(systemName: symbol) }; Text(title) }
            .font(.system(size: 11, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(color.opacity(0.10), in: Capsule())
    }
}
struct PageHeading: View {
    var eyebrow: String = ""
    var title: String
    var subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !eyebrow.isEmpty { Text(eyebrow).font(.caption).foregroundStyle(.secondary) }
            Text(title).font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-0.35)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
}
struct LocalArtwork: View {
    var path: String?
    var symbol: String = "gamecontroller"
    var body: some View {
        if let path, let image = ArtworkCache.image(path) {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            ZStack {
                Color.harbor.opacity(0.10)
                Image(systemName: symbol).font(.system(size: 44, weight: .light)).foregroundStyle(Color.harbor.opacity(0.65))
            }
        }
    }
}

@MainActor private enum ArtworkCache {
    static let storage = NSCache<NSString, NSImage>()
    static func image(_ path: String) -> NSImage? {
        storage.countLimit = 80; storage.totalCostLimit = 64 * 1024 * 1024
        if let cached = storage.object(forKey: path as NSString) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        storage.setObject(image, forKey: path as NSString)
        return image
    }
}
struct EmptyState: View {
    var symbol: String; var title: String; var message: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 42, weight: .light)).foregroundStyle(Color.harbor)
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 440)
        }.frame(maxWidth: .infinity).padding(.vertical, 56)
    }
}
