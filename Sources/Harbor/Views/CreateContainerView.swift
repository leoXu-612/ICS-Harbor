import SwiftUI
import HarborCore

struct CreateContainerView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Windows 应用"
    @State private var purpose: ContainerPurpose = .applications

    private var purposeBinding: Binding<ContainerPurpose> { $purpose }

    var body: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.roomy) {
            sheetHeader(title: "一个独立的 Windows 环境",
                        subtitle: "不复制其他容器的账号、应用或存档。",
                        symbol: "shippingbox.fill")

            CDSSegmented(selection: purposeBinding, items: [
                .init(value: .applications, title: "通用应用 · 不装 Steam"),
                .init(value: .steam, title: "Steam 游戏")
            ])

            VStack(alignment: .leading, spacing: 6) {
                Text("容器名称").cdsType(10.5).foregroundStyle(CDSColor.textSecondary)
                TextField("例如：Steam · DXMT", text: $name)
                    .textFieldStyle(.plain)
                    .cdsType(13)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                    .background(CDSColor.surface3,
                                in: RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous)
                            .strokeBorder(CDSColor.border, lineWidth: 1)
                    }
            }

            CDSSurface(level: .three, radius: CDSRadius.xl, padding: CDSSpacing.base) {
                VStack(alignment: .leading, spacing: 9) {
                    row("运行环境", "Wine Sikarugir 11.0 r1 / DXMT")
                    CDSHairline()
                    row("首次下载", purpose == .applications ? "约 283 MB · 含开源中文字体" : "约 266 MB · SHA-256 校验")
                    CDSHairline()
                    row("建议空间", "至少 10 GB，应用与游戏另计")
                    CDSHairline()
                    row("数据位置", "Harbor 的独立 Application Support 目录")
                }
            }

            Text("运行组件来自 Sikarugir 与 Valve 官方下载，使用须遵守各自许可。Harbor 本体不捆绑这些组件。本地预览版尚未完成公开分发的许可及公证审核。")
                .cdsType(10.5)
                .foregroundStyle(CDSColor.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            Label(purpose == .steam
                  ? "Steam 登录、Steam Guard 与许可确认仍由本人完成。"
                  : "只创建独立 Wine 目录，之后可安装 EXE / MSI。不是安全沙箱。",
                  systemImage: "person.crop.circle.badge.checkmark")
                .font(.system(size: 10.5))
                .foregroundStyle(CDSColor.textSecondary)

            HStack(spacing: CDSSpacing.tight) {
                Button("改为关联已有容器…") {
                    dismiss()
                    model.linkContainer()
                }
                .cdsButton(.ghost, size: .md)

                Spacer()

                Button("取消") { dismiss() }.cdsButton(.ghost, size: .md)
                Button("下载并创建") { model.createContainer(name: name, purpose: purpose) }
                    .cdsButton(.primary, size: .md)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || model.isWorking)
            }
        }
        .padding(CDSSpacing.section)
        .frame(width: 600)
        .background(CDSColor.surface1)
        .onAppear {
            purpose = model.creationPurpose
            name = purpose == .steam ? "Steam 游戏" : "Windows 应用"
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: CDSSpacing.snug) {
            Text(title)
                .cdsType(10.5)
                .foregroundStyle(CDSColor.textSecondary)
                .frame(width: 72, alignment: .leading)
            Text(value).cdsType(11.5, .medium)
            Spacer(minLength: 0)
        }
    }
}
