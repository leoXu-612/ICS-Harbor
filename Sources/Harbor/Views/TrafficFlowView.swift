import SwiftUI
import HarborCore

struct TrafficFlowView: View {
    @Bindable var monitor: TrafficMonitor
    let applications: [WindowsApplication]
    let application: WindowsApplication?
    @Binding var paused: Bool
    let viewport: CGRect
    @State private var diagramFrame: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedID: String?
    @State private var showAll = false
    private var flows: [TrafficFlow] {
        monitor.flows.filter { flow in
            guard let application else { return true }
            return flow.applicationID == application.id || (flow.applicationID == nil && flow.containerID == application.containerID)
        }
    }
    private var processes: [TrafficProcess] {
        monitor.processes.filter { process in
            guard let application else { return true }
            return process.applicationID == application.id || (process.applicationID == nil && process.containerID == application.containerID)
        }
    }
    private var visibleFlows: [TrafficFlow] {
        Array(flows.sorted {
            let a = $0.downloadBps + $0.uploadBps, b = $1.downloadBps + $1.uploadBps
            if (a > 0) != (b > 0) { return a > 0 }
            if a != b { return a > b }
            let at = Double($0.receivedBytes) + Double($0.sentBytes), bt = Double($1.receivedBytes) + Double($1.sentBytes)
            return at == bt ? $0.id < $1.id : at > bt
        }.prefix(6)).sorted { $0.id < $1.id }
    }
    private var download: Double { flows.reduce(0) { $0 + $1.downloadBps } }
    private var upload: Double { flows.reduce(0) { $0 + $1.uploadBps } }
    private var hasRates: Bool { monitor.failure == nil && monitor.sampledAt != nil && flows.allSatisfy(\.hasRateBaseline) }
    private var live: Bool { !paused && monitor.isSampling && scenePhase == .active && (monitor.sampledAt.map { Date().timeIntervalSince($0) < 6 } ?? false) }
    private func rate(_ bytes: Double) -> String { Self.rate(bytes) }
    static func rate(_ bytes: Double) -> String {
        guard bytes.isFinite, bytes >= 0 else { return "—" }
        if bytes < 0.5 { return "0 B/s" }
        return ByteCountFormatter.string(fromByteCount: Int64(min(bytes, Double(Int64.max).nextDown)), countStyle: .binary) + "/s"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center) { heading; Spacer(); controls }
                VStack(alignment: .leading, spacing: 12) { heading; controls }
            }
            Text(application.map { "范围：\($0.name) 与同环境共享进程" } ?? "范围：所有 Harbor 运行环境")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            HStack(spacing: 0) {
                metric("下载", value: hasRates ? rate(download) : "—", color: .harborSignal)
                metric("上传", value: hasRates ? rate(upload) : "—", color: .harbor)
                metric("进程 CPU", value: monitor.sampledAt == nil ? "—" : String(format: "%.1f%%", processes.reduce(0) { $0 + $1.cpuPercent }), color: .primary)
                metric("进程内存", value: monitor.sampledAt == nil ? "—" : (processes.isEmpty ? "0 B" : ByteCountFormatter.string(fromByteCount: Int64(processes.reduce(UInt64(0)) { $0 + $1.rssBytes }), countStyle: .memory)), color: .primary)
            }
            .opacity(live ? 1 : 0.65)
            if visibleFlows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: processes.isEmpty ? "network" : "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 34, weight: .light)).foregroundStyle(.secondary)
                    Text(monitor.failure != nil ? "暂时无法读取流量" : (processes.isEmpty ? "等待应用连接" : "当前没有网络连接")).font(.headline)
                    Text(monitor.failure ?? (paused ? "已暂停，继续后获取新的流量数据。" : "软件连接网络后，这里会显示真实流向。离线计算不会产生流量。"))
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
                }.frame(maxWidth: .infinity, minHeight: 240)
            } else {
                diagram
                if flows.count > visibleFlows.count {
                    Button("另有 \(flows.count-visibleFlows.count) 条连接 · 查看全部") { showAll = true }.font(.caption)
                }
            }
            if let flow = flows.first(where: { $0.id == selectedID }) { details(flow) }
            HStack(alignment: .top, spacing: 12) {
                Label("下载", systemImage: "arrow.left").foregroundStyle(Color.harborSignal)
                Label("上传", systemImage: "arrow.right").foregroundStyle(Color.harbor)
                Spacer(minLength: 4)
                Text("线宽按对数缩放 · 光点表示方向").foregroundStyle(.secondary)
            }.font(.caption)
            Text("约每 2 秒采样，短连接可能漏采。CPU 100% 约为一个逻辑核；内存为进程 RSS，不含换出页。地址是连接端点，不代表加密内容或最终服务。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(CDSSpacing.base)
        .background(CDSColor.surface2, in: RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: CDSRadius.xl, style: .continuous).strokeBorder(CDSColor.border, lineWidth: 1) }
        .sheet(isPresented: $showAll) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("当前连接").cdsType(18, .semibold); Spacer(); Button("完成") { showAll = false } }
                ScrollView { LazyVStack(alignment: .leading, spacing: 12) { ForEach(flows) { details($0) } } }
            }.padding(24).frame(width: 620, height: 480)
        }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("流量去向").cdsType(15, .semibold)
            HStack(spacing: 6) {
                CDSStatusDot(kind: live ? .live : .idle, size: 5)
                Text(paused ? "已暂停" : monitor.status)
                if let time = monitor.sampledAt { Text(time, style: .time).monospacedDigit() }
            }.font(.caption).foregroundStyle(.secondary)
        }
    }
    private var controls: some View {
        HStack(spacing: 12) {
            Text("\(flows.count) 条连接").font(.caption).foregroundStyle(.secondary)
            Button { paused.toggle() } label: { Label(paused ? "继续" : "暂停", systemImage: paused ? "play.fill" : "pause.fill") }
                .controlSize(.small).accessibilityLabel(paused ? "继续流量采样" : "暂停流量采样")
        }
    }
    private func metric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).cdsType(17, .medium, mono: true).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.75)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var diagram: some View {
        let rows = visibleFlows
        let pids = Array(Set(rows.map(\.pid))).sorted()
        let height = CGFloat(max(rows.count, 3)) * 72 + 40
        return GeometryReader { geo in
            let left: CGFloat = 65, right = geo.size.width - 85
            let sourceY: (Int32) -> CGFloat = { pid in 26 + (height-52) * CGFloat((pids.firstIndex(of: pid) ?? 0)+1) / CGFloat(pids.count+1) }
            let endY: (Int) -> CGFloat = { index in 24 + (height-48) * CGFloat(index+1) / CGFloat(rows.count+1) }
            if geo.size.width < 420 {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { flow in
                        Button { selectedID = selectedID == flow.id ? nil : flow.id } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\(flow.processName) → \(flow.remoteEndpoint)").font(.caption.weight(.medium)).lineLimit(1).truncationMode(.middle)
                                Text(flow.hasRateBaseline ? "↓ \(rate(flow.downloadBps))  ↑ \(rate(flow.uploadBps))" : "建立流量基线…").font(.caption).foregroundStyle(.secondary)
                            }.padding(10).frame(maxWidth:.infinity,alignment:.leading).background(CDSColor.fillTertiary, in: RoundedRectangle(cornerRadius: CDSRadius.md, style: .continuous))
                        }.buttonStyle(.plain)
                    }
                }
            } else {
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1.0/30, paused: reducedMotion || !live || (!rows.contains { $0.hasRateBaseline && $0.downloadBps+$0.uploadBps > 0 }) || !diagramFrame.intersects(viewport))) { timeline in
                    Canvas { context, size in
                        for (index, flow) in rows.enumerated() {
                            let start = CGPoint(x: left+56, y: sourceY(flow.pid)), end = CGPoint(x: right-75, y: endY(index))
                            for (amount, direction, color, shift) in [(flow.uploadBps, 1.0, Color.harbor, -4.0), (flow.downloadBps, -1.0, Color.harborSignal, 4.0)] {
                                let a = CGPoint(x: start.x, y: start.y+shift), b = CGPoint(x: end.x, y: end.y+shift)
                                let c = CGPoint(x: a.x+(b.x-a.x)*0.5, y:a.y), d = CGPoint(x: a.x+(b.x-a.x)*0.5, y:b.y)
                                var path = Path(); path.move(to:a); path.addCurve(to:b,control1:c,control2:d)
                                let width = amount > 0 ? min(8, 1+log2(1+amount/1024)) : 1
                                context.stroke(path, with: .color(color.opacity(selectedID == flow.id ? 0.65 : 0.25)), style: StrokeStyle(lineWidth: width, lineCap:.round))
                                guard amount > 0, flow.hasRateBaseline, live, !reducedMotion else { continue }
                                let count = min(5, max(1, Int(log2(1+amount/4096))))
                                for particle in 0..<count {
                                    var t = (timeline.date.timeIntervalSinceReferenceDate/3 + Double(particle)/Double(count)).truncatingRemainder(dividingBy:1)
                                    if direction < 0 { t = 1-t }
                                    let q = CGFloat(t), u = 1-CGFloat(t)
                                    let w0 = u*u*u, w1 = 3*u*u*q, w2 = 3*u*q*q, w3 = q*q*q
                                    let x: CGFloat = w0*a.x + w1*c.x + w2*d.x + w3*b.x
                                    let y: CGFloat = w0*a.y + w1*c.y + w2*d.y + w3*b.y
                                    let point = CGPoint(x:x, y:y)
                                    context.fill(Path(ellipseIn:CGRect(x:point.x-2,y:point.y-2,width:4,height:4)),with:.color(color.opacity(0.9)))
                                }
                            }
                        }
                    }
                }.accessibilityHidden(true)
                ForEach(pids, id: \.self) { pid in
                    if let flow = rows.first(where: { $0.pid == pid }) {
                        VStack(spacing: 6) {
                            if let app = applications.first(where: { $0.id == flow.applicationID }) { WindowsApplicationIcon(executablePath: app.executablePath) }
                            else { Image(systemName:"gearshape.2").font(.title2).foregroundStyle(.secondary).frame(height:32) }
                            Text(flow.applicationID == nil ? "共享 · \(flow.processName)" : flow.processName).font(.caption.weight(.medium)).lineLimit(1)
                        }.frame(width:118).position(x:left,y:sourceY(pid))
                    }
                }
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, flow in
                    Button { withAnimation(reducedMotion ? nil : .spring(response:0.35,dampingFraction:0.88)) { selectedID = selectedID == flow.id ? nil : flow.id } } label: {
                        VStack(alignment:.leading,spacing:5) {
                            Text(flow.remoteEndpoint).font(.system(size:11,weight:.medium,design:.monospaced)).lineLimit(1).truncationMode(.middle)
                            Text(flow.hasRateBaseline ? "↓ \(rate(flow.downloadBps))  ↑ \(rate(flow.uploadBps))" : "建立流量基线…").font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                        }.padding(9).frame(width:154,alignment:.leading)
                            .background(selectedID == flow.id ? CDSColor.claySubtle : CDSColor.surface3, in: RoundedRectangle(cornerRadius: CDSRadius.md, style: .continuous))
                            .overlay { RoundedRectangle(cornerRadius: CDSRadius.md, style: .continuous).strokeBorder(selectedID == flow.id ? CDSColor.clay : CDSColor.border, lineWidth: 1) }
                    }.buttonStyle(.plain).help("查看 \(flow.remoteEndpoint) 连接详情")
                        .accessibilityLabel(flow.hasRateBaseline && monitor.failure == nil ? "\(flow.processName) 到 \(flow.remoteEndpoint)，下载 \(rate(flow.downloadBps))，上传 \(rate(flow.uploadBps))" : "\(flow.processName) 到 \(flow.remoteEndpoint)，速率暂不可用")
                        .position(x:right,y:endY(index))
                }
            }
            }
        }.frame(height:height)
            .background(GeometryReader { geometry in Color.clear.preference(key: TrafficDiagramFrameKey.self, value: geometry.frame(in:.global)) })
            .onPreferenceChange(TrafficDiagramFrameKey.self) { diagramFrame = $0 }
    }
    private func details(_ flow: TrafficFlow) -> some View {
        VStack(alignment:.leading,spacing:7) {
            Text("\(flow.processName) · \(flow.transport.uppercased()) · PID \(flow.pid)").font(.caption.weight(.semibold))
            Text(flow.hasRateBaseline && monitor.failure == nil ? "下载 \(rate(flow.downloadBps)) · 上传 \(rate(flow.uploadBps))" : "速率暂不可用").font(.caption).foregroundStyle(.secondary)
            Text("本地  \(flow.localEndpoint)\n远端  \(flow.remoteEndpoint)").font(.system(.caption,design:.monospaced)).textSelection(.enabled)
            Text("观察期间：收到 \(ByteCountFormatter.string(fromByteCount:Int64(clamping:flow.receivedBytes),countStyle:.binary)) · 发出 \(ByteCountFormatter.string(fromByteCount:Int64(clamping:flow.sentBytes),countStyle:.binary))")
                .font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading).padding(12).background(CDSColor.fillTertiary, in: RoundedRectangle(cornerRadius: CDSRadius.md, style: .continuous))
    }
}

private struct TrafficDiagramFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}
