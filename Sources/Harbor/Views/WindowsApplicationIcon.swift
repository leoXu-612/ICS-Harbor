import SwiftUI
import HarborCore

struct WindowsApplicationIcon: View {
    let executablePath: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                Image(systemName: "macwindow").resizable().scaledToFit().padding(5).foregroundStyle(Color.harbor)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
        .task(id: executablePath) {
            image = nil
            let path = executablePath
            let data = await Task.detached(priority: .utility) {
                guard let executable = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { return Data?.none }
                return WindowsExecutableIcon.iconData(in: executable)
            }.value
            guard !Task.isCancelled else { return }
            image = data.flatMap(NSImage.init(data:))
        }
    }
}
