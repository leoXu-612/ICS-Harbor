import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("appearance") private var appearance = "system"
    var body: some View {
        Form {
            Section("外观") {
                Picker("主题", selection: $appearance) { Text("跟随系统").tag("system"); Text("浅色").tag("light"); Text("深色").tag("dark") }.pickerStyle(.segmented)
            }
            Section("数据与隐私") {
                LabeledContent("游戏与容器", value: "保留在各自的原始位置")
                LabeledContent("运行组件", value: "固定版本 · 不自动升级")
                LabeledContent("诊断日志", value: "仅本机保存")
                Button("打开 Harbor 数据目录") { model.reveal(AppPaths.root.path) }
                Button("导出脱敏诊断…") { model.exportDiagnostics() }
            }
            Section("关于") {
                LabeledContent("版本", value: "0.4.0 · 本地开发预览")
                Text("原生 macOS 游戏容器管理器。独立项目，非 Valve、Apple 或 Sikarugir 官方产品。尚未进行 Developer ID 公证，不作为公开正式发行版。").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 550, height: 480)
    }
}
