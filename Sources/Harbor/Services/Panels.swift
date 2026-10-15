import AppKit
import UniformTypeIdentifiers

@MainActor enum Panels {
    static func chooseWindowsFile(installer: Bool, directory: URL? = nil) -> URL? {
        let panel = NSOpenPanel()
        panel.title = installer ? "选择 Windows 安装包" : "选择已安装或便携版 EXE"
        panel.message = installer ? "仅运行你信任的来源。许可和登录需要本人处理。" : "选择程序本身，不要选择安装器。只保存启动入口，文件保留原位。"
        panel.allowedContentTypes = (installer ? ["exe", "msi"] : ["exe"]).compactMap { UTType(filenameExtension: $0) }
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true; panel.directoryURL = directory
        return panel.runModal() == .OK ? panel.url : nil
    }
    static func chooseDirectory(_ initial: URL?) -> URL? {
        let panel = NSOpenPanel(); panel.title = "选择工作目录"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true; panel.directoryURL = initial
        return panel.runModal() == .OK ? panel.url : nil
    }
    static func chooseWrapper() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "关联现有 Wine 容器"
        panel.message = "选择 Sikarugir 的 .app。不复制账号或存档，不在关联环境中安装新软件。"
        panel.canChooseFiles = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = [.applicationBundle]; panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Sikarugir")
        return panel.runModal() == .OK ? panel.url : nil
    }
    static func exportText(_ text: String) throws {
        let panel = NSSavePanel(); panel.title = "导出脱敏诊断"
        panel.allowedContentTypes = [.plainText]; panel.nameFieldStringValue = "Harbor-diagnostics.txt"
        if panel.runModal() == .OK, let url = panel.url { try text.write(to: url, atomically: true, encoding: .utf8) }
    }
    static func confirm(title: String, message: String, action: String) -> Bool {
        let alert = NSAlert(); alert.messageText = title; alert.informativeText = message
        alert.addButton(withTitle: action); alert.addButton(withTitle: "取消")
        return alert.runModal() == .alertFirstButtonReturn
    }
}
