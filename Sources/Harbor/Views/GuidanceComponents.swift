import SwiftUI
import HarborCore

// MARK: - 操作提示

struct TaskHint: View {
    var title: String
    var message: String
    var symbol: String = "info.circle"
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: CDSSpacing.base) {
                text
                if let actionTitle {
                    Spacer(minLength: CDSSpacing.base)
                    Button(actionTitle, action: action).cdsButton(.outline, size: .md)
                }
            }
            VStack(alignment: .leading, spacing: CDSSpacing.snug) {
                text
                if let actionTitle {
                    Button(actionTitle, action: action).cdsButton(.outline, size: .md)
                }
            }
        }
        .padding(CDSSpacing.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CDSColor.fillTertiary,
                    in: RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous)
                .strokeBorder(CDSColor.borderHairline, lineWidth: 1)
        }
    }

    private var text: some View {
        HStack(alignment: .top, spacing: CDSSpacing.snug) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(CDSColor.clay)
                .frame(width: 16)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).cdsType(12, .semibold)
                Text(message)
                    .cdsType(11)
                    .foregroundStyle(CDSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - 库冲突

struct LibraryConflictNotice: View {
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 7) {
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(CDSColor.fault)
                Text("游戏库共用冲突 · 已阻止相关启动")
                    .cdsType(12.5, .semibold)
                    .foregroundStyle(CDSColor.fault)
            }
            Text("Mac 原生 Steam 与 Wine 登记了同一目录，可能互相替换游戏文件。请先在原生 Steam 中取消这个库的登记，不要删除磁盘上的游戏。Harbor 不会自动改动库配置。")
                .cdsType(11)
                .foregroundStyle(CDSColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let action {
                Button("查看冲突的环境", action: action)
                    .cdsButton(.outline, size: .sm)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(CDSSpacing.base)
        .background(CDSColor.fault.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous)
                .strokeBorder(CDSColor.fault.opacity(0.20), lineWidth: 1)
        }
    }
}

// MARK: - 首次使用某应用时的路径引导

struct ApplicationSetupView: View {
    @Bindable var model: AppModel

    private var next: ApplicationGuidance { model.applicationGuidance }

    private var title: String {
        switch next {
        case .createEnvironment: "先准备一个独立环境"
        case .prepare: "继续准备你的环境"
        case .install: "环境已就绪，安装你的第一个应用"
        case .checkEnvironment: "先确认环境状态"
        case .wait: "等待当前环境空闲"
        }
    }

    private var button: String {
        switch next {
        case .createEnvironment: "创建通用环境"
        case .prepare: "继续准备环境"
        case .install: "选择安装包…"
        case .checkEnvironment: "检查运行环境"
        case .wait: "查看当前任务与环境"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.section) {
            VStack(alignment: .leading, spacing: CDSSpacing.snug) {
                CDSIconTile(symbol: "app.badge", size: 56, tint: CDSColor.clay)
                Text(title).cdsType(20, .semibold).padding(.top, 4)
                Text(model.state.containers.contains(where: { $0.origin == .linked }) && next == .createEnvironment
                     ? "你已有的关联环境保持原样。新软件使用独立环境，避免影响现有游戏。"
                     : "安装包用于安装软件；安装完成后，再把程序本身添加到这里。")
                    .cdsType(12)
                    .foregroundStyle(CDSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: model.guideApplicationSetup) {
                    Label(button, systemImage: next == .createEnvironment ? "plus" : "arrow.right")
                }
                .cdsButton(.primary, size: .lg)
                .padding(.top, 6)
            }

            CDSHairline()

            VStack(alignment: .leading, spacing: CDSSpacing.roomy) {
                step(1, "准备环境", "创建通用 Windows 环境，不需要安装 Steam。")
                step(2, "运行安装包", "选择可信的 EXE 或 MSI，按安装器提示完成安装。便携版可跳过。")
                step(3, "添加程序入口", "选择安装后的 EXE。以后直接从应用列表启动。")
            }

            HStack(spacing: CDSSpacing.snug) {
                Button("已有 EXE？直接添加") { model.addApplication() }
                    .cdsButton(.outline, size: .md)
                    .disabled(model.state.containers.isEmpty)
                Button("查看完整指南") { model.section = .guide }
                    .cdsButton(.ghost, size: .md)
            }

            if model.state.containers.isEmpty {
                Text("添加已有 EXE 前，也需要先创建或关联一个 Wine 环境。")
                    .cdsType(10.5)
                    .foregroundStyle(CDSColor.textMuted)
            }
        }
        .frame(maxWidth: 660, alignment: .leading)
        .padding(.vertical, CDSSpacing.roomy)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: CDSSpacing.snug) {
            Text("\(number)")
                .cdsType(11, .semibold, mono: true)
                .foregroundStyle(CDSColor.clay)
                .frame(width: 22, height: 22)
                .background(CDSColor.claySubtle, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).cdsType(12.5, .semibold)
                Text(detail)
                    .cdsType(11)
                    .foregroundStyle(CDSColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
