import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = "system"

    private var appearanceBinding: Binding<String> { $appearance }

    var body: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.roomy) {
            CDSPageHeader(title: "设置", subtitle: "外观、数据与版本信息。")

            CDSSurface(level: .two, radius: CDSRadius.xl, padding: CDSSpacing.base) {
                VStack(alignment: .leading, spacing: CDSSpacing.snug) {
                    Text("外观").cdsType(12, .semibold)
                    CDSSegmented(selection: appearanceBinding, items: [
                        .init(value: "system", title: "跟随系统"),
                        .init(value: "light", title: "浅色"),
                        .init(value: "dark", title: "深色")
                    ])
                    .frame(width: 300)
                }
            }

            CDSSurface(level: .two, radius: CDSRadius.xl, padding: CDSSpacing.base) {
                VStack(alignment: .leading, spacing: CDSSpacing.snug) {
                    Text("数据与隐私").cdsType(12, .semibold)
                    CDSKeyValue(label: "游戏与容器", value: "保留在各自的原始位置")
                    CDSHairline()
                    CDSKeyValue(label: "运行组件", value: "固定版本 · 不自动升级")
                    CDSHairline()
                    CDSKeyValue(label: "诊断日志", value: "仅本机保存")
                    HStack(spacing: CDSSpacing.tight) {
                        Button("打开数据目录") { model.reveal(AppPaths.root.path) }
                            .cdsButton(.outline, size: .sm)
                        Button("导出脱敏诊断…") { model.exportDiagnostics() }
                            .cdsButton(.outline, size: .sm)
                    }
                    .padding(.top, 4)
                }
            }

            CDSSurface(level: .two, radius: CDSRadius.xl, padding: CDSSpacing.base) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("关于").cdsType(12, .semibold)
                        Spacer()
                        Text("\(AppPaths.version) · 本地开发预览")
                            .cdsType(10.5, mono: true)
                            .foregroundStyle(CDSColor.textMuted)
                    }
                    Text("原生 macOS 游戏容器管理器。独立项目，非 Valve、Apple 或 Sikarugir 官方产品。尚未进行 Developer ID 公证，不作为公开正式发行版。")
                        .cdsType(10.5)
                        .foregroundStyle(CDSColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(CDSSpacing.section)
        .frame(width: 560, height: 520)
        .background(CDSColor.surface1)
    }
}
