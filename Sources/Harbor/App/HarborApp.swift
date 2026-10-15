import SwiftUI
import AppKit

@main struct HarborApp: App {
    @NSApplicationDelegateAdaptor(HarborDelegate.self) private var delegate
    @State private var model = AppModel()
    @AppStorage("appearance") private var appearance = "system"
    private var colorScheme: ColorScheme? { appearance == "light" ? .light : appearance == "dark" ? .dark : nil }
    var body: some Scene {
        WindowGroup("Harbor", id: "main") {
            ContentView(model: model)
                .preferredColorScheme(colorScheme)
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) { Button("新建托管容器…") { model.showCreate = true }.keyboardShortcut("n") }
            CommandMenu("Windows 应用") {
                Button("安装 EXE / MSI…") { model.showInstallApplication = true }
                Button("添加已安装 EXE…") { model.addApplication() }.keyboardShortcut("i", modifiers: [.command, .shift])
                Divider()
                Button("启动所选应用") { if let app = model.selectedApplication { model.launchApplication(app) } }.disabled(model.selectedApplication == nil || model.isWorking)
            }
            CommandMenu("游戏库") {
                Button("启动所选游戏") { if let game = model.selectedGame { model.launchGame(game) } }
                    .keyboardShortcut(.return, modifiers: .command).disabled(model.selectedGame == nil || model.isWorking)
                Divider()
                Button("刷新游戏库") { Task { await model.refresh() } }.keyboardShortcut("r")
                Button("关联现有容器…") { model.linkContainer() }.keyboardShortcut("o")
                Divider()
                Button("导出脱敏诊断…") { model.exportDiagnostics() }
            }
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
