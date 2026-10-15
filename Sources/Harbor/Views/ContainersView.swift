import SwiftUI
import HarborCore

struct ContainersView: View {
    @Bindable var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    PageHeading(title: "运行环境", subtitle: "统一管理 Windows 环境。应用与游戏各自保留独立入口。")
                    Spacer()
                    Button("创建环境", systemImage: "plus") { model.showCreate = true }.buttonStyle(.borderedProminent)
                }
                if model.state.containers.isEmpty {
                    EmptyState(symbol: "shippingbox", title: "还没有运行环境", message: "关联现有 Wine 容器，或创建新的独立环境。")
                    Button("关联现有环境…") { model.linkContainer() }
                }
                ForEach(model.state.containers) { container in
                    Surface {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack(spacing: 12) {
                                Image(systemName: container.origin == .managed ? "shippingbox.fill" : "link")
                                    .font(.system(size: 22)).foregroundStyle(Color.harbor)
                                    .frame(width: 42, height: 42).background(Color.harbor.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(container.name).font(.system(size: 15, weight: .semibold))
                                    Text(container.origin == .linked ? (model.canCustomize(container) ? "关联环境 · 图形参数可回退管理" : "关联环境 · 保护原配置") : "Harbor 托管环境").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Pill(title: model.runtime[container.id] == nil ? "待检查" : model.busy.contains(container.id) ? "后台运行" : "已停止", color: model.busy.contains(container.id) ? .harborSignal : .secondary)
                                Menu {
                                    if model.canCustomize(container) {
                                        Button("恢复原始图形参数…", systemImage: "arrow.uturn.backward") { model.restoreRuntimeParameters(container) }.disabled(model.busy.contains(container.id))
                                    } else {
                                        Button("备份并允许图形参数管理…", systemImage: "slider.horizontal.3") { model.authorizeRuntimeParameters(container) }.disabled(model.busy.contains(container.id))
                                    }
                                    if container.origin == .managed { Button("结束此环境…", role: .destructive) { model.endManagedRuntime(container) }.disabled(!model.busy.contains(container.id) || model.isWorking) }
                                    Button("移除记录（保留文件）", role: .destructive) { model.forgetContainer(container) }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24).help("环境操作")
                            }
                            HStack(spacing: 22) {
                                detail("图形后端", model.runtime[container.id]?.renderer ?? "待检查")
                                detail("运行引擎", model.runtime[container.id]?.engine ?? "待检查")
                            }
                            Divider()
                            if model.runtime[container.id]?.initialized != true && container.origin == .managed {
                                Button("准备 / 重试此环境") { model.provision(container) }.disabled(model.isWorking || model.busy.contains(container.id))
                            }
                            if model.runtime[container.id]?.hasSteam == true || container.preparesSteam {
                                SteamSessionControls(model: model, container: container)
                            } else {
                                Label("通用 Windows 环境 · 无需 Steam", systemImage: "app").font(.callout)
                                DisclosureGroup("可选：添加 Steam") { SteamSessionControls(model: model, container: container).padding(.top, 8) }
                            }
                            let libraries = model.libraries.filter { $0.containerID == container.id }
                            if !libraries.isEmpty {
                                Divider()
                                Text("Steam 游戏库").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                ForEach(libraries) { library in
                                    HStack(spacing: 11) {
                                        Image(systemName: library.drive == "C" ? "internaldrive" : "externaldrive").foregroundStyle(.secondary).frame(width: 22)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("\(volumeName(library)) · \(library.drive):").font(.callout.weight(.medium))
                                            Text(library.windowsPath).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        Text("\(library.registeredCount) 款").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                        Pill(title: model.conflictingLibraries.contains(library.id) ? "共用库风险" : library.isOnline ? "已登记 · 可读取" : "离线或不可读",
                                             color: model.conflictingLibraries.contains(library.id) ? .red : library.isOnline ? .harborSignal : .orange)
                                    }
                                }
                            }
                            HStack {
                                Button("显示环境文件", systemImage: "folder") { model.reveal(container.wrapperPath) }
                                Spacer()
                                if container.origin == .linked { Label(model.canCustomize(container) ? "原始参数已有备份" : "原设置保留", systemImage: "lock.shield").font(.caption).foregroundStyle(.secondary) }
                            }.controlSize(.small)
                        }
                    }
                }
                HStack {
                    PageHeading(title: "外置盘映射", subtitle: "按磁盘标识绑定 Wine 盘符，避免认错同名磁盘。")
                    Spacer()
                    Button("绑定盘符…", systemImage: "link.badge.plus") { model.showBind = true }.disabled(model.state.containers.isEmpty)
                }.padding(.top, 8)
                Surface {
                    if model.state.bindings.isEmpty {
                        HStack(spacing: 14) {
                            Image(systemName: "externaldrive.badge.plus").font(.title).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 5) {
                                Text("尚未保存固定绑定").font(.callout.weight(.medium))
                                Text("现有映射仍可使用。新绑定只建立缺失链接，不覆盖其他盘符。").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    } else {
                        VStack(spacing: 14) {
                            ForEach(model.state.bindings) { binding in
                                HStack {
                                    Label(binding.volumeName, systemImage: "externaldrive").font(.callout.weight(.medium))
                                    Text("→ \(binding.letter):").font(.caption.monospaced()).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("检查并恢复") { model.repair(binding) }.disabled(DriveMapper.target(for: binding, volumes: model.volumes) == nil)
                                }
                            }
                        }
                    }
                }
                Label("盘符映射不等于 Steam 库登记。不要让 Mac 原生 Steam 与 Wine 共用同一个库目录。", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(24)
        }
    }
    private func volumeName(_ library: LibraryRecord) -> String {
        if library.drive == "C" { return "内置目录" }
        if let path = library.unixPath, let volume = model.volumes.first(where: { path == $0.path || path.hasPrefix($0.path + "/") }) { return volume.name }
        return library.mappedTarget.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "未映射磁盘"
    }
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BindDriveView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedContainer: UUID?
    @State private var volumeID = ""
    @State private var letter = "P"
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Label("绑定外置磁盘", systemImage: "externaldrive.badge.plus").font(.title2.weight(.bold))
            Text("只建立缺失映射。若该盘符已有其他目标，Harbor 会停止并说明原因。").font(.callout).foregroundStyle(.secondary)
            Form {
                Picker("容器", selection: $selectedContainer) { ForEach(model.state.containers) { Text($0.name).tag(Optional($0.id)) } }
                Picker("磁盘", selection: $volumeID) {
                    Text("选择已挂载磁盘").tag("")
                    ForEach(model.volumes.filter { $0.path != "/Volumes/Macintosh HD" }) { Text($0.name).tag($0.id) }
                }
                Picker("Wine 盘符", selection: $letter) { ForEach(["P", "Q", "R", "S", "T", "U", "V", "W"], id: \.self) { Text($0 + ":").tag($0) } }
            }.formStyle(.grouped)
            if model.volumes.filter({ $0.path != "/Volumes/Macintosh HD" }).isEmpty {
                Label("没有发现外置磁盘，请先连接磁盘。", systemImage: "cable.connector").foregroundStyle(.orange).font(.callout)
            }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("检查并绑定") {
                if let id = selectedContainer, let container = model.container(id), let volume = model.volumes.first(where: { $0.id == volumeID }) { model.bindDrive(container: container, letter: letter, volume: volume) }
            }.buttonStyle(.borderedProminent).disabled(selectedContainer == nil || volumeID.isEmpty) }
        }.padding(28).frame(width: 510).onAppear { selectedContainer = model.state.containers.first?.id }
    }
}
