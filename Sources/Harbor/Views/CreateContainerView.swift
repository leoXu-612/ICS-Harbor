import SwiftUI
import HarborCore

struct CreateContainerView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Windows 应用"
    @State private var purpose: ContainerPurpose = .applications
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            HStack(spacing: 15) {
                Image(systemName: "shippingbox.fill").font(.system(size: 35)).foregroundStyle(Color.harbor)
                VStack(alignment: .leading, spacing: 5) { Text("一个独立的 Windows 环境").font(.title2.weight(.bold)); Text("不复制其他容器的账号、应用或存档。").font(.callout).foregroundStyle(.secondary) }
            }
            Picker("用途", selection: $purpose) { Text("通用应用 · 不装 Steam").tag(ContainerPurpose.applications); Text("Steam 游戏").tag(ContainerPurpose.steam) }.pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 8) { Text("容器名称").font(.caption).foregroundStyle(.secondary); TextField("例如：Steam · DXMT", text: $name).textFieldStyle(.roundedBorder).controlSize(.large) }
            Surface {
                VStack(alignment: .leading, spacing: 12) {
                    row("运行环境", "Wine Sikarugir 11.0 r1 / DXMT")
                    row("首次下载", purpose == .applications ? "约 283 MB · 含开源中文字体" : "约 266 MB · SHA-256 校验")
                    row("建议空间", "至少 10 GB，应用与游戏另计")
                    row("数据位置", "Harbor 的独立 Application Support 目录")
                }
            }
            Text("运行组件来自 Sikarugir 与 Valve 官方下载，使用须遵守各自许可。Harbor 本体不捆绑这些组件。本地预览版尚未完成公开分发的许可及公证审核。").font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Label(purpose == .steam ? "Steam 登录、Steam Guard 与许可确认仍由本人完成。" : "只创建独立 Wine 目录，之后可安装 EXE / MSI。不是安全沙箱。", systemImage: "person.crop.circle.badge.checkmark").font(.caption)
            HStack {
                Button("改为关联已有容器…") { dismiss(); model.linkContainer() }.buttonStyle(.link)
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("下载并创建") { model.createContainer(name: name, purpose: purpose) }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || model.isWorking)
            }.controlSize(.large)
        }.padding(30).frame(width: 580)
    }
    private func row(_ title: String, _ value: String) -> some View { HStack { Text(title).font(.caption).foregroundStyle(.secondary).frame(width: 80, alignment: .leading); Text(value).font(.system(size: 12, weight: .medium)); Spacer() } }
}
