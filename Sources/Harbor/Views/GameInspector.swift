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
    private var conflict: Bool { container.map { model.hasLibraryConflict($0) } ?? false }
    private var favored: Bool { model.state.favorites.contains(game.id) }
    private var storageName: String {
        if let path = game.installDirectory,
           let volume = model.volumes.first(where: { path.hasPrefix($0.path + "/") }) {
            return volume.name
        }
        return "容器内置目录"
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: CDSSpacing.base) {
                    artwork(width: max(230, geometry.size.width - 32))

                    HStack(alignment: .top, spacing: CDSSpacing.tight) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.name)
                                .cdsType(18, .semibold)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(container?.name ?? "未知环境")
                                .cdsType(10.5)
                                .foregroundStyle(CDSColor.textSecondary)
                        }
                        Spacer(minLength: 4)
                        Button { model.toggleFavorite(game) } label: {
                            Image(systemName: favored ? "star.fill" : "star")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(favored ? CDSColor.clay : CDSColor.textMuted)
                        }
                        .buttonStyle(.plain)
                        .help("切换收藏")
                    }

                    HStack(spacing: 6) {
                        CDSPill(title: game.availability.title,
                                symbol: game.availability == .ready ? "checkmark" : "exclamationmark",
                                color: game.availability == .ready ? CDSColor.signal : CDSColor.warning)
                        Spacer(minLength: 0)
                        Text(Format.bytes(game.sizeOnDisk))
                            .cdsType(10.5, mono: true)
                            .foregroundStyle(CDSColor.textMuted)
                    }

                    Button {
                        if let progress, progress.isObservedRunning {
                            model.focusLaunch(progress.id)
                        } else {
                            model.launchGame(game)
                        }
                    } label: {
                        Label(pending ? "正在启动…"
                              : progress?.isObservedRunning == true ? "显示游戏窗口" : "启动游戏",
                              systemImage: pending ? "hourglass"
                              : progress?.isObservedRunning == true ? "macwindow" : "play.fill")
                    }
                    .cdsButton(.primary, size: .lg, fullWidth: true)
                    .disabled((game.availability != .ready || conflict || model.isWorking || pending)
                              && progress?.isObservedRunning != true)

                    if conflict {
                        Text("此环境存在共用库冲突，暂不能启动。请到运行环境查看原因。")
                            .cdsType(10.5)
                            .foregroundStyle(CDSColor.fault)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("查看库冲突") { model.section = .containers }
                            .cdsButton(.ghost, size: .xs)
                    } else if game.availability == .ready {
                        Text("需要时会自动打开 Steam。启动后可在“启动记录”查看每个阶段。")
                            .cdsType(10)
                            .foregroundStyle(CDSColor.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let progress, progress.isPending {
                        Button("查看启动进度") { model.presentProgress(progress.id) }
                            .cdsButton(.ghost, size: .xs)
                    }

                    CDSHairline()

                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            Image(systemName: "externaldrive")
                                .font(.system(size: 11))
                                .foregroundStyle(CDSColor.textSecondary)
                            Text(storageName).cdsType(11.5, .medium)
                        }
                        Text(game.libraryWindowsPath)
                            .cdsType(10, mono: true)
                            .foregroundStyle(CDSColor.textMuted)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        if let path = game.installDirectory {
                            Button("显示游戏文件", systemImage: "folder") { model.reveal(path) }
                                .cdsButton(.ghost, size: .xs)
                        }
                    }

                    CDSHairline()

                    VStack(alignment: .leading, spacing: 8) {
                        Button("游戏参数…", systemImage: "slider.horizontal.3") { showPresetEditor = true }
                            .cdsButton(.outline, size: .md, fullWidth: true)
                        Text(model.preset(game.id).summary)
                            .cdsType(10.5)
                            .foregroundStyle(CDSColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("显示与性能 · 同步 · 诊断 · 启动行为")
                            .cdsType(9.5)
                            .foregroundStyle(CDSColor.textMuted)
                    }

                    DisclosureGroup("安装信息", isExpanded: $technicalExpanded) {
                        VStack(alignment: .leading, spacing: 7) {
                            CDSKeyValue(label: "Steam App ID", value: game.appID, mono: true)
                            if let build = game.buildID {
                                CDSKeyValue(label: "Build", value: build, mono: true)
                            }
                            CDSKeyValue(label: "配置归属",
                                        value: isLinked
                                        ? (container.map { model.canCustomize($0) } == true
                                           ? "关联 · 已授权图形参数" : "关联 · 保留原配置")
                                        : "Harbor 托管")
                            Text("安装状态不等于兼容性或帧率保证。")
                                .cdsType(9.5)
                                .foregroundStyle(CDSColor.textMuted)
                        }
                        .padding(.top, 8)
                    }
                    .font(.system(size: 12, weight: .medium))
                }
                .frame(width: max(230, geometry.size.width - 32), alignment: .leading)
                .padding(CDSSpacing.base)
            }
        }
        .background(CDSColor.surface0)
        .sheet(isPresented: $showPresetEditor) { GamePresetEditor(model: model, game: game) }
    }

    private func artwork(width: CGFloat) -> some View {
        LocalArtwork(path: game.heroPath ?? game.coverPath)
            .frame(width: width, height: 104)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous)
                    .strokeBorder(CDSColor.border, lineWidth: 1)
            }
    }
}
