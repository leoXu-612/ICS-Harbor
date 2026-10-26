import SwiftUI
import HarborCore

struct ContainersView: View {
    @Bindable var model: AppModel
    @State private var drivesExpanded = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 20) {
                    PageHeading(title: "运行环境", subtitle: "Steam 的启动与退出集中在这里。已有游戏和应用从各自资料库打开。")
                    Spacer()
                    Menu {
                        Button("创建新环境…") { model.presentCreate() }
                        Button("关联已有环境…") { model.linkContainer() }
                    } label: { Label("添加环境", systemImage: "plus") }.controlSize(.large).fixedSize()
                }
                if model.state.containers.isEmpty {
                    TaskHint(title: "还没有运行环境", message: "新环境用于独立安装；已有 Sikarugir 环境只需关联，不要重建。", symbol: "shippingbox", actionTitle: "创建环境") { model.presentCreate() }
                    Button("我已有环境，直接关联…") { model.linkContainer() }.buttonStyle(.link)
                }
                ForEach(model.state.containers) { container in EnvironmentCard(model: model, container: container) }
                Divider().padding(.top, 8)
                DisclosureGroup("外置盘与盘符 · 高级维护", isExpanded: $drivesExpanded) {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("已有映射可继续使用，不需要为新版重新绑定。这里只创建缺失链接，不替换已有盘符，也不会登记或删除 Steam 游戏库。")
                            .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        ForEach(model.state.bindings) { binding in
                            HStack {
                                Label("\(binding.volumeName) → \(binding.letter):", systemImage: "externaldrive").font(.callout)
                                Spacer(); Button("检查并恢复") { model.repair(binding) }.disabled(DriveMapper.target(for: binding, volumes: model.volumes) == nil)
                            }
                        }
                        Button("绑定缺失盘符…", systemImage: "link.badge.plus") { model.showBind = true }.disabled(model.state.containers.isEmpty).controlSize(.large)
                    }.padding(.top, 16)
                }.font(.system(size: 14, weight: .medium))
                Button("不确定该怎么做？查看使用指南", systemImage: "questionmark.circle") { model.section = .guide }.buttonStyle(.link).font(.system(size: 13))
            }.padding(28).frame(maxWidth: 1100, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
        }
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
                Label("没有发现外置磁盘，请先连接磁盘。", systemImage: "cable.connector").foregroundStyle(Color.harborWarning).font(.callout)
            }
            HStack { Spacer(); Button("取消") { dismiss() }.keyboardShortcut(.cancelAction); Button("检查并绑定") {
                if let id = selectedContainer, let container = model.container(id), let volume = model.volumes.first(where: { $0.id == volumeID }) { model.bindDrive(container: container, letter: letter, volume: volume) }
            }.buttonStyle(.borderedProminent).disabled(selectedContainer == nil || volumeID.isEmpty) }
        }.padding(28).frame(width: 510).onAppear { selectedContainer = model.state.containers.first?.id }
    }
}
