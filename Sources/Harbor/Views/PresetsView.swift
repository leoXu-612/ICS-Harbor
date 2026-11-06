import SwiftUI
import HarborCore

struct PresetsView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CDSSpacing.section) {
                CDSPageHeader(title: "游戏预设",
                              subtitle: "按游戏保存；运行参数在环境停止后应用。关联环境须先授权并备份。")

                CDSSurface(level: .two, radius: CDSRadius.xl, padding: 0) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0, alignment: .topLeading),
                                             count: 3),
                              spacing: 0) {
                        presetColumn("继承原始配置", subtitle: "默认选项 · 可回退",
                                     symbol: "lock.shield", tint: CDSColor.signal,
                                     body: "使用环境最初备份的参数。存档、键位和插件不参与修改。")
                        presetColumn("DXMT 细项", subtitle: "先核对本地能力",
                                     symbol: "sparkles.tv", tint: CDSColor.clay,
                                     body: "限帧、强制 SDR 和独占全屏切换。只开放本地组件支持的参数。")
                        presetColumn("DXVK 对照", subtitle: "已授权环境 · 对照配置",
                                     symbol: "square.3.layers.3d", tint: CDSColor.info,
                                     body: "用于需要另一条图形路径的游戏。不是保证提帧的开关。")
                    }
                    .overlay { columnRule }
                }

                CDSSurface(level: .two, radius: CDSRadius.xl, padding: CDSSpacing.base) {
                    HStack(alignment: .top, spacing: CDSSpacing.snug) {
                        CDSIconTile(symbol: "arrow.triangle.branch", size: 32)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("保存 ≠ 立即生效").cdsType(12.5, .semibold)
                            Text("切换引擎配置前，容器必须完全停止。Harbor 会阻止运行中切换；新预设不会自动终止游戏，修改前会保存配置副本。")
                                .cdsType(11)
                                .foregroundStyle(CDSColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: CDSSpacing.snug) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("逐游戏配置").cdsType(15, .semibold)
                        Spacer()
                        Text("点击游戏进入右侧预设面板")
                            .cdsType(10)
                            .foregroundStyle(CDSColor.textMuted)
                    }

                    if model.games.isEmpty {
                        CDSSurface(padding: CDSSpacing.section) {
                            CDSIntro(symbol: "slider.horizontal.3",
                                     title: "先关联或安装游戏",
                                     message: "有游戏记录后，便可以在详情面板保存专属预设。")
                        }
                    } else {
                        VStack(spacing: 0) {
                            ForEach(model.games) { game in
                                presetRow(game)
                                if game.id != model.games.last?.id {
                                    CDSHairline(inset: 58)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .background(CDSColor.surface2, in: RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous)
                                .strokeBorder(CDSColor.border, lineWidth: 1)
                        }
                    }

                    Text("不自动安装 DLL 注入器、画质包或反作弊补丁；也不提供虚假的通用分辨率或画质开关。预设效果需要实际进入游戏验证。")
                        .cdsType(10)
                        .foregroundStyle(CDSColor.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            .padding(CDSSpacing.page)
            .frame(maxWidth: 1200, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CDSColor.surface1)
    }

    private var columnRule: some View {
        GeometryReader { geo in
            let step = geo.size.width / 3
            Path { path in
                for index in 1...2 {
                    let x = step * CGFloat(index)
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: geo.size.height))
                }
            }
            .stroke(CDSColor.borderHairline, lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }

    private func presetColumn(_ title: String, subtitle: String, symbol: String,
                              tint: Color, body: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                CDSIconTile(symbol: symbol, size: 26, tint: tint)
                Text(title).cdsType(12.5, .semibold)
            }
            Text(subtitle).cdsType(10, .medium).foregroundStyle(tint)
            Text(body)
                .cdsType(10.5)
                .foregroundStyle(CDSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(CDSSpacing.base)
    }

    private func presetRow(_ game: GameRecord) -> some View {
        Button {
            model.navigate(.library)
            model.selectedGameID = game.id
        } label: {
            HStack(spacing: CDSSpacing.snug) {
                LocalArtwork(path: game.coverPath)
                    .frame(width: 32, height: 42)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: CDSRadius.md, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.name).cdsType(12, .medium)
                    Text(model.container(game.containerID)?.name ?? "")
                        .cdsType(10)
                        .foregroundStyle(CDSColor.textMuted)
                }
                Spacer(minLength: CDSSpacing.tight)
                if model.preset(game.id) != GamePreset() {
                    Text(model.preset(game.id).summary)
                        .cdsType(10)
                        .foregroundStyle(CDSColor.textSecondary)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CDSColor.textMuted)
            }
            .padding(.horizontal, CDSSpacing.base)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
