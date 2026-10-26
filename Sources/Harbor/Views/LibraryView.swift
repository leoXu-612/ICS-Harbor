import SwiftUI
import HarborCore

struct LibraryView: View {
    @Bindable var model: AppModel
    @AppStorage("libraryLayout") private var layout = "grid"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeading(title: "游戏库", subtitle: model.lastRefreshedAt == nil && model.isRefreshing ? "正在读取本机 Steam 清单…" : "\(model.readyCount) 款已安装 · 游戏文件保留原位")
                if !model.conflictingLibraries.isEmpty { LibraryConflictNotice { model.section = .containers } }
                TaskHint(title: "选中游戏，在右侧启动", message: "不必先打开 Steam。图形与启动设置在游戏详情的“游戏参数”中。", symbol: "cursorarrow.click", actionTitle: "管理 Steam") { model.section = .containers }
                HStack(alignment: .center) {
                    Text(model.favoritesOnly ? "收藏" : "所有游戏").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Picker("筛选游戏", selection: $model.favoritesOnly) { Text("全部").tag(false); Text("收藏").tag(true) }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 132).accessibilityLabel("筛选游戏")
                    Picker("游戏库布局", selection: $layout) {
                        Image(systemName: "square.grid.2x2").tag("grid")
                        Image(systemName: "list.bullet").tag("list")
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 78).accessibilityLabel("游戏库布局").help("切换网格或列表")
                }
                if model.offlineCount > 0 {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.badge.exclamationmark").foregroundStyle(.orange).font(.title2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(model.offlineCount) 款游戏的磁盘未连接").font(.callout.weight(.semibold))
                            Text("连接原磁盘后刷新，不会触发重新下载。").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Button("查看磁盘") { model.section = .containers }
                    }.padding(14).background(.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                }
                if model.state.containers.isEmpty {
                    Surface {
                        VStack(spacing: 16) {
                            EmptyState(symbol: "shippingbox", title: "添加第一个运行环境", message: "可以关联已有的 Wine Steam，也可以创建独立环境。原有游戏和存档留在原处。")
                            HStack { Button("关联已有环境") { model.linkContainer() }; Button("创建游戏环境") { model.presentCreate(.steam) }.buttonStyle(.borderedProminent).tint(.harborAction) }.controlSize(.large).padding(.bottom, 18)
                        }
                    }
                } else if model.games.isEmpty && model.isRefreshing {
                    VStack(spacing: 14) {
                        ProgressView().controlSize(.large)
                        Text("正在读取游戏库").font(.headline)
                        Text("等待磁盘返回清单。不会移动游戏，也不会重新下载。").font(.callout).foregroundStyle(.secondary)
                        Text("若 macOS 弹出磁盘访问确认，请允许 Harbor 访问已绑定的外置盘。").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 80)
                } else if model.filteredGames.isEmpty {
                    EmptyState(symbol: "magnifyingglass", title: model.favoritesOnly && model.search.isEmpty ? "还没有收藏" : model.search.isEmpty ? "这里还没有游戏" : "没有匹配的游戏", message: model.favoritesOnly && model.search.isEmpty ? "选择游戏后点星标，即可在这里找到它。" : model.search.isEmpty ? "先在该环境的 Steam 中安装游戏，然后刷新。" : "试试另一段名称，或输入 Steam App ID。")
                } else if layout == "list" {
                    VStack(spacing: 2) { ForEach(model.filteredGames) { game in GameListRow(model: model, game: game) } }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 18)], spacing: 24) {
                        ForEach(model.filteredGames) { game in GameCard(model: model, game: game) }
                    }
                }
                if !model.warnings.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(model.warnings.filter { !$0.contains("共用") && !$0.contains("同一游戏库") }, id: \.self) { Label($0, systemImage: "info.circle").font(.system(size: 12)).foregroundStyle(.secondary) }
                    }
                }
                HStack {
                    Label("本机 Steam 清单", systemImage: "internaldrive").font(.caption2)
                    Spacer()
                    if model.isRefreshing { ProgressView().controlSize(.mini); Text("正在读取磁盘…").font(.caption2) }
                    else if let date = model.lastRefreshedAt { Text("更新于 \(date.formatted(date: .omitted, time: .shortened))").font(.caption2).monospacedDigit() }
                }.foregroundStyle(.tertiary).padding(.top, 4)
            }.padding(28).frame(maxWidth: .infinity, alignment: .topLeading)
        }.searchable(text: $model.search, placement: .toolbar, prompt: "搜索游戏或 App ID")
    }
}

private struct GameCard: View {
    @Bindable var model: AppModel
    var game: GameRecord
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var hovering = false
    @FocusState private var keyboardFocused: Bool
    private var selected: Bool { model.selectedGameID == game.id }
    private var progress: LaunchProgress? { model.progress(for: game) }
    var body: some View {
        Button { model.selectedGameID = game.id } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    LocalArtwork(path: game.coverPath).frame(height: 202).clipped()
                    if model.state.favorites.contains(game.id) {
                        Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.white).padding(7).background(.black.opacity(0.65), in: Circle()).padding(9)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(game.name).font(.system(size: 14, weight: .semibold)).lineLimit(2).frame(height: 38, alignment: .topLeading).help(game.name)
                    HStack(spacing: 5) {
                        Image(systemName: progress?.isPending == true ? "hourglass" : progress?.isObservedRunning == true ? "play.circle.fill" : "externaldrive")
                            .foregroundStyle(progress?.isPending == true ? Color.harbor : game.availability == .ready ? .harborSignal : .orange)
                        Text(progress?.isPending == true ? "正在启动" : progress?.isObservedRunning == true ? "已检测到窗口" : game.availability.title).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").foregroundStyle(.secondary).accessibilityHidden(true)
                    }.font(.system(size: 12))
                }.padding(12)
            }
            .background(selected ? Color.harbor.opacity(0.08) : Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(selected || keyboardFocused ? Color.harbor : Color.primary.opacity(contrast == .increased ? 0.4 : hovering ? 0.23 : 0.08), lineWidth: selected || keyboardFocused ? 2 : 1) }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(HarborTileButtonStyle())
            .focused($keyboardFocused)
            .onHover { hovering = $0 }
            .animation(HarborMotion.feedback(reduced: reducedMotion), value: selected)
            .accessibilityLabel("\(game.name)，\(game.availability.title)，显示详情")
            .contextMenu {
                Button("启动游戏", systemImage: "play.fill") { model.launchGame(game) }.disabled(game.availability != .ready || model.pendingLaunch(in: game.containerID) != nil)
                Button(model.state.favorites.contains(game.id) ? "取消收藏" : "加入收藏", systemImage: "star") { model.toggleFavorite(game) }
                if let path = game.installDirectory { Button("显示安装目录", systemImage: "folder") { model.reveal(path) } }
            }
    }
}

private struct GameListRow: View {
    @Bindable var model: AppModel
    var game: GameRecord
    var body: some View {
        Button { model.selectedGameID = game.id } label: {
            HStack(spacing: 12) {
                LocalArtwork(path: game.coverPath).frame(width: 38, height: 49).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 4) {
                    Text(game.name).font(.callout.weight(.medium)).lineLimit(1)
                    Text(model.container(game.containerID)?.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(game.availability.title).font(.caption).foregroundStyle(.secondary)
                Text(Format.bytes(game.sizeOnDisk)).font(.caption.monospacedDigit()).foregroundStyle(.tertiary).frame(width: 65, alignment: .trailing)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }.padding(10).background(model.selectedGameID == game.id ? Color.harbor.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }.buttonStyle(HarborTileButtonStyle()).accessibilityLabel("\(game.name)，\(game.availability.title)，显示详情")
    }
}
