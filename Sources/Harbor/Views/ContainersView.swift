import SwiftUI
import HarborCore

struct ContainersView: View {
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CDSSpacing.roomy) {
                CDSPageHeader(title: "运行环境",
                              subtitle: "查看哪些内容共用一个 Wine 环境，并分别维护引擎、磁盘与图形参数。") {
                    Menu {
                        Button("创建新环境…") { model.presentCreate() }
                        Button("关联已有环境…") { model.linkContainer() }
                    } label: {
                        Label("添加环境", systemImage: "plus")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderedProminent)
                    .tint(CDSColor.clay)
                    .controlSize(.large)
                    .fixedSize()
                }

                if model.state.containers.isEmpty {
                    TaskHint(title: "还没有运行环境",
                             message: "新环境用于独立安装；已有 Sikarugir 环境只需关联，不要重建。",
                             symbol: "shippingbox",
                             actionTitle: "创建环境") { model.presentCreate() }
                    Button("我已有环境，直接关联…") { model.linkContainer() }
                        .cdsButton(.ghost, size: .sm)
                }

                ForEach(model.state.containers) { container in
                    EnvironmentCard(model: model, container: container)
                }

                CDSHairline().padding(.top, 4)

                Button("不确定该怎么做？查看使用指南", systemImage: "questionmark.circle") { model.section = .guide }
                    .cdsButton(.ghost, size: .sm)
            }
            .padding(CDSSpacing.page)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .background(CDSColor.surface1)
    }
}

struct BindDriveView: View {
    @Bindable var model: AppModel
    var fixedContainer: ContainerRecord? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var selectedContainer: UUID?
    @State private var volumeID = ""
    @State private var letter = "P"

    var body: some View {
        VStack(alignment: .leading, spacing: CDSSpacing.base) {
            sheetHeader(title: "绑定外置磁盘",
                        subtitle: "保存磁盘唯一标识，重连后自动恢复缺失映射。若盘符已有其他目标，Harbor 会保留原映射并说明原因。",
                        symbol: "externaldrive.badge.plus")

            Form {
                if let fixedContainer {
                    LabeledContent("运行环境", value: fixedContainer.name)
                } else {
                    Picker("运行环境", selection: $selectedContainer) {
                        ForEach(model.state.containers) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Picker("磁盘", selection: $volumeID) {
                    Text("选择已挂载磁盘").tag("")
                    ForEach(model.volumes.filter { $0.path != "/Volumes/Macintosh HD" }) {
                        Text($0.name).tag($0.id)
                    }
                }
                Picker("Wine 盘符", selection: $letter) {
                    ForEach(["P", "Q", "R", "S", "T", "U", "V", "W"], id: \.self) { Text($0 + ":").tag($0) }
                }
            }
            .formStyle(.grouped)

            if model.volumes.filter({ $0.path != "/Volumes/Macintosh HD" }).isEmpty {
                Label("没有发现外置磁盘，请先连接磁盘。", systemImage: "cable.connector")
                    .font(.system(size: 11))
                    .foregroundStyle(CDSColor.warning)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }.cdsButton(.ghost, size: .md)
                Button("检查并绑定") {
                    if let id = fixedContainer?.id ?? selectedContainer,
                       let container = model.container(id),
                       let volume = model.volumes.first(where: { $0.id == volumeID }) {
                        model.bindDrive(container: container, letter: letter, volume: volume)
                        if fixedContainer != nil { dismiss() }
                    }
                }
                .cdsButton(.primary, size: .md)
                .disabled((fixedContainer == nil && selectedContainer == nil) || volumeID.isEmpty || model.isWorking)
            }
        }
        .padding(CDSSpacing.section)
        .frame(width: 520)
        .background(CDSColor.surface1)
        .onAppear { selectedContainer = fixedContainer?.id ?? model.state.containers.first?.id }
    }
}
