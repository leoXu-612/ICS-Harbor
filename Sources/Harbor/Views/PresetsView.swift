import SwiftUI
import HarborCore

struct PresetsView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                PageHeading(title: "游戏预设", subtitle: "按游戏保存；运行参数在环境停止后应用。关联环境须先授权并备份。")
                HStack(alignment: .top, spacing: 16) {
                    presetCard("继承原始配置", subtitle: "默认选项 · 可回退", symbol: "lock.shield", color: .green, body: "使用环境最初备份的参数。存档、键位和插件不参与修改。")
                    presetCard("DXMT 细项", subtitle: "先核对本地能力", symbol: "sparkles.tv", color: .harbor, body: "限帧、强制 SDR 和独占全屏切换。只开放本地组件支持的参数。")
                    presetCard("DXVK 对照", subtitle: "已授权环境 · 对照配置", symbol: "square.3.layers.3d", color: .purple, body: "用于需要另一条图形路径的游戏。不是保证提帧的开关。")
                }
                Surface {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "arrow.triangle.branch").font(.title2).foregroundStyle(Color.harbor)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("保存 ≠ 立即生效").font(.headline)
                            Text("切换引擎配置前，容器必须完全停止。Harbor 会阻止运行中切换；新预设不会自动终止游戏，修改前会保存配置副本。").font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack { Text("逐游戏配置").font(.title3.weight(.semibold)); Spacer(); Text("点击游戏进入右侧预设面板").font(.caption).foregroundStyle(.secondary) }
                if model.games.isEmpty { EmptyState(symbol: "slider.horizontal.3", title: "先关联或安装游戏", message: "有游戏记录后，便可以在详情面板保存专属预设。") }
                VStack(spacing: 0) {
                    ForEach(model.games) { game in
                        Button {
                            model.section = .library; model.selectedGameID = game.id
                        } label: {
                            HStack(spacing: 15) {
                                LocalArtwork(path: game.coverPath).frame(width: 35, height: 47).clipped().clipShape(RoundedRectangle(cornerRadius: 5))
                                VStack(alignment: .leading, spacing: 4) { Text(game.name).font(.system(size: 13, weight: .medium)); Text(model.container(game.containerID)?.name ?? "").font(.caption).foregroundStyle(.secondary) }
                                Spacer(); Pill(title: model.preset(game.id).summary, color: .secondary)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }.padding(.vertical, 12).padding(.horizontal, 16).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        if game.id != model.games.last?.id { Divider().padding(.leading, 64) }
                    }
                }.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    Text("不自动安装 DLL 注入器、画质包或反作弊补丁；也不提供虚假的通用分辨率或画质开关。预设效果需要实际进入游戏验证。").font(.caption).foregroundStyle(.tertiary)
            }.padding(28)
        }
    }
    private func presetCard(_ title: String, subtitle: String, symbol: String, color: Color, body: String) -> some View {
        Surface {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: symbol).font(.system(size: 26, weight: .light)).foregroundStyle(color)
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(color)
                Text(body).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 164, alignment: .topLeading)
        }
    }
}
