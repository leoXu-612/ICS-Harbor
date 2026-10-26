import SwiftUI
import HarborCore

struct TaskHint: View {
    var title: String
    var message: String
    var symbol: String = "info.circle"
    var actionTitle: String?
    var action: () -> Void = {}
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 16) { text; if let actionTitle { Spacer(minLength: 16); Button(actionTitle, action: action).controlSize(.large) } }
            VStack(alignment: .leading, spacing: 12) { text; if let actionTitle { Button(actionTitle, action: action).controlSize(.large) } }
        }.padding(16).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
    }
    private var text: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(Color.harbor).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(message).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct LibraryConflictNotice: View {
    var action: (() -> Void)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("游戏库共用冲突 · 已阻止相关启动", systemImage: "exclamationmark.shield").font(.system(size: 14, weight: .semibold)).foregroundStyle(Color.harborFault)
            Text("Mac 原生 Steam 与 Wine 登记了同一目录，可能互相替换游戏文件。请先在原生 Steam 中取消这个库的登记，不要删除磁盘上的游戏。Harbor 不会自动改动库配置。")
                .font(.system(size: 13)).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
            if let action { Button("查看冲突的环境", action: action).controlSize(.large) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(18).background(Color.harborFault.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ApplicationSetupView: View {
    @Bindable var model: AppModel
    private var next: ApplicationGuidance { model.applicationGuidance }
    private var title: String {
        switch next { case .createEnvironment: return "先准备一个独立环境"; case .prepare: return "继续准备你的环境"; case .install: return "环境已就绪，安装你的第一个应用"; case .checkEnvironment: return "先确认环境状态"; case .wait: return "等待当前环境空闲" }
    }
    private var button: String {
        switch next { case .createEnvironment: return "创建通用环境"; case .prepare: return "继续准备环境"; case .install: return "选择安装包…"; case .checkEnvironment: return "检查运行环境"; case .wait: return "查看当前任务与环境" }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "app.badge").font(.system(size: 36, weight: .light)).foregroundStyle(Color.harbor).accessibilityHidden(true)
                Text(title).font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(model.state.containers.contains(where: { $0.origin == .linked }) && next == .createEnvironment ? "你已有的关联环境保持原样。新软件使用独立环境，避免影响现有游戏。" : "安装包用于安装软件；安装完成后，再把程序本身添加到这里。").font(.system(size: 14)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button(action: model.guideApplicationSetup) { Label(button, systemImage: next == .createEnvironment ? "plus" : "arrow.right").padding(.horizontal, 8).padding(.vertical, 4) }
                    .buttonStyle(.borderedProminent).tint(.harborAction).controlSize(.large).padding(.top, 4)
            }
            Divider()
            VStack(alignment: .leading, spacing: 22) {
                step(1, "准备环境", "创建通用 Windows 环境，不需要安装 Steam。")
                step(2, "运行安装包", "选择可信的 EXE 或 MSI，按安装器提示完成安装。便携版可跳过。")
                step(3, "添加程序入口", "选择安装后的 EXE。以后直接从应用列表启动。")
            }
            HStack(spacing: 14) {
                Button("已有 EXE？直接添加") { model.addApplication() }.disabled(model.state.containers.isEmpty)
                Button("查看完整指南") { model.section = .guide }.buttonStyle(.link)
            }.controlSize(.large)
            if model.state.containers.isEmpty { Text("添加已有 EXE 前，也需要先创建或关联一个 Wine 环境。").font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: 660, alignment: .leading).padding(.vertical, 20)
    }
    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)").font(.system(size: 13, weight: .semibold, design: .rounded)).frame(width: 28, height: 28).background(Color.primary.opacity(0.06), in: Circle()).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.system(size: 14, weight: .semibold)); Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }.accessibilityElement(children: .combine)
    }
}
