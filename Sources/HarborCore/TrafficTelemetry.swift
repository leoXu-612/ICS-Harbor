import Foundation

/// Byte totals cover this continuous observation, never the process's lifetime.
public struct TrafficFlow: Identifiable, Sendable {
    public var id: String
    public var pid: Int32
    public var processName: String
    public var containerID: UUID
    public var applicationID: UUID?
    public var localEndpoint: String
    public var remoteEndpoint: String
    public var transport: String
    public var downloadBps: Double
    public var uploadBps: Double
    public var receivedBytes: UInt64
    public var sentBytes: UInt64
    /// False means unknown, even though the numeric placeholders are finite zero.
    public var hasRateBaseline: Bool

    public init(id: String, pid: Int32, processName: String, containerID: UUID, applicationID: UUID?, localEndpoint: String, remoteEndpoint: String, transport: String, downloadBps: Double, uploadBps: Double, receivedBytes: UInt64, sentBytes: UInt64, hasRateBaseline: Bool = true) {
        self.id = id; self.pid = pid; self.processName = processName
        self.containerID = containerID; self.applicationID = applicationID
        self.localEndpoint = localEndpoint; self.remoteEndpoint = remoteEndpoint; self.transport = transport
        self.downloadBps = downloadBps; self.uploadBps = uploadBps
        self.receivedBytes = receivedBytes; self.sentBytes = sentBytes; self.hasRateBaseline = hasRateBaseline
    }
}

public struct TrafficProcess: Identifiable, Sendable {
    public var id: Int32
    public var name: String
    public var containerID: UUID
    public var applicationID: UUID?
    public var cpuPercent: Double
    public var rssBytes: UInt64
    public init(id: Int32, name: String, containerID: UUID, applicationID: UUID?, cpuPercent: Double, rssBytes: UInt64) {
        self.id = id; self.name = name; self.containerID = containerID; self.applicationID = applicationID
        self.cpuPercent = cpuPercent; self.rssBytes = rssBytes
    }
}

public struct TrafficIdentity: Hashable, Sendable {
    public var pid: Int32
    /// Kernel start seconds + microseconds, not PID or executable name alone.
    public var startKey: String
    public var processName: String
    public var containerID: UUID
    public var applicationID: UUID?
    public init(pid: Int32, startKey: String, processName: String, containerID: UUID, applicationID: UUID?) {
        self.pid = pid; self.startKey = startKey; self.processName = processName
        self.containerID = containerID; self.applicationID = applicationID
    }
}

public struct NettopConnection: Sendable {
    public var pid: Int32
    public var localEndpoint: String
    public var remoteEndpoint: String
    public var transport: String
    public var receivedBytes: UInt64
    public var sentBytes: UInt64
    public init(pid: Int32, localEndpoint: String, remoteEndpoint: String, transport: String, receivedBytes: UInt64, sentBytes: UInt64) {
        self.pid = pid; self.localEndpoint = localEndpoint; self.remoteEndpoint = remoteEndpoint
        self.transport = transport; self.receivedBytes = receivedBytes; self.sentBytes = sentBytes
    }
}

public struct NettopSnapshot: Sendable {
    public var connections: [NettopConnection]
    public init(connections: [NettopConnection]) { self.connections = connections }
}

public enum TrafficTelemetryError: Error { case invalidCSV, invalidSnapshot, invalidProcessSample }

public enum NettopParser {
    /// Each repeated header begins a new snapshot. Process aggregates are context
    /// only; adding them to socket rows would count traffic twice.
    public static func parse(_ text: String) throws -> [NettopSnapshot] {
        var snapshots: [NettopSnapshot] = []
        var connections: [NettopConnection] = []
        var columns: (input: Int, output: Int)?
        var pid: Int32?
        for fields in try csv(text) {
            if fields.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) { continue }
            guard let first = fields.first else { continue }
            let label = first.trimmingCharacters(in: .whitespaces)
            if label.isEmpty, let input = fields.firstIndex(of: "bytes_in"), let output = fields.firstIndex(of: "bytes_out") {
                if columns != nil { snapshots.append(NettopSnapshot(connections: connections)) }
                columns = (input, output); connections = []; pid = nil
                continue
            }
            guard let columns else { throw TrafficTelemetryError.invalidSnapshot }
            let parts = label.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            if let transport = parts.first, ["tcp4", "tcp6", "udp4", "udp6"].contains(String(transport)) {
                guard let pid, parts.count == 2,
                      let delimiter = parts[1].range(of: "<->"),
                      fields.count > max(columns.input, columns.output),
                      let received = counter(fields[columns.input]), let sent = counter(fields[columns.output]) else {
                    throw TrafficTelemetryError.invalidSnapshot
                }
                let local = String(parts[1][..<delimiter.lowerBound]).trimmingCharacters(in: .whitespaces)
                let remote = String(parts[1][delimiter.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard !local.isEmpty, !remote.isEmpty else { throw TrafficTelemetryError.invalidSnapshot }
                connections.append(NettopConnection(pid: pid, localEndpoint: local, remoteEndpoint: remote, transport: String(transport), receivedBytes: received, sentBytes: sent))
            } else {
                guard let dot = label.lastIndex(of: "."), let parsed = Int32(label[label.index(after: dot)...]), parsed > 0 else {
                    throw TrafficTelemetryError.invalidSnapshot
                }
                pid = parsed
            }
        }
        guard columns != nil else { throw TrafficTelemetryError.invalidSnapshot }
        snapshots.append(NettopSnapshot(connections: connections))
        return snapshots
    }

    private static func counter(_ text: String) -> UInt64? {
        guard !text.isEmpty, text.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
        return UInt64(text)
    }

    /// RFC-style quoted fields, escaped quotes, CRLF and trailing empty columns.
    private static func csv(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closedQuote = false
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            let next = text.index(after: index)
            if quoted {
                if char == "\"" {
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\""); index = text.index(after: next); continue
                    }
                    quoted = false; closedQuote = true
                } else { field.append(char) }
            } else if char == "," {
                row.append(field); field = ""; closedQuote = false
            } else if char == "\n" || char == "\r\n" || char == "\r" {
                row.append(field); rows.append(row); row = []; field = ""; closedQuote = false
            } else if char == "\"", field.isEmpty, !closedQuote {
                quoted = true
            } else {
                guard !closedQuote, char != "\"" else { throw TrafficTelemetryError.invalidCSV }
                field.append(char)
            }
            index = next
        }
        guard !quoted else { throw TrafficTelemetryError.invalidCSV }
        if !row.isEmpty || !field.isEmpty || closedQuote { row.append(field); rows.append(row) }
        return rows
    }
}

/// Optional rates keep absence of evidence distinct from an observed zero delta.
public struct TrafficMeasurement: Sendable {
    public var id: String
    public var identity: TrafficIdentity
    public var localEndpoint: String
    public var remoteEndpoint: String
    public var transport: String
    public var downloadBps: Double?
    public var uploadBps: Double?
    public var receivedBytes: UInt64
    public var sentBytes: UInt64

    public var flow: TrafficFlow {
        TrafficFlow(id: id, pid: identity.pid, processName: identity.processName, containerID: identity.containerID,
                    applicationID: identity.applicationID, localEndpoint: localEndpoint, remoteEndpoint: remoteEndpoint,
                    transport: transport, downloadBps: downloadBps ?? 0, uploadBps: uploadBps ?? 0,
                    receivedBytes: receivedBytes, sentBytes: sentBytes,
                    hasRateBaseline: downloadBps != nil && uploadBps != nil)
    }
}

public struct TrafficRateReducer: Sendable {
    private struct Key: Hashable, Sendable {
        var identity: TrafficIdentity
        var local: String
        var remote: String
        var transport: String
        var id: String {
            // Length prefixes avoid delimiter collisions in endpoint/process names.
            [String(identity.pid), identity.startKey, identity.containerID.uuidString,
             identity.applicationID?.uuidString ?? "shared", identity.processName, transport, local, remote]
                .map { "\($0.utf8.count):\($0)" }.joined()
        }
    }
    private struct Counter: Sendable {
        var received: UInt64
        var sent: UInt64
        var socketCount: Int
        var overflow = false
    }
    private struct State: Sendable {
        var counter: Counter
        var time: TimeInterval?
        var received: UInt64 = 0
        var sent: UInt64 = 0
    }
    private var previous: [Key: State] = [:]
    public init() {}

    /// Keep observed totals, but never infer traffic during an unavailable interval.
    public mutating func invalidate() {
        for key in Array(previous.keys) { previous[key]?.time = nil }
    }

    /// `time` is monotonic uptime, not wall-clock time. State is bounded to the
    /// current socket set; disappearance starts a new observation if it returns.
    public mutating func reduce(_ snapshot: NettopSnapshot, identities: [Int32: TrafficIdentity], at time: TimeInterval) -> [TrafficMeasurement] {
        var counters: [Key: Counter] = [:]
        for row in snapshot.connections {
            guard let identity = identities[row.pid], identity.pid == row.pid else { continue }
            let key = Key(identity: identity, local: row.localEndpoint, remote: row.remoteEndpoint, transport: row.transport)
            var value = counters[key] ?? Counter(received: 0, sent: 0, socketCount: 0)
            let received = value.received.addingReportingOverflow(row.receivedBytes)
            let sent = value.sent.addingReportingOverflow(row.sentBytes)
            value.received = received.partialValue; value.sent = sent.partialValue; value.socketCount += 1
            value.overflow = value.overflow || received.overflow || sent.overflow
            counters[key] = value
        }
        var next: [Key: State] = [:]
        var result: [TrafficMeasurement] = []
        for (key, counter) in counters {
            let old = previous[key]
            var state = State(counter: counter, time: time.isFinite && !counter.overflow ? time : nil,
                              received: old?.received ?? 0, sent: old?.sent ?? 0)
            var download: Double?, upload: Double?
            if let old, let then = old.time {
                let elapsed = time - then
                if elapsed.isFinite, elapsed > 0, elapsed <= 8, !counter.overflow,
                   !old.counter.overflow, counter.socketCount == old.counter.socketCount {
                    if counter.received >= old.counter.received {
                        let delta = counter.received - old.counter.received
                        let rate = Double(delta) / elapsed
                        if rate.isFinite { download = rate; state.received = Self.add(state.received, delta) }
                    }
                    if counter.sent >= old.counter.sent {
                        let delta = counter.sent - old.counter.sent
                        let rate = Double(delta) / elapsed
                        if rate.isFinite { upload = rate; state.sent = Self.add(state.sent, delta) }
                    }
                }
            }
            next[key] = state
            result.append(TrafficMeasurement(id: key.id, identity: key.identity, localEndpoint: key.local,
                                            remoteEndpoint: key.remote, transport: key.transport,
                                            downloadBps: download, uploadBps: upload,
                                            receivedBytes: state.received, sentBytes: state.sent))
        }
        previous = next
        return result.sorted { $0.id < $1.id }
    }
    private static func add(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let sum = lhs.addingReportingOverflow(rhs)
        return sum.overflow ? UInt64.max : sum.partialValue
    }
}

public enum TrafficAttribution {
    /// Inputs must be canonical native paths (resolved by the caller).
    public static func containerID(executablePath: String, engineRoots: [UUID: String]) -> UUID? {
        let matches = engineRoots.filter { _, root in
            root.hasPrefix("/") && root != "/" && executablePath.hasPrefix(root + (root.hasSuffix("/") ? "" : "/"))
        }
        return matches.count == 1 ? matches.first?.key : nil
    }
    /// No basename, substring, parent-PID or sibling-directory inference.
    public static func applicationID(command: String, paths: [UUID: String]) -> UUID? {
        func normalize(_ value: String) -> String { value.replacingOccurrences(of: "/", with: "\\").lowercased() }
        let matches = paths.filter { normalize($0.value) == normalize(command) }
        return matches.count == 1 ? matches.first?.key : nil
    }
}

public struct TrafficProcessSample: Sendable {
    public var pid: Int32
    public var command: String
    public var cpuPercent: Double
    public var rssBytes: UInt64
    public init(pid: Int32, command: String, cpuPercent: Double, rssBytes: UInt64) {
        self.pid = pid; self.command = command; self.cpuPercent = cpuPercent; self.rssBytes = rssBytes
    }
    public static func parsePS(_ text: String) throws -> [TrafficProcessSample] {
        try text.split(whereSeparator: { $0.isNewline }).map { line in
            let parts = line.split(maxSplits: 3, whereSeparator: { $0.isWhitespace })
            guard parts.count == 4, let pid = Int32(parts[0]), pid > 0,
                  let cpu = Double(parts[1]), cpu.isFinite, cpu >= 0,
                  let rss = UInt64(parts[2]), rss <= UInt64.max / 1024 else { throw TrafficTelemetryError.invalidProcessSample }
            return TrafficProcessSample(pid: pid, command: String(parts[3]), cpuPercent: cpu, rssBytes: rss * 1024)
        }
    }
}
