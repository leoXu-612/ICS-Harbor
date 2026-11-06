import SwiftUI
import HarborCore

struct ContentView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 196, ideal: 212, max: 252)
        } detail: {
            detail
        }
        .navigationTitle("")
        .frame(minWidth: 1000, minHeight: 680)
        .tint(CDSColor.clay)
        .sheet(isPresented: $model.showCreate) { CreateContainerView(model: model) }
        .sheet(isPresented: $model.showBind) { BindDriveView(model: model) }
        .sheet(isPresented: $model.showAddApplication) { ApplicationEditor(model: model) }
        .sheet(isPresented: $model.showInstallApplication) { InstallApplicationView(model: model) }
        .alert("操作未完成", isPresented: Binding(get: { model.errorMessage != nil },
                                              set: { if !$0 { model.errorMessage = nil } })) {
            Button("知道了") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    // MARK: 侧边栏

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brand
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    navGroup("资料库", items: [.library])
                    navGroup("来源", items: [.steam, .local, .epic, .gog])
                    navGroup("管理", items: [.containers, .activity])
                    navGroup("帮助", items: [.guide, .presets])
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            Spacer(minLength: 8)
            footer
        }
        .background { FluoriteBackdrop(tone: CDSColor.surface0) }
    }

    private var brand: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: CDSRadius.panel, style: .continuous)
                    .fill(CDSColor.claySubtle)
                Image(systemName: "sailboat.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(CDSColor.clay)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Harbor").cdsType(15, .semibold, tracking: -0.2)
                Text("来源中心").cdsType(10).foregroundStyle(CDSColor.textMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private func navGroup(_ title: String, items: [AppSection]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .cdsType(9.5, .medium, tracking: 0.6)
                .foregroundStyle(CDSColor.textMuted)
                .padding(.horizontal, 9)
                .padding(.bottom, 4)

            ForEach(items) { item in
                SidebarRow(
                    item: item,
                    selected: model.section == item,
                    note: sidebarNote(item)
                ) {
                    model.navigate(item)
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            CDSHairline(inset: 4)

            if !model.conflictingLibraries.isEmpty {
                Button {
                    model.section = .containers
                } label: {
                    HStack(spacing: 6) {
                        CDSStatusDot(kind: .fault, size: 5)
                        Text("有库冲突待处理").cdsType(10.5, .medium)
                    }
                    .foregroundStyle(CDSColor.fault)
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            } else {
                HStack(spacing: 6) {
                    CDSStatusDot(kind: .live, size: 5)
                    Text("索引保留在本机").cdsType(10.5).foregroundStyle(CDSColor.textSecondary)
                }
                .padding(.leading, 4)
            }

            Text("\(model.games.count + model.applications.count) 个条目 · \(model.state.containers.count) 个环境")
                .cdsType(10)
                .foregroundStyle(CDSColor.textMuted)
                .padding(.leading, 4)

            HStack(spacing: 10) {
                SettingsLink {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape").font(.system(size: 11))
                        Text("设置").cdsType(11.5, .medium)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(CDSColor.textSecondary)

                Spacer(minLength: 0)

                Text(AppPaths.version)
                    .cdsType(10, mono: true)
                    .foregroundStyle(CDSColor.textMuted)
            }
            .padding(.leading, 4)
            .padding(.top, 1)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 16)
        .padding(.top, 8)
    }

    // MARK: 详情区

    private var detail: some View {
        VStack(spacing: 0) {
            if let progress = model.currentLaunch, model.section != .activity,
               !(catalogVisible && progress.applicationID != nil && progress.applicationID == model.selectedApplicationID) {
                LaunchProgressView(model: model, progress: progress, compact: true)
                    .padding(.horizontal, CDSSpacing.page)
                    .padding(.top, 16)
                    .padding(.bottom, 2)
            }

            if let notice = model.notice {
                CDSNotice(text: notice, onClose: { model.notice = nil })
                    .padding(.horizontal, CDSSpacing.page)
                    .padding(.top, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Group {
                switch model.section {
                case .library: UnifiedCatalogView(model: model, source: nil)
                case .steam, .local, .epic, .gog:
                    if let source = model.section.source { sourcePage(source) }
                case .containers: ContainersView(model: model)
                case .presets: PresetsView(model: model)
                case .activity: ActivityView(model: model)
                case .guide: GuideView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.isWorking {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small).tint(CDSColor.clay)
                    Text(model.activeStage)
                        .cdsType(11)
                        .foregroundStyle(CDSColor.textSecondary)
                        .lineLimit(2)
                    Spacer()
                    Button("查看进度") { model.section = .activity }
                        .cdsButton(.ghost, size: .xs)
                }
                .padding(.horizontal, CDSSpacing.roomy)
                .padding(.vertical, 9)
                .background(CDSColor.surface0)
                .overlay(alignment: .top) { CDSHairline() }
            }
        }
        .background(CDSColor.surface1)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("重新读取环境与磁盘状态")
                .disabled(model.isRefreshing)

                Button { model.section = .guide } label: {
                    Label("使用指南", systemImage: "questionmark.circle")
                }
                .labelStyle(.titleAndIcon)

                Menu {
                    Button("安装 Windows 软件…", systemImage: "shippingbox") {
                        model.openSourceSettings(.local)
                        model.guideApplicationSetup()
                    }
                    Button("添加已有 EXE…", systemImage: "app.badge") { model.addApplication() }
                        .disabled(model.state.containers.isEmpty)
                    Divider()
                    Button("创建运行环境…", systemImage: "plus.rectangle.on.folder") { model.presentCreate() }
                    Button("关联现有 Wine 环境…", systemImage: "link") { model.linkContainer() }
                } label: {
                    Label("添加", systemImage: "plus")
                }
                .labelStyle(.titleAndIcon)
                .help("添加应用或运行环境")

            }
        }
    }

    private var catalogVisible: Bool {
        model.section == .library || (model.section.source?.isAvailable == true && !model.sourceSettingsVisible)
    }

    private func sidebarNote(_ section: AppSection) -> String? {
        switch section {
        case .steam: String(model.games.count)
        case .local: String(model.applications.count)
        case .epic, .gog: "规划中"
        case .activity: model.pendingLaunchCount > 0 ? String(model.pendingLaunchCount) : nil
        default: nil
        }
    }

    @ViewBuilder private func sourcePage(_ source: CatalogSource) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: source.symbol).foregroundStyle(CDSColor.clay)
                Text(source.title).cdsType(17, .semibold)
                Spacer()
                if source.isAvailable {
                    SourceTabs(settings: $model.sourceSettingsVisible)
                } else {
                    Text("规划中").cdsType(12).foregroundStyle(CDSColor.textSecondary)
                }
            }
            .padding(.horizontal, 22)
            .frame(height: 51)
            CDSHairline()
            if model.sourceSettingsVisible || !source.isAvailable {
                SourceManagementView(model: model, source: source)
            } else {
                UnifiedCatalogView(model: model, source: source)
            }
        }
        .id(source)
    }
}

// Amicro snappy preset, translated to a native matched-geometry selection.
// Upstream revision and MIT notice: THIRD_PARTY_NOTICES.md.
private struct SourceTabs: View {
    @Binding var settings: Bool
    @Namespace private var highlight
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        HStack(spacing: 1) {
            tab("内容", false)
            tab("接入设置", true)
        }
        .padding(3)
        .background(CDSColor.surface0, in: Capsule())
    }

    private func tab(_ title: String, _ value: Bool) -> some View {
        Button {
            withAnimation(reduced ? nil : .interpolatingSpring(mass: 0.8, stiffness: 400, damping: 28, initialVelocity: 0)) {
                settings = value
            }
        } label: {
            Text(title).cdsType(12, value == settings ? .semibold : .regular)
                .foregroundStyle(value == settings ? CDSColor.clay : CDSColor.textSecondary)
                .padding(.horizontal, 13).frame(height: 25)
                .background {
                    if value == settings {
                        Capsule().fill(CDSColor.claySubtle).matchedGeometryEffect(id: "tab", in: highlight)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(value == settings ? .isSelected : [])
    }
}

// MARK: - 侧栏行

private struct SidebarRow: View {
    let item: AppSection
    let selected: Bool
    let note: String?
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: item.symbol)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? CDSColor.clay : CDSColor.textSecondary)
                    .frame(width: 16)
                Text(item.title)
                    .cdsType(12.5, selected ? .medium : .regular)
                    .foregroundStyle(selected ? CDSColor.textPrimary : CDSColor.textSecondary)
                Spacer(minLength: 4)
                if let note {
                    Text(note)
                        .cdsType(10, .medium, mono: true)
                        .foregroundStyle(CDSColor.clay)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(CDSColor.claySubtle, in: Capsule())
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(
                selected ? CDSColor.claySubtle
                         : hovering ? CDSColor.fillGhostHover : .clear,
                in: RoundedRectangle(cornerRadius: CDSRadius.lg, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: CDSRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(CDSMotion.honoring(reduceMotion, CDSMotion.press), value: hovering)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
