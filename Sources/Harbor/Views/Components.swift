import SwiftUI
import HarborCore

extension Color {
    static let harborAction = Color(red: 0.18, green: 0.35, blue: 0.84)
    static let harbor = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.52, green: 0.66, blue: 1, alpha: 1) : NSColor(red: 0.18, green: 0.35, blue: 0.84, alpha: 1) })
    static let harborSignal = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.36, green: 0.81, blue: 0.72, alpha: 1) : NSColor(red: 0.07, green: 0.43, blue: 0.36, alpha: 1) })
    static let harborWarning = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 1, green: 0.80, blue: 0.46, alpha: 1) : NSColor(red: 0.51, green: 0.30, blue: 0.04, alpha: 1) })
    static let harborFault = Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 1, green: 0.60, blue: 0.55, alpha: 1) : NSColor(red: 0.69, green: 0.13, blue: 0.09, alpha: 1) })
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
    @Environment(\.colorSchemeContrast) private var contrast
    var padding: CGFloat = 18
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(padding)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(contrast == .increased ? 0.4 : 0.10), lineWidth: 1) }
    }
}
struct Pill: View {
    var title: String
    var symbol: String? = nil
    var color: Color = .secondary
    var body: some View {
        HStack(spacing: 5) { if let symbol { Image(systemName: symbol) }; Text(title) }
            .font(.system(size: 12, weight: .medium)).foregroundStyle(color)
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
            Text(title).font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-0.4)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
