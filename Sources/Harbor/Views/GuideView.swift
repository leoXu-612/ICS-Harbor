import SwiftUI

struct GuideView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CDSSpacing.section) {
                CDSPageHeader(title: "你想做什么？",
                              subtitle: "从目标出发，不必先理解容器和盘符。")

                CDSSurface(level: .two, radius: CDSRadius.xl, padding: 0) {
                    VStack(spacing: 0) {
                        route("启动已添加的内容",
                              detail: "在全部内容中搜索名称，按类型或环境筛选，选中条目后在详情中启动。",
                              symbol: "gamecontroller", button: "打开全部内容") { model.navigate(.library) }
                        CDSHairline(inset: 60)
                        route("安装 Windows 软件",
                              detail: "先准备独立环境，再运行 EXE/MSI 安装包。装好后添加程序入口；便携版可以跳过安装。",
                              symbol: "app.badge", button: "开始添加应用") { model.openSourceSettings(.local) }
                        CDSHairline(inset: 60)
                        route("接入以前创建的环境",
                              detail: "选择已有 Sikarugir .app。只登记入口，不复制账号、游戏或存档，也不重建原来的环境。",
                              symbol: "link", button: "关联现有环境…", action: model.linkContainer)
                    }
                }

                VStack(alignment: .leading, spacing: CDSSpacing.base) {
                    Text("运行中，怎么操作？").cdsType(15, .semibold)
                    VStack(alignment: .leading, spacing: CDSSpacing.base) {
                        help("想打开或退出 Steam",
                             "前往「Steam → 接入设置」，选择运行该客户端的环境。退出前先保存并关闭游戏；关闭 Harbor 本身不会结束 Windows 程序。",
                             destination: .steam, action: "管理 Steam")
                        help("不知道是在加载还是卡住",
                             "“启动记录”显示已确认的检查点和等待时间。没有新状态时会提示等待较久；“停止跟踪”不会强杀程序。",
                             destination: .activity, action: "查看启动记录")
                        help("想调整游戏画面或性能",
                             "选中游戏后点“游戏参数”。参数按游戏保存，切换运行时配置前需要正常退出同一环境内的程序。",
                             destination: .presets, action: "查看参数说明")
                        help("外置盘或游戏库有问题",
                             "先在“运行环境”检查磁盘与游戏库。不要让原生 Mac Steam 和 Wine 共用同一目录；不要因读取不到就删除或重装游戏。",
                             destination: .containers, action: "检查磁盘与库")
                    }
                }

                Text("Harbor 管理的是 Wine 运行环境，不是安全沙箱。只运行可信程序；安装成功、窗口出现和软件功能正常是不同的验证阶段。")
                    .cdsType(10.5)
                    .foregroundStyle(CDSColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(CDSSpacing.page)
            .frame(maxWidth: 1040, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CDSColor.surface1)
    }

    private func route(_ title: String, detail: String, symbol: String, button: String,
                       action: @escaping () -> Void) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: CDSSpacing.roomy) {
                routeLabel(title, detail: detail, symbol: symbol)
                Spacer(minLength: CDSSpacing.snug)
                Button(button, action: action).cdsButton(.outline, size: .md).fixedSize()
            }
            VStack(alignment: .leading, spacing: CDSSpacing.base) {
                routeLabel(title, detail: detail, symbol: symbol)
                Button(button, action: action).cdsButton(.outline, size: .md)
            }
        }
        .padding(CDSSpacing.roomy)
    }

    private func routeLabel(_ title: String, detail: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: CDSSpacing.base) {
            CDSIconTile(symbol: symbol, size: 36)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).cdsType(14.5, .semibold)
                Text(detail)
                    .cdsType(11.5)
                    .foregroundStyle(CDSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func help(_ title: String, _ text: String, destination: AppSection, action: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).cdsType(12.5, .semibold)
            Text(text)
                .cdsType(11)
                .foregroundStyle(CDSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action) { if let source = destination.source { model.openSourceSettings(source) } else { model.navigate(destination) } }
                .cdsButton(.ghost, size: .xs)
                .padding(.top, 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CDSSpacing.base)
        .background(CDSColor.fillTertiary,
                    in: RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous))
    }
}
