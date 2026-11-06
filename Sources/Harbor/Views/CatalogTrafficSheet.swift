import SwiftUI
import HarborCore

/// Keep the flow diagram usable even when opened from the narrow inspector.
struct CatalogTrafficSheet: View {
    let model: AppModel
    let application: WindowsApplication?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var monitor = TrafficMonitor()
    @State private var paused = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(application?.name ?? "所有环境的运行概览").cdsType(17, .semibold)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(CDSSpacing.base)
            Divider()
            GeometryReader { geometry in
                ScrollView {
                    TrafficFlowView(monitor: monitor, applications: model.applications,
                                    application: application, paused: $paused,
                                    viewport: geometry.frame(in: .global))
                        .padding(CDSSpacing.base)
                }
            }
        }
        .frame(width: 640, height: 520)
        .background(CDSColor.surface1)
        .onAppear { update() }
        .onChange(of: paused) { update() }
        .onChange(of: phase) { update() }
        .onChange(of: model.applications) { update() }
        .onChange(of: model.state.containers) { update() }
        .onDisappear { monitor.stop() }
    }

    private func update() {
        if !paused && phase == .active {
            monitor.start(containers: model.state.containers, applications: model.applications)
        } else {
            monitor.stop()
        }
    }
}
