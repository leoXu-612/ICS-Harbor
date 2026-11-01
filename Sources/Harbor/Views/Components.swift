import SwiftUI
import AppKit
import HarborCore

// ============================================================================
// 兼容适配层（0.5.x）
// 旧视图仍调用 Surface / Pill / PageHeading / EmptyState 等名字；
// 这里把它们转发到 CDS 控件层，换取全站一致的表面、排版与动效。
// 品牌色 harbor / harborAction / 状态色由 CDSTokens.swift 统一给出。
// ============================================================================

enum HarborMotion {
    static func feedback(reduced: Bool) -> Animation {
        reduced ? .easeOut(duration: 0.1) : CDSMotion.snappy
    }
}

struct Surface<Content: View>: View {
    var padding: CGFloat = CDSSpacing.roomy
    @ViewBuilder var content: Content

    var body: some View {
        CDSSurface(level: .two, radius: CDSRadius.xl, padding: padding) { content }
    }
}

struct Pill: View {
    var title: String
    var symbol: String? = nil
    var color: Color = CDSColor.textSecondary

    var body: some View {
        CDSPill(title: title, symbol: symbol, color: color)
    }
}

struct PageHeading: View {
    var eyebrow: String = ""
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).cdsType(24, .semibold)
            Text(subtitle)
                .cdsType(12.5)
                .foregroundStyle(CDSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
                LinearGradient(colors: [CDSColor.claySubtle, CDSColor.fillTertiary],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(CDSColor.clay.opacity(0.55))
            }
        }
    }
}

@MainActor private enum ArtworkCache {
    static let storage = NSCache<NSString, NSImage>()
    static func image(_ path: String) -> NSImage? {
        storage.countLimit = 80
        storage.totalCostLimit = 64 * 1024 * 1024
        if let cached = storage.object(forKey: path as NSString) { return cached }
        guard let image = NSImage(contentsOfFile: path) else { return nil }
        storage.setObject(image, forKey: path as NSString)
        return image
    }
}

struct EmptyState: View {
    var symbol: String
    var title: String
    var message: String

    var body: some View {
        CDSIntro(symbol: symbol, title: title, message: message)
    }
}
