import SwiftUI
import HarborCore

struct ApplicationsView: View {
    let model: AppModel

    var body: some View {
        UnifiedCatalogView(model: model, source: .local)
    }
}

struct CatalogApplicationInspector: View {
    let model: AppModel
    let app: WindowsApplication
    let status: CatalogStatus
    @State private var detailsExpanded = false
    @State private var showTraffic = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CDSSpacing.roomy) {
                HStack(alignment: .top, spacing: CDSSpacing.snug) {
                    WindowsApplicationIcon(executablePath: app.executablePath)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(app.name).cdsType(18, .semibold).fixedSize(horizontal: false, vertical: true)
                        Text(model.container(app.containerID)?.name ?? "环境不可用")
                            .cdsType(11).foregroundStyle(CDSColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                CatalogStatusLabel(status: status)
                    .cdsType(11)

                Button("启动", systemImage: "play.fill") { model.launchApplication(app) }
                    .cdsButton(.primary, size: .lg, fullWidth: true)
                    .disabled(model.isWorking || model.pendingLaunch(in: app.containerID) != nil)

                if status == .unreadable {
                    Text("连接原磁盘，或在启动设置中重新选择 EXE。")
                        .cdsType(11).foregroundStyle(CDSColor.warning)
                }

                HStack {
                    Button("启动设置…", systemImage: "slider.horizontal.3") { model.editApplication(app) }
                        .cdsButton(.outline, size: .md)
                    Spacer()
                    Menu("更多操作") {
                        Button("显示 EXE 文件") { model.reveal(app.executablePath) }
                        Button("移除入口（保留文件）", role: .destructive) { model.forgetApplication(app) }
                    }
                    .fixedSize()
                }

                if let progress = model.applicationProgress(app) {
                    LaunchProgressView(model: model, progress: progress, compact: true)
                }

                Button("流量与资源使用…", systemImage: "waveform.path.ecg") { showTraffic = true }
                    .cdsButton(.outline, size: .md, fullWidth: true)

                Button("来源详情", systemImage: "tray.and.arrow.down") { model.openSourceSettings(.local) }
                    .cdsButton(.ghost, size: .sm)
                Button("所在环境", systemImage: "square.3.layers.3d") { model.navigate(.containers) }
                    .cdsButton(.ghost, size: .sm)

                DisclosureGroup("程序路径与启动参数", isExpanded: $detailsExpanded) {
                    CDSSurface(level: .three, radius: CDSRadius.xl, padding: CDSSpacing.base) {
                        VStack(alignment: .leading, spacing: CDSSpacing.snug) {
                            pathRow("EXE 程序", app.executablePath)
                            CDSHairline()
                            pathRow("工作目录", app.workingDirectory)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("启动参数").cdsType(10.5).foregroundStyle(CDSColor.textSecondary)
                                Text(app.arguments.isEmpty ? "无" : app.arguments.joined(separator: "\n"))
                                    .cdsType(11, mono: true)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.top, CDSSpacing.snug)
                }
                .font(.system(size: 12, weight: .medium))

                Text("通过 EXE 启动时继承环境原始图形参数。退出请使用程序自己的菜单；关闭 Harbor 不会关闭程序。")
                    .cdsType(10.5)
                    .foregroundStyle(CDSColor.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(CDSSpacing.roomy)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: $showTraffic) { CatalogTrafficSheet(model: model, application: app) }
    }

    private func pathRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).cdsType(10.5).foregroundStyle(CDSColor.textSecondary)
            Text(Format.path(value))
                .cdsType(11, mono: true)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 添加 / 编辑入口

struct ApplicationEditor: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var containerID: UUID?
    @State private var name = ""
    @State private var executable = ""
    @State private var workingDirectory = ""
    @State private var arguments = ""
    @State private var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.base) {
            sheetHeader(title: model.editingApplication == nil ? "添加已安装 EXE" : "编辑应用入口",
                        subtitle: "只登记启动方式，不安装、不移动文件。请选择程序本身，而不是安装器。",
                        symbol: "app.badge")

            Form {
                Section("程序与环境") {
                    Picker("运行环境", selection: $containerID) {
                        Text("选择环境").tag(UUID?.none)
                        ForEach(model.state.containers) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .disabled(model.editingApplication != nil)

                    HStack {
                        Text(executable.isEmpty ? "尚未选择 EXE"
                             : URL(fileURLWithPath: executable).lastPathComponent)
                            .cdsType(12)
                            .lineLimit(1)
                        Spacer()
                        Button("选择 EXE…") {
                            let initial = containerID.flatMap(model.container)
                                .map { URL(fileURLWithPath: $0.prefix + "/drive_c") }
                            if let url = Panels.chooseWindowsFile(installer: false, directory: initial) {
                                executable = url.path
                                workingDirectory = url.deletingLastPathComponent().path
                                if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                            }
                        }
                        .disabled(containerID == nil)
                    }

                    TextField("显示名称", text: $name)
                }

                DisclosureGroup("可选：工作目录与启动参数", isExpanded: $advanced) {
                    HStack {
                        Text(workingDirectory.isEmpty ? "默认：EXE 所在目录" : Format.path(workingDirectory))
                            .cdsType(10.5).lineLimit(2)
                        Spacer()
                        Button("工作目录…") {
                            if let url = Panels.chooseDirectory(
                                workingDirectory.isEmpty ? nil : URL(fileURLWithPath: workingDirectory)
                            ) { workingDirectory = url.path }
                        }
                    }
                    Text("启动参数 · 每行一个完整参数，无需加引号")
                        .cdsType(10.5).foregroundStyle(CDSColor.textSecondary)
                    TextEditor(text: $arguments)
                        .font(.system(.body, design: .monospaced))
                        .frame(height: 80)
                    Text("参数逐项传递，不把输入拼成 Shell 命令。当前不接受内嵌双引号或控制字符。")
                        .cdsType(10).foregroundStyle(CDSColor.textMuted)
                }
            }
            .formStyle(.grouped)

            HStack {
                Text("请勿运行不可信 EXE；Wine 不是安全沙箱。")
                    .cdsType(10.5).foregroundStyle(CDSColor.textMuted)
                Spacer()
                Button("取消") { dismiss() }.cdsButton(.ghost, size: .md)
                Button("保存入口") {
                    guard let containerID else { return }
                    let value = WindowsApplication(
                        id: model.editingApplication?.id ?? UUID(),
                        containerID: containerID,
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        executablePath: executable,
                        workingDirectory: workingDirectory,
                        arguments: arguments.components(separatedBy: .newlines).filter { !$0.isEmpty }
                    )
                    if model.saveApplication(value) { dismiss() }
                }
                .cdsButton(.primary, size: .md)
                .disabled(containerID == nil || executable.isEmpty
                          || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(CDSSpacing.section)
        .frame(width: 660, height: 600)
        .background(CDSColor.surface1)
        .onAppear {
            if let app = model.editingApplication {
                containerID = app.containerID
                name = app.name
                executable = app.executablePath
                workingDirectory = app.workingDirectory
                arguments = app.arguments.joined(separator: "\n")
                advanced = true
            } else {
                containerID = model.state.containers.first(where: { $0.purpose == .applications })?.id
                    ?? model.state.containers.first?.id
            }
        }
    }
}

// MARK: - 安装器

struct InstallApplicationView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var containerID: UUID?
    @State private var file: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.base) {
            sheetHeader(title: "安装 Windows 软件",
                        subtitle: "选择环境与安装包，然后按安装器提示操作。完成后添加安装好的 EXE，而不是再次添加安装包。",
                        symbol: "shippingbox")

            Form {
                Picker("1 · 安装到哪个环境", selection: $containerID) {
                    Text("选择已准备的托管环境").tag(UUID?.none)
                    ForEach(model.state.containers.filter { $0.origin == .managed }) {
                        Text($0.name).tag(Optional($0.id))
                    }
                }
                HStack {
                    Text(file?.lastPathComponent ?? "请选择 EXE 或 MSI 安装包")
                        .cdsType(12).lineLimit(2)
                    Spacer()
                    Button("选择安装包…") { file = Panels.chooseWindowsFile(installer: true) }
                }
            }
            .formStyle(.grouped)
            .frame(height: 150)

            if let id = containerID, model.busy.contains(id) || model.pendingLaunch(in: id) != nil {
                Label("这个环境仍在运行。请先保存并正常退出其中的程序。", systemImage: "pause.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(CDSColor.warning)
            } else if let id = containerID, model.runtime[id]?.applicationReady != true {
                Label("这个环境尚未准备完成。请先到运行环境页继续准备。", systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(CDSColor.warning)
            }

            Text("许可与登录由你完成。不会启动 Steam，不会自动接受协议或强制重启。")
                .cdsType(10.5)
                .foregroundStyle(CDSColor.textMuted)

            if model.state.containers.allSatisfy({ $0.origin != .managed }) {
                Label("请先在运行环境页创建通用 Windows 环境。", systemImage: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(CDSColor.warning)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }.cdsButton(.ghost, size: .md)
                Button("运行安装器") {
                    if let file, let id = containerID, let container = model.container(id) {
                        dismiss()
                        model.installApplication(file, container: container)
                        model.navigate(.local)
                    }
                }
                .cdsButton(.primary, size: .md)
                .disabled(file == nil || containerID == nil || model.isWorking
                          || containerID.map { model.runtime[$0]?.applicationReady != true
                              || model.busy.contains($0)
                              || model.pendingLaunch(in: $0) != nil } == true)
            }
        }
        .padding(CDSSpacing.section)
        .frame(width: 620)
        .background(CDSColor.surface1)
        .onAppear {
            if case .install(let id) = model.applicationGuidance { containerID = id }
            else { containerID = model.preferredInstallContainerID
                ?? model.state.containers.first(where: { $0.origin == .managed })?.id }
        }
    }
}
