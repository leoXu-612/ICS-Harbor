import SwiftUI
import HarborCore

struct LibraryView: View {
    @Bindable var model: AppModel
    @AppStorage("libraryLayout") private var layout = "grid"

    private var filterBinding: Binding<Bool> { $model.favoritesOnly }
    private var layoutBinding: Binding<String> { $layout }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CDSSpacing.roomy) {
                CDSPageHeader(
                    title: "游戏库",
                    subtitle: model.lastRefreshedAt == nil && model.isRefreshing
                        ? "正在读取本机 Steam 清单…"
                        : "\(model.readyCount) 款已安装 · 游戏文件保留原位"
                )

                if !model.conflictingLibraries.isEmpty {
                    LibraryConflictNotice { model.section = .containers }
                }

                TaskHint(title: "选中游戏，在右侧启动",
                         message: "不必先打开 Steam。图形与启动设置在游戏详情的“游戏参数”中。",
                         symbol: "cursorarrow.click",
                         actionTitle: "管理 Steam") { model.section = .containers }

                HStack(alignment: .center, spacing: CDSSpacing.base) {
                    Text(model.favoritesOnly ? "收藏" : "所有游戏")
                        .cdsType(15, .semibold)
                    Spacer(minLength: CDSSpacing.base)

                    CDSSegmented(selection: filterBinding, items: [
                        .init(value: false, title: "全部"),
                        .init(value: true, title: "收藏")
                    ])
                    .frame(width: 128)

                    CDSSegmented(selection: layoutBinding, items: [
                        .init(value: "grid", symbol: "square.grid.2x2"),
                        .init(value: "list", symbol: "list.bullet")
                    ])
                    .frame(width: 72)
                    .accessibilityLabel("游戏库布局")
                    .help("切换网格或列表")
                }

                if model.offlineCount > 0 {
                    offlineBanner
                }

                if model.state.containers.isEmpty {
                    CDSSurface(padding: CDSSpacing.section) {
                        VStack(spacing: CDSSpacing.roomy) {
                            CDSIntro(symbol: "shippingbox",
                                     title: "添加第一个运行环境",
                                     message: "可以关联已有的 Wine Steam，也可以创建独立环境。原有游戏和存档留在原处。")
                            HStack(spacing: CDSSpacing.tight) {
                                Button("关联已有环境") { model.linkContainer() }.cdsButton(.outline, size: .md)
                                Button("创建游戏环境") { model.presentCreate(.steam) }.cdsButton(.primary, size: .md)
                            }
                            .padding(.bottom, 8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else if model.games.isEmpty && model.isRefreshing {
                    loadingState
                } else if model.filteredGames.isEmpty {
                    CDSIntro(
                        symbol: "magnifyingglass",
                        title: model.favoritesOnly && model.search.isEmpty ? "还没有收藏"
                            : model.search.isEmpty ? "这里还没有游戏" : "没有匹配的游戏",
                        message: model.favoritesOnly && model.search.isEmpty ? "选择游戏后点星标，即可在这里找到它。"
                            : model.search.isEmpty ? "先在该环境的 Steam 中安装游戏，然后刷新。"
                            : "试试另一段名称，或输入 Steam App ID。"
                    )
                } else if layout == "list" {
                    VStack(spacing: 2) {
                        ForEach(model.filteredGames) { game in
                            GameListRow(model: model, game: game)
                        }
                    }
                    .padding(6)
                    .background(CDSColor.surface2, in: RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous)
                            .strokeBorder(CDSColor.border, lineWidth: 1)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 168, maximum: 216), spacing: CDSSpacing.base)],
                              spacing: CDSSpacing.roomy) {
                        ForEach(model.filteredGames) { game in
                            GameCard(model: model, game: game)
                        }
                    }
                }

                if !model.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(model.warnings.filter { !$0.contains("共用") && !$0.contains("同一游戏库") }, id: \.self) { warning in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "info.circle").font(.system(size: 10))
                                Text(warning).cdsType(10.5).fixedSize(horizontal: false, vertical: true)
                            }
                            .foregroundStyle(CDSColor.textMuted)
                        }
                    }
                }

                footerLine
            }
            .padding(CDSSpacing.page)
            .frame(maxWidth: 1200, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CDSColor.surface1)
        .searchable(text: $model.search, placement: .toolbar, prompt: "搜索游戏或 App ID")
    }

    // MARK: 局部

    private var offlineBanner: some View {
        HStack(spacing: CDSSpacing.snug) {
            CDSIconTile(symbol: "externaldrive.badge.exclamationmark", size: 32, tint: CDSColor.warning)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(model.offlineCount) 款游戏的磁盘未连接").cdsType(12, .medium)
                Text("连接原磁盘后刷新，不会触发重新下载。").cdsType(10.5).foregroundStyle(CDSColor.textSecondary)
            }
            Spacer(minLength: CDSSpacing.tight)
            Button("查看磁盘") { model.section = .containers }.cdsButton(.outline, size: .sm)
        }
        .padding(.horizontal, CDSSpacing.snug)
        .padding(.vertical, 10)
        .background(CDSColor.warning.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous)
                .strokeBorder(CDSColor.warning.opacity(0.18), lineWidth: 1)
        }
    }

    private var loadingState: some View {
        VStack(spacing: CDSSpacing.base) {
            ProgressView().controlSize(.large).tint(CDSColor.clay)
            Text("正在读取游戏库").cdsType(14, .semibold)
            Text("等待磁盘返回清单。不会移动游戏，也不会重新下载。")
                .cdsType(11.5).foregroundStyle(CDSColor.textSecondary)
            Text("若 macOS 弹出磁盘访问确认，请允许 Harbor 访问已绑定的外置盘。")
                .cdsType(10.5).foregroundStyle(CDSColor.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 72)
    }

    private var footerLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "internaldrive").font(.system(size: 9))
            Text("本机 Steam 清单").cdsType(10)
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.mini)
                Text("正在读取磁盘…").cdsType(10)
            } else if let date = model.lastRefreshedAt {
                Text("更新于 \(date.formatted(date: .omitted, time: .shortened))")
                    .cdsType(10, mono: true)
            }
        }
        .foregroundStyle(CDSColor.textMuted)
        .padding(.top, 2)
    }
}

// MARK: - 卡片

private struct GameCard: View {
    @Bindable var model: AppModel
    var game: GameRecord

    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var hovering = false
    @FocusState private var keyboardFocused: Bool

    private var selected: Bool { model.selectedGameID == game.id }
    private var progress: LaunchProgress? { model.progress(for: game) }

    private var status: (text: String, dot: CDSStatusDot.Kind) {
        if progress?.isPending == true { return ("正在启动", .live) }
        if progress?.isObservedRunning == true { return ("已检测到窗口", .live) }
        switch game.availability {
        case .ready: return (game.availability.title, .live)
        case .offline, .incomplete, .missing: return (game.availability.title, .attention)
        }
    }

    var body: some View {
        Button { model.selectedGameID = game.id } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    LocalArtwork(path: game.coverPath)
                        .frame(height: 198)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    if model.state.favorites.contains(game.id) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(.black.opacity(0.38), in: Circle())
                            .padding(8)
                    }
                }
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: CDSRadius.xl,
                                                  topTrailingRadius: CDSRadius.xl,
                                                  style: .continuous))

                VStack(alignment: .leading, spacing: 6) {
                    Text(game.name)
                        .cdsType(12.5, .semibold)
                        .lineLimit(2)
                        .frame(height: 34, alignment: .topLeading)
                        .help(game.name)
                    HStack(spacing: 5) {
                        CDSStatusDot(kind: status.dot, size: 5).frame(width: 10)
                        Text(status.text)
                            .cdsType(10)
                            .foregroundStyle(CDSColor.textSecondary)
                        Spacer(minLength: 0)
                        if game.sizeOnDisk > 0 {
                            Text(Format.bytes(game.sizeOnDisk))
                                .cdsType(9.5, mono: true)
                                .foregroundStyle(CDSColor.textMuted)
                        }
                    }
                }
                .padding(.horizontal, 11)
                .padding(.top, 9)
                .padding(.bottom, 10)
            }
            .background(CDSColor.surface2)
            .clipShape(RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous)
                    .strokeBorder(selected || keyboardFocused ? CDSColor.clay
                                  : hovering ? CDSColor.borderStrong : CDSColor.border,
                                  lineWidth: selected || keyboardFocused ? 2 : 1)
                    .allowsHitTesting(false)
            }
            .cdsShadow(hovering && !selected ? .md : .none)
            .contentShape(RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous))
        }
        .buttonStyle(HarborTileButtonStyle())
        .focused($keyboardFocused)
        .onHover { hovering = $0 }
        .animation(CDSMotion.honoring(reducedMotion, CDSMotion.snappy), value: hovering)
        .animation(CDSMotion.honoring(reducedMotion, CDSMotion.snappy), value: selected)
        .accessibilityLabel("\(game.name)，\(game.availability.title)，显示详情")
        .contextMenu {
            Button("启动游戏", systemImage: "play.fill") { model.launchGame(game) }
                .disabled(game.availability != .ready || model.pendingLaunch(in: game.containerID) != nil)
            Button(model.state.favorites.contains(game.id) ? "取消收藏" : "加入收藏", systemImage: "star") {
                model.toggleFavorite(game)
            }
            if let path = game.installDirectory {
                Button("显示安装目录", systemImage: "folder") { model.reveal(path) }
            }
        }
    }
}

// MARK: - 列表行

private struct GameListRow: View {
    @Bindable var model: AppModel
    var game: GameRecord
    @State private var hovering = false

    private var selected: Bool { model.selectedGameID == game.id }

    var body: some View {
        Button { model.selectedGameID = game.id } label: {
            HStack(spacing: CDSSpacing.snug) {
                LocalArtwork(path: game.coverPath)
                    .frame(width: 34, height: 45)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: CDSRadius.md, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CDSRadius.md, style: .continuous)
                            .strokeBorder(CDSColor.border, lineWidth: 0.5)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    Text(game.name).cdsType(12.5, .medium).lineLimit(1)
                    Text(model.container(game.containerID)?.name ?? "")
                        .cdsType(10.5).foregroundStyle(CDSColor.textMuted).lineLimit(1)
                }

                Spacer(minLength: CDSSpacing.tight)

                CDSPill(title: game.availability.title,
                        symbol: game.availability == .ready ? "checkmark" : "exclamationmark",
                        color: game.availability == .ready ? CDSColor.signal : CDSColor.warning)

                Text(Format.bytes(game.sizeOnDisk))
                    .cdsType(10.5, mono: true)
                    .foregroundStyle(CDSColor.textSecondary)
                    .frame(width: 64, alignment: .trailing)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CDSColor.textMuted)
            }
            .padding(.horizontal, 10)
            .frame(height: 58)
            .background(selected ? CDSColor.claySubtle
                         : hovering ? CDSColor.fillGhostHover : .clear,
                        in: RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(game.name)，\(game.availability.title)，显示详情")
    }
}
