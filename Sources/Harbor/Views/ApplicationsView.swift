import SwiftUI
import HarborCore

struct ApplicationsView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    private var filtered: [WindowsApplication] {
        model.applications.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                PageHeading(title: "Windows 应用", subtitle: "独立于 Steam。安装软件，或为已有 EXE 添加启动入口。")
                Spacer()
                Button("安装 EXE / MSI…", systemImage: "shippingbox") { model.showInstallApplication = true }.disabled(model.isWorking)
                Button("添加已安装 EXE…", systemImage: "plus") { model.addApplication() }.buttonStyle(.borderedProminent)
            }.padding(.horizontal, 24).padding(.top, 24)
            if model.applications.isEmpty {
                Spacer()
                EmptyState(symbol: "app.badge", title: "不需要 Steam 的 Windows 软件", message: "先创建通用运行环境，再安装 EXE/MSI。便携版或已经安装的软件可以直接添加 EXE。")
                HStack { Spacer(); Button("创建通用环境…") { model.showCreate = true }; Spacer() }
                Spacer()
                Text("Wine 环境不是安全沙箱。只运行可信程序；软件许可、登录与功能兼容性仍需分别确认。")
                    .font(.caption).foregroundStyle(.secondary).padding(24)
            } else {
                HSplitView {
                    VStack(spacing: 10) {
                        TextField("搜索应用", text: $query).textFieldStyle(.roundedBorder).padding(.horizontal, 12)
                        List(selection: $model.selectedApplicationID) {
                            ForEach(filtered) { app in
                                HStack(spacing: 10) {
                                    Image(systemName: "app").foregroundStyle(Color.harbor)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(app.name).lineLimit(1)
                                        Text(model.container(app.containerID)?.name ?? "环境已移除").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }.padding(.vertical, 5).tag(app.id)
                            }
                        }.listStyle(.inset)
                    }.frame(minWidth: 210, idealWidth: 260, maxWidth: 340)
                    if let app = model.selectedApplication {
                        applicationDetail(app).frame(minWidth: 380, maxWidth: .infinity)
                    } else {
                        EmptyState(symbol: "app", title: "选择一个应用", message: "查看启动入口、工作目录和运行状态。")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }
    private func applicationDetail(_ app: WindowsApplication) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeading(title: app.name, subtitle: model.container(app.containerID)?.name ?? "环境不可用")
                HStack {
                    Button("启动应用", systemImage: "play.fill") { model.launchApplication(app) }.buttonStyle(.borderedProminent).controlSize(.large)
                        .disabled(model.isWorking || model.pendingLaunch(in: app.containerID) != nil)
                    Button("编辑入口…") { model.editApplication(app) }
                    Menu {
                        Button("显示 EXE 文件") { model.reveal(app.executablePath) }
                        Button("移除入口（保留文件）", role: .destructive) { model.forgetApplication(app) }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 26)
                }
                if let progress = model.applicationProgress(app) { LaunchProgressView(model: model, progress: progress, compact: true) }
                Surface {
                    VStack(alignment: .leading, spacing: 15) {
                        pathRow("EXE 程序", app.executablePath)
                        pathRow("工作目录", app.workingDirectory)
                        Text("启动参数").font(.caption).foregroundStyle(.secondary)
                        Text(app.arguments.isEmpty ? "无" : app.arguments.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        if !FileManager.default.isReadableFile(atPath: app.executablePath) { Label("程序文件不可读，请连接原磁盘或编辑入口。", systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(.orange).font(.caption) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("启动普通应用时继承环境原始图形参数。退出请使用程序自己的菜单；关闭 Harbor 不会关闭程序。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
    private func pathRow(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(title).font(.caption).foregroundStyle(.secondary); Text(Format.path(value)).font(.system(.caption, design: .monospaced)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
    }
}

struct ApplicationEditor: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var containerID: UUID?
    @State private var name = ""
    @State private var executable = ""
    @State private var workingDirectory = ""
    @State private var arguments = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.editingApplication == nil ? "添加已安装 EXE" : "编辑应用入口").font(.title2.weight(.bold))
            Text("只登记启动方式，不安装、不移动文件。请选择程序本身，而不是安装器。").font(.callout).foregroundStyle(.secondary)
            Form {
                Section("程序与环境") {
                    Picker("运行环境", selection: $containerID) { Text("选择环境").tag(UUID?.none); ForEach(model.state.containers) { Text($0.name).tag(Optional($0.id)) } }
                        .disabled(model.editingApplication != nil)
                    HStack {
                        Text(executable.isEmpty ? "尚未选择 EXE" : URL(fileURLWithPath: executable).lastPathComponent).lineLimit(1)
                        Spacer(); Button("选择 EXE…") {
                            let initial = containerID.flatMap(model.container).map { URL(fileURLWithPath: $0.prefix + "/drive_c") }
                            if let url = Panels.chooseWindowsFile(installer: false, directory: initial) {
                                executable = url.path; workingDirectory = url.deletingLastPathComponent().path
                                if name.isEmpty { name = url.deletingPathExtension().lastPathComponent }
                            }
                        }.disabled(containerID == nil)
                    }
                    TextField("显示名称", text: $name)
                }
                Section("启动方式") {
                    HStack {
                        Text(workingDirectory.isEmpty ? "默认：EXE 所在目录" : Format.path(workingDirectory)).font(.caption).lineLimit(2)
                        Spacer(); Button("工作目录…") {
                            if let url = Panels.chooseDirectory(workingDirectory.isEmpty ? nil : URL(fileURLWithPath: workingDirectory)) { workingDirectory = url.path }
                        }
                    }
                    Text("启动参数 · 每行一个完整参数，无需加引号").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $arguments).font(.system(.body, design: .monospaced)).frame(height: 80).border(Color.secondary.opacity(0.2))
                    Text("参数逐项传递，不把输入拼成 Shell 命令。当前不接受内嵌双引号或控制字符。").font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
            HStack {
                Text("请勿运行不可信 EXE；Wine 不是安全沙箱。").font(.caption).foregroundStyle(.secondary)
                Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存入口") {
                    guard let containerID else { return }
                    let value = WindowsApplication(id: model.editingApplication?.id ?? UUID(), containerID: containerID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), executablePath: executable, workingDirectory: workingDirectory, arguments: arguments.components(separatedBy: .newlines).filter { !$0.isEmpty })
                    if model.saveApplication(value) { dismiss() }
                }.buttonStyle(.borderedProminent).disabled(containerID == nil || executable.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }.padding(24).frame(width: 650, height: 590).onAppear {
            if let app = model.editingApplication { containerID = app.containerID; name = app.name; executable = app.executablePath; workingDirectory = app.workingDirectory; arguments = app.arguments.joined(separator: "\n") }
            else { containerID = model.state.containers.first(where: { $0.purpose == .applications })?.id ?? model.state.containers.first?.id }
        }
    }
}

struct InstallApplicationView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var containerID: UUID?
    @State private var file: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("安装 Windows 软件", systemImage: "shippingbox").font(.title2.weight(.bold))
            Text("复用 Wine 安装器；MSI 由内置 msiexec 处理。不会启动 Steam，也不会自动接受许可或登录。").foregroundStyle(.secondary)
            Form {
                Picker("目标环境", selection: $containerID) { Text("选择已准备的托管环境").tag(UUID?.none); ForEach(model.state.containers.filter { $0.origin == .managed }) { Text($0.name).tag(Optional($0.id)) } }
                HStack { Text(file?.lastPathComponent ?? "请选择 EXE 或 MSI 安装包").lineLimit(2); Spacer(); Button("选择安装包…") { file = Panels.chooseWindowsFile(installer: true) } }
            }.formStyle(.grouped).frame(height: 140)
            Text("安装会修改所选环境。先保存并退出其中的程序；安装结束后，用“添加已安装 EXE”创建启动入口。安装器退出不等于应用功能已通过验收。").font(.callout).foregroundStyle(.secondary)
            if model.state.containers.allSatisfy({ $0.origin != .managed }) { Label("请先在运行环境页创建通用 Windows 环境。", systemImage: "info.circle").foregroundStyle(.orange) }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("运行安装器") {
                if let file, let id = containerID, let container = model.container(id) { dismiss(); model.installApplication(file, container: container); model.section = .applications }
            }.buttonStyle(.borderedProminent).disabled(file == nil || containerID == nil || model.isWorking) }
        }.padding(28).frame(width: 620).onAppear { containerID = model.state.containers.first(where: { $0.origin == .managed && $0.purpose == .applications })?.id ?? model.state.containers.first(where: { $0.origin == .managed })?.id }
    }
}
