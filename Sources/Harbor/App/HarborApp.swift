import SwiftUI
import AppKit

@main struct HarborApp: App {
    @NSApplicationDelegateAdaptor(HarborDelegate.self) private var delegate
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = "system"
    private var colorScheme: ColorScheme? { appearance == "light" ? .light : appearance == "dark" ? .dark : nil }
    private var selectionCanLaunch: Bool {
        guard !model.isWorking,
              model.section == .library || (model.section.source?.isAvailable == true && !model.sourceSettingsVisible) else { return false }
        if let game = model.selectedGame {
            return game.availability == .ready && model.container(game.containerID).map { !model.hasLibraryConflict($0) } == true
        }
        return model.selectedApplication != nil
    }
    var body: some Scene {
        WindowGroup("Harbor", id: "main") {
            ContentView(model: model)
                .preferredColorScheme(colorScheme)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) { Button("创建运行环境…") { model.presentCreate() }.keyboardShortcut("n") }
            CommandMenu("资料库") {
                Button("全部内容") { model.navigate(.library) }.keyboardShortcut("1")
                Button("安装 EXE / MSI…") { model.openSourceSettings(.local); model.guideApplicationSetup() }
                Button("导入已安装程序…") { model.addApplication() }
                    .keyboardShortcut("i", modifiers: [.command, .shift]).disabled(model.state.containers.isEmpty)
                Divider()
                Button("启动所选条目") {
                    if let game = model.selectedGame { model.launchGame(game) }
                    else if let app = model.selectedApplication { model.launchApplication(app) }
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!selectionCanLaunch)
                Button("刷新资料库") { Task { await model.refresh() } }.keyboardShortcut("r")
                Button("关联现有容器…") { model.linkContainer() }.keyboardShortcut("o")
                Divider()
                Button("导出脱敏诊断…") { model.exportDiagnostics() }
            }
            CommandGroup(replacing: .help) { Button("Harbor 使用指南") { model.section = .guide }.keyboardShortcut("?", modifiers: .command) }
        }
        Settings { SettingsView(model: model).preferredColorScheme(colorScheme) }
    }
}

@MainActor final class HarborDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard model?.isWorking == true else { return .terminateNow }
        return Panels.confirm(title: "组件任务还在进行", message: "退出可能中断下载或初始化。部分文件会保留，下次可重试。正在运行的游戏不会被强制退出。", action: "仍然退出") ? .terminateNow : .terminateCancel
    }
}
