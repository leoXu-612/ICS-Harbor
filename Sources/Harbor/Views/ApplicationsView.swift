import SwiftUI
import HarborCore

struct ApplicationsView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @State private var detailsExpanded = false
    private var filtered: [WindowsApplication] {
        model.applications.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 20) {
                PageHeading(title: "Windows 应用", subtitle: model.applications.isEmpty ? "从安装到启动，一条清楚的路径。" : "\(model.applications.count) 个入口 · 选择应用后在右侧启动。")
                Spacer()
                if !model.applications.isEmpty {
                    Menu {
                        Button("安装新软件…") { model.guideApplicationSetup() }
                        Button("添加已有 EXE…") { model.addApplication() }
                    } label: { Label("添加应用", systemImage: "plus") }.controlSize(.large).fixedSize()
                }
            }.padding(.horizontal, 28).padding(.top, 28)
            if model.applications.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ApplicationSetupView(model: model)
                        Text("只运行可信来源的程序。Wine 环境不是安全沙箱，软件许可和登录仍由你完成。").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.padding(.horizontal, 32).padding(.bottom, 32).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
                }
            } else {
                HSplitView {
                    VStack(spacing: 10) {
                        TextField("搜索应用", text: $query).textFieldStyle(.roundedBorder).controlSize(.large).padding(.horizontal, 12).accessibilityLabel("搜索 Windows 应用")
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
                        if filtered.isEmpty { Button("清除搜索") { query = "" }.padding(.bottom, 16) }
                    }.frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
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
                    Button("启动设置…") { model.editApplication(app) }
                    Menu {
                        Button("显示 EXE 文件") { model.reveal(app.executablePath) }
                        Button("移除入口（保留文件）", role: .destructive) { model.forgetApplication(app) }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 26).accessibilityLabel("应用的其他操作")
                }
                if let progress = model.applicationProgress(app) { LaunchProgressView(model: model, progress: progress, compact: true) }
                DisclosureGroup("程序路径与启动参数", isExpanded: $detailsExpanded) {
                    VStack(alignment: .leading, spacing: 15) {
                        pathRow("EXE 程序", app.executablePath)
                        pathRow("工作目录", app.workingDirectory)
                        Text("启动参数").font(.caption).foregroundStyle(.secondary)
                        Text(app.arguments.isEmpty ? "无" : app.arguments.joined(separator: "\n")).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        if !FileManager.default.isReadableFile(atPath: app.executablePath) { Label("程序文件不可读，请连接原磁盘或编辑入口。", systemImage: "externaldrive.badge.exclamationmark").foregroundStyle(.orange).font(.caption) }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
                }.font(.system(size: 13, weight: .medium))
                Text("启动普通应用时继承环境原始图形参数。退出请使用程序自己的菜单；关闭 Harbor 不会关闭程序。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(28).frame(maxWidth: 760, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
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
    @State private var advanced = false
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
                DisclosureGroup("可选：工作目录与启动参数", isExpanded: $advanced) {
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
            if let app = model.editingApplication { containerID = app.containerID; name = app.name; executable = app.executablePath; workingDirectory = app.workingDirectory; arguments = app.arguments.joined(separator: "\n"); advanced = true }
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
            Text("选择环境与安装包，然后按安装器提示操作。完成后添加安装好的 EXE，而不是再次添加安装包。").font(.system(size: 13)).foregroundStyle(.secondary)
            Form {
                Picker("1 · 安装到哪个环境", selection: $containerID) { Text("选择已准备的托管环境").tag(UUID?.none); ForEach(model.state.containers.filter { $0.origin == .managed }) { Text($0.name).tag(Optional($0.id)) } }
                HStack { Text(file?.lastPathComponent ?? "请选择 EXE 或 MSI 安装包").lineLimit(2); Spacer(); Button("选择安装包…") { file = Panels.chooseWindowsFile(installer: true) } }
            }.formStyle(.grouped).frame(height: 140)
            if let id = containerID, model.busy.contains(id) || model.pendingLaunch(in: id) != nil {
                Label("这个环境仍在运行。请先保存并正常退出其中的程序。", systemImage: "pause.circle").font(.callout).foregroundStyle(Color.harborWarning)
            } else if let id = containerID, model.runtime[id]?.initialized != true {
                Label("这个环境尚未准备完成。请先到运行环境页继续准备。", systemImage: "info.circle").font(.callout).foregroundStyle(Color.harborWarning)
            }
            Text("许可与登录由你完成。不会启动 Steam，不会自动接受协议或强制重启。").font(.system(size: 12)).foregroundStyle(.secondary)
            if model.state.containers.allSatisfy({ $0.origin != .managed }) { Label("请先在运行环境页创建通用 Windows 环境。", systemImage: "info.circle").foregroundStyle(.orange) }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("运行安装器") {
                if let file, let id = containerID, let container = model.container(id) { dismiss(); model.installApplication(file, container: container); model.section = .applications }
            }.buttonStyle(.borderedProminent).disabled(file == nil || containerID == nil || model.isWorking || containerID.map { model.runtime[$0]?.initialized != true || model.busy.contains($0) || model.pendingLaunch(in: $0) != nil } == true) }
        }.padding(28).frame(width: 620).onAppear {
            if case .install(let id) = model.applicationGuidance { containerID = id }
            else { containerID = model.preferredInstallContainerID ?? model.state.containers.first(where: { $0.origin == .managed })?.id }
        }
    }
}
