import SwiftUI
import HarborCore

struct GameInspector: View {
    @Bindable var model: AppModel
    var game: GameRecord
    @State private var showPresetEditor = false
    @State private var technicalExpanded = false
    private var container: ContainerRecord? { model.container(game.containerID) }
    private var isLinked: Bool { container?.origin != .managed }
    private var progress: LaunchProgress? { model.progress(for: game) }
    private var pending: Bool { model.pendingLaunch(in: game.containerID) != nil }
    private var storageName: String {
        if let path = game.installDirectory, let volume = model.volumes.first(where: { path.hasPrefix($0.path + "/") }) { return volume.name }
        return "容器内置目录"
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    LocalArtwork(path: game.heroPath ?? game.coverPath)
                        .frame(width: max(230, geometry.size.width - 36), height: 110).clipped().clipShape(RoundedRectangle(cornerRadius: 11))
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(game.name).font(.system(size: 19, weight: .semibold, design: .rounded)).fixedSize(horizontal: false, vertical: true)
                            Text(container?.name ?? "未知环境").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        Button { model.toggleFavorite(game) } label: { Image(systemName: model.state.favorites.contains(game.id) ? "star.fill" : "star") }
                            .buttonStyle(.borderless).foregroundStyle(model.state.favorites.contains(game.id) ? .orange : .secondary).help("切换收藏")
                    }
                    HStack {
                        Pill(title: game.availability.title, symbol: game.availability == .ready ? "checkmark.circle" : "externaldrive.badge.exclamationmark", color: game.availability == .ready ? .harborSignal : .orange)
                        Spacer()
                        Text(Format.bytes(game.sizeOnDisk)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Button {
                        if let progress, progress.isObservedRunning { model.focusLaunch(progress.id) } else { model.launchGame(game) }
                    } label: {
                        Label(pending ? "正在启动…" : progress?.isObservedRunning == true ? "显示游戏窗口" : "启动游戏",
                              systemImage: pending ? "hourglass" : progress?.isObservedRunning == true ? "macwindow" : "play.fill")
                            .frame(maxWidth: .infinity).padding(.vertical, 5)
                    }.buttonStyle(.borderedProminent).controlSize(.large).disabled(game.availability != .ready || model.isWorking || pending)
                    if let progress, progress.isPending {
                        Button("查看启动进度") { model.presentProgress(progress.id) }.buttonStyle(.link).font(.caption)
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 11) {
                        Label(storageName, systemImage: "externaldrive").font(.callout.weight(.medium))
                        Text(game.libraryWindowsPath).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                        if let path = game.installDirectory { Button("显示游戏文件", systemImage: "folder") { model.reveal(path) }.buttonStyle(.link).font(.caption) }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 9) {
                        Button("游戏参数…", systemImage: "slider.horizontal.3") { showPresetEditor = true }.controlSize(.large)
                        Text(model.preset(game.id).summary).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Text("显示与性能 · 同步 · 诊断 · 启动行为").font(.caption2).foregroundStyle(.tertiary)
                    }
                    DisclosureGroup("安装信息", isExpanded: $technicalExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            detail("Steam App ID", game.appID)
                            if let build = game.buildID { detail("Build", build) }
                            detail("配置归属", isLinked ? (container.map { model.canCustomize($0) } == true ? "关联 · 已授权图形参数" : "关联 · 保留原配置") : "Harbor 托管")
                            Text("安装状态不等于兼容性或帧率保证。").font(.caption2).foregroundStyle(.tertiary)
                        }.padding(.top, 10)
                    }.font(.callout.weight(.medium))
                }.frame(width: max(230, geometry.size.width - 36), alignment: .leading).padding(18)
            }
        }.sheet(isPresented: $showPresetEditor) { GamePresetEditor(model: model, game: game) }
    }
    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) { Text(label).foregroundStyle(.secondary); Spacer(); Text(value).textSelection(.enabled) }.font(.caption)
    }
}
