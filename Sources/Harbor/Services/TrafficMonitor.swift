import Foundation
import Observation
import OSLog
import Darwin
import HarborCore

@MainActor @Observable final class TrafficMonitor {
    var flows: [TrafficFlow] = []
    var processes: [TrafficProcess] = []
    var status: String = "等待采样"
    var sampledAt: Date?
    var isSampling: Bool = false
    var failure: String?

    @ObservationIgnored private let logger = Logger(subsystem: "local.harbor.desktop", category: "Traffic")
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var containers: [ContainerRecord] = []
    @ObservationIgnored private var applications: [WindowsApplication] = []

    func start(containers: [ContainerRecord], applications: [WindowsApplication]) {
        if task != nil, self.containers == containers, self.applications == applications { return }
        stop()
        if self.containers != containers || self.applications != applications {
            flows = []; processes = []; sampledAt = nil
        }
        self.containers = containers; self.applications = applications
        failure = nil; status = "等待采样"
        // A paused snapshot is useful, but its rates are no longer current.
        flows = flows.map { flow in
            var flow = flow
            flow.hasRateBaseline = false; flow.downloadBps = 0; flow.uploadBps = 0
            return flow
        }
        logger.debug("Traffic observation started")
        let token = generation
        task = Task.detached(priority: .utility) { [weak self] in
            let scope = TrafficScope(containers: containers, applications: applications)
            var reducer = TrafficRateReducer()
            while !Task.isCancelled {
                let began = ProcessInfo.processInfo.systemUptime
                do {
                    let sample = try await TrafficSampler.sample(scope)
                    try Task.checkCancellation()
                    let measurements = reducer.reduce(sample.snapshot, identities: sample.identities, at: sample.uptime)
                    guard await self?.publish(sample, flows: measurements.map(\.flow), token: token) == true else { return }
                } catch {
                    if Task.isCancelled { return }
                    reducer.invalidate()
                    guard await self?.publishFailure(error, token: token) == true else { return }
                }
                // Start-to-start cadence; no overlapping ps/nettop processes.
                let delay = max(0.05, 2 - (ProcessInfo.processInfo.systemUptime - began))
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            }
        }
    }

    func stop() {
        if task != nil { logger.debug("Traffic observation stopped") }
        generation = UUID()
        task?.cancel(); task = nil
        isSampling = false
        status = sampledAt == nil ? "等待采样" : "已暂停"
        // Deliberately retain the last snapshot and its timestamp for the UI.
    }

    deinit { task?.cancel() }

    private func publish(_ sample: TrafficSample, flows: [TrafficFlow], token: UUID) -> Bool {
        guard token == generation else { return false }
        self.flows = flows; processes = sample.processes; sampledAt = sample.date
        failure = nil; isSampling = true
        if processes.isEmpty { status = "暂无运行中的 Windows 程序" }
        else if flows.isEmpty { status = "实时采样 · 暂无网络连接" }
        else if flows.contains(where: { !$0.hasRateBaseline }) { status = "等待采样 · 正在建立速率基线" }
        else { status = "实时采样" }
        return true
    }

    private func publishFailure(_ error: Error, token: UUID) -> Bool {
        guard token == generation else { return false }
        isSampling = false
        if failure == nil { logger.error("Traffic sampling unavailable") }
        failure = (error as? TrafficSamplingError)?.message ?? "无法解析系统采样结果；未将未知数据视为零。"
        status = sampledAt == nil ? "采样不可用" : "采样不可用 · 上次结果已过期"
        return true
    }
}

private enum TrafficSamplingError: Error {
    case launch, command, timeout, outputLimit, ownership, processLimit, enumeration
    var message: String {
        switch self {
        case .launch: return "无法启动系统采样工具。"
        case .command: return "系统采样工具未成功返回（可能受权限或系统限制）；不会请求提权。"
        case .timeout: return "系统采样超时，已终止本次采样工具。"
        case .outputLimit: return "采样输出超过安全上限，本次结果未采用。"
        case .ownership: return "多个环境共用同一运行时路径，无法可靠确认进程归属。"
        case .processLimit: return "运行时进程数量超过单次采样上限，本次未采样。"
        case .enumeration: return "无法完整读取系统进程列表。"
        }
    }
}

private struct TrafficScope: Sendable {
    var engineRoots: [UUID: String] = [:]
    var applicationPaths: [UUID: [UUID: String]] = [:]
    init(containers: [ContainerRecord], applications: [WindowsApplication]) {
        for container in containers {
            engineRoots[container.id] = URL(fileURLWithPath: container.wrapperPath + "/Contents/SharedSupport/wine")
                .standardizedFileURL.resolvingSymlinksInPath().path
            var paths: [UUID: String] = [:]
            for application in applications where application.containerID == container.id {
                if let path = try? WindowsCommand.windowsPath(URL(fileURLWithPath: application.executablePath), container: container) {
                    paths[application.id] = path
                }
            }
            applicationPaths[container.id] = paths
        }
    }
}

private struct TrafficKernelIdentity: Equatable, Sendable {
    var startKey: String
    var executable: String

    static func read(_ pid: Int32) -> Self? {
        func start() -> String? {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            return "\(info.pbi_start_tvsec).\(info.pbi_start_tvusec)"
        }
        guard let before = start() else { return nil }
        var buffer = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = URL(fileURLWithPath: String(cString: buffer)).standardizedFileURL.resolvingSymlinksInPath().path
        guard start() == before else { return nil }
        return Self(startKey: before, executable: path)
    }
}

private struct TrafficSample: Sendable {
    var snapshot: NettopSnapshot
    var identities: [Int32: TrafficIdentity]
    var processes: [TrafficProcess]
    var uptime: TimeInterval
    var date: Date
}

private enum TrafficSampler {
    static func sample(_ scope: TrafficScope) async throws -> TrafficSample {
        try Task.checkCancellation()
        if scope.engineRoots.isEmpty { return empty() }
        // Read kernel identity before ps, then verify after ps AND after nettop.
        // A recycled PID cannot inherit a previous process's command or counters.
        let count = proc_listallpids(nil, 0)
        guard count > 0, count < 65536 else { throw TrafficSamplingError.enumeration }
        var pids = [Int32](repeating: 0, count: Int(count) + 1024)
        let capacity = pids.count
        let bytes = Int32(capacity * MemoryLayout<Int32>.stride)
        let actual = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, bytes) }
        guard actual > 0, actual < capacity else { throw TrafficSamplingError.enumeration }
        var known: [Int32: (kernel: TrafficKernelIdentity, containerID: UUID)] = [:]
        for pid in pids.prefix(Int(actual)) where pid > 0 {
            try Task.checkCancellation()
            guard let kernel = TrafficKernelIdentity.read(pid) else { continue }
            let matches = scope.engineRoots.filter { kernel.executable.hasPrefix($0.value + "/") }
            guard matches.count <= 1 else { throw TrafficSamplingError.ownership }
            if let containerID = TrafficAttribution.containerID(executablePath: kernel.executable, engineRoots: scope.engineRoots) {
                known[pid] = (kernel, containerID)
            }
        }
        guard known.count <= 256 else { throw TrafficSamplingError.processLimit }
        guard !known.isEmpty else { return empty() }
        let ps = try await TrafficCommand.run("/bin/ps", arguments: ["-ww", "-p", known.keys.sorted().map(String.init).joined(separator: ","), "-o", "pid=,%cpu=,rss=,comm="], timeout: 1.5, outputLimit: 1024 * 1024, allowedExitCodes: [0, 1])
        let rows = try TrafficProcessSample.parsePS(ps)
        var identities: [Int32: TrafficIdentity] = [:]
        var processes: [TrafficProcess] = []
        for row in rows {
            guard let owned = known[row.pid], TrafficKernelIdentity.read(row.pid) == owned.kernel else { continue }
            let appID = TrafficAttribution.applicationID(command: row.command, paths: scope.applicationPaths[owned.containerID] ?? [:])
            let name = row.command.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? row.command
            identities[row.pid] = TrafficIdentity(pid: row.pid, startKey: owned.kernel.startKey, processName: name, containerID: owned.containerID, applicationID: appID)
            processes.append(TrafficProcess(id: row.pid, name: name, containerID: owned.containerID, applicationID: appID, cpuPercent: row.cpuPercent, rssBytes: row.rssBytes))
        }
        // An empty/partial ps result is not evidence of an exited process if the
        // same kernel identity still exists: treat missing metrics as unavailable.
        for (pid, owned) in known where identities[pid] == nil {
            if TrafficKernelIdentity.read(pid) == owned.kernel { throw TrafficSamplingError.command }
        }
        guard !identities.isEmpty else { return empty() }
        var arguments = ["-n", "-x", "-L", "1", "-J", "bytes_in,bytes_out"]
        for pid in identities.keys.sorted() { arguments += ["-p", String(pid)] }
        let csv = try await TrafficCommand.run("/usr/bin/nettop", arguments: arguments, timeout: 3, outputLimit: 4 * 1024 * 1024)
        let uptime = ProcessInfo.processInfo.systemUptime
        let date = Date()
        let snapshots = try NettopParser.parse(csv)
        // -L 1 must yield exactly one snapshot; no invented interval between headers.
        guard snapshots.count == 1, let snapshot = snapshots.first else { throw TrafficTelemetryError.invalidSnapshot }
        for pid in Array(identities.keys) {
            if TrafficKernelIdentity.read(pid) != known[pid]?.kernel { identities.removeValue(forKey: pid) }
        }
        processes.removeAll { identities[$0.id] == nil }
        return TrafficSample(snapshot: snapshot, identities: identities, processes: processes.sorted { $0.id < $1.id }, uptime: uptime, date: date)
    }

    private static func empty() -> TrafficSample {
        TrafficSample(snapshot: NettopSnapshot(connections: []), identities: [:], processes: [], uptime: ProcessInfo.processInfo.systemUptime, date: Date())
    }
}

/// A single owned child with bounded memory and lifetime. The serial reader runs
/// off the main actor and Swift's cooperative executor; cancellation sends TERM
/// immediately and escalates to KILL after 150 ms. No shell or privilege helper.
private final class TrafficCommand: @unchecked Sendable {
    private let lock = NSLock()
    private var child: Process?
    private var cancelled = false

    static func run(_ executable: String, arguments: [String], timeout: TimeInterval, outputLimit: Int, allowedExitCodes: Set<Int32> = [0]) async throws -> String {
        let command = TrafficCommand()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do { continuation.resume(returning: try command.execute(executable, arguments: arguments, timeout: timeout, outputLimit: outputLimit, allowedExitCodes: allowedExitCodes)) }
                    catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { command.cancel() }
    }

    private func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        if let child, child.isRunning { child.terminate() }
    }
    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    private func execute(_ executable: String, arguments: [String], timeout: TimeInterval, outputLimit: Int, allowedExitCodes: Set<Int32>) throws -> String {
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = pipe; process.standardError = pipe
        // Diagnostics must invalidate the sample, even if a tool exits zero.
        // Sharing the bounded pipe prevents stderr deadlock and silent false-zero data.
        var environment = ProcessInfo.processInfo.environment
        environment["LC_ALL"] = "C"; process.environment = environment
        let descriptor = pipe.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else { throw TrafficSamplingError.launch }
        defer {
            lock.lock(); child = nil; lock.unlock()
            try? pipe.fileHandleForReading.close(); try? pipe.fileHandleForWriting.close()
        }
        lock.lock()
        if cancelled { lock.unlock(); throw CancellationError() }
        do { try process.run() } catch { lock.unlock(); throw TrafficSamplingError.launch }
        child = process
        lock.unlock()
        try? pipe.fileHandleForWriting.close()
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var output = Data(), buffer = [UInt8](repeating: 0, count: 16384)
        var failure: Error?, terminationAt: TimeInterval?
        var eof = false
        while true {
            // Bounded drain per iteration so continuous output cannot starve timeout/cancellation.
            for _ in 0..<16 {
                let length = Darwin.read(descriptor, &buffer, buffer.count)
                if length > 0 {
                    if length <= outputLimit - output.count, failure == nil { output.append(contentsOf: buffer.prefix(length)) }
                    else if failure == nil { failure = TrafficSamplingError.outputLimit }
                } else {
                    if length == 0 { eof = true }
                    else if errno != EAGAIN && errno != EINTR { failure = TrafficSamplingError.command }
                    break
                }
            }
            let now = ProcessInfo.processInfo.systemUptime
            if isCancelled { failure = CancellationError() }
            if failure == nil, now >= deadline { failure = TrafficSamplingError.timeout }
            if failure != nil {
                if terminationAt == nil {
                    terminationAt = now
                    if process.isRunning { process.terminate() }
                }
                if let terminationAt, now - terminationAt >= 0.15, process.isRunning {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                }
                // Never waitUntilExit/readDataToEndOfFile: neither has a deadline.
                if !process.isRunning || now - (terminationAt ?? now) >= 0.5 { break }
            } else if !process.isRunning && eof { break }
            Thread.sleep(forTimeInterval: 0.02)
        }
        if let failure { throw failure }
        guard allowedExitCodes.contains(process.terminationStatus) else { throw TrafficSamplingError.command }
        guard let text = String(data: output, encoding: .utf8) else { throw TrafficSamplingError.command }
        return text
    }
}
