import Foundation
import AppKit
import CoreGraphics
import Darwin
import HarborCore

struct LaunchProbeTarget: Sendable {
    var container: ContainerRecord
    var game: GameRecord?
    var since: Date
    var focusOnWindow = false
    var executable: String?
    var completionPath: String?
}

enum LaunchProbe {
    static func owns(_ pid: Int32, container: ContainerRecord) -> Bool {
        let root = URL(fileURLWithPath: container.wrapperPath + "/Contents/SharedSupport/wine").resolvingSymlinksInPath().path + "/"
        return executablePath(pid)?.hasPrefix(root) == true
    }
    static func sample(_ targets: [UUID: LaunchProbeTarget]) -> [UUID: LaunchEvidence] {
        let entries = ProcessProbe.entries()
        let windows = visibleWindowPIDs()
        var paths: [Int32: String] = [:]
        for entry in entries where entry.command.lowercased().contains(".exe") {
            if let path = executablePath(entry.pid) { paths[entry.pid] = path }
        }
        var results: [UUID: LaunchEvidence] = [:]
        for (id, target) in targets {
            let container = target.container
            let engine = URL(fileURLWithPath: container.wrapperPath + "/Contents/SharedSupport/wine").resolvingSymlinksInPath().path + "/"
            let scoped = entries.filter { entry in paths[entry.pid]?.hasPrefix(engine) == true }
            let steam = scoped.first { $0.command.replacingOccurrences(of: "/", with: "\\").lowercased() == "c:\\program files (x86)\\steam\\steam.exe" }
            let steamFamily = scoped.filter {
                let command = $0.command.lowercased()
                return command.contains("\\steam\\") && (command.hasSuffix("\\steam.exe") || command.hasSuffix("\\steamwebhelper.exe"))
            }
            var evidence = LaunchEvidence()
            evidence.runtimeRunning = ProcessProbe.isBusy(container, entries: entries)
            evidence.steamPID = steam?.pid
            // The updater and service-error dialogs belong to steam.exe too.
            // Count the modern Steam client window, not those bootstrap windows.
            evidence.steamWindowPID = steamFamily.first { $0.command.lowercased().hasSuffix("\\steamwebhelper.exe") && windows.contains($0.pid) }?.pid
            evidence.visibleWindowPIDs = windows
            if let executable = target.executable {
                let normalized = executable.replacingOccurrences(of: "/", with: "\\").lowercased()
                let candidates = scoped.filter { $0.command.replacingOccurrences(of: "/", with: "\\").lowercased() == normalized }
                evidence.gamePID = (candidates.first { windows.contains($0.pid) } ?? candidates.first)?.pid
            }
            if let path = target.completionPath, let bytes = try? Data(contentsOf: URL(fileURLWithPath: path)), bytes.count < 32 {
                evidence.exitCode = Int(String(decoding: bytes, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
            }
            if let root = target.game?.windowsGamePath?.lowercased() {
                let candidates = scoped.filter {
                    let command = $0.command.replacingOccurrences(of: "/", with: "\\").lowercased()
                    return command.hasPrefix(root + "\\") && !command.contains("crashpad_handler") && !command.contains("crashreporter")
                }
                evidence.gamePID = (candidates.first { windows.contains($0.pid) } ?? candidates.first)?.pid
            }
            if let steam {
                let start = processStartedAt(steam.pid) ?? NSRunningApplication(processIdentifier: steam.pid)?.launchDate ?? target.since
                evidence.connection = SteamSignals.connection(in: tail(container.steamRoot + "/logs/connection_log.txt"), since: start.addingTimeInterval(-2))
            }
            if let game = target.game {
                evidence.diskError = SteamSignals.hasDiskFailure(in: tail(container.steamRoot + "/logs/content_log.txt"), appID: game.appID, since: target.since)
                if let library = SteamScanner.resolve(windowsPath: game.libraryWindowsPath, prefix: container.prefix) {
                    let manifest = URL(fileURLWithPath: library + "/steamapps/appmanifest_\(game.appID).acf")
                    if let text = try? String(contentsOf: manifest, encoding: .utf8), let attributes = try? manifest.resourceValues(forKeys: [.contentModificationDateKey]) {
                        evidence.transfer = SteamSignals.transfer(in: text, recordedAt: attributes.contentModificationDate ?? target.since)
                    }
                }
            }
            results[id] = evidence
        }
        return results
    }

    private static func processStartedAt(_ pid: Int32) -> Date? {
        // Wine apps need not be registered with AppKit. Use kernel process time
        // so opening Harbor later still finds this Steam session's login event.
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.stride)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec))
    }
    private static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath().path
    }
    private static func visibleWindowPIDs() -> Set<Int32> {
        // Metadata only: no screenshots, window titles, Accessibility or screen-recording prompt.
        let rows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(rows.compactMap { row in
            guard (row[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = row[kCGWindowBounds as String] as? [String: Any],
                  (bounds["Width"] as? Double ?? 0) > 120, (bounds["Height"] as? Double ?? 0) > 100,
                  let pid = row[kCGWindowOwnerPID as String] as? Int32 else { return nil }
            return pid
        })
    }
    private static func tail(_ path: String) -> String {
        guard let handle = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? handle.close() }
        do {
            let size = try handle.seekToEnd()
            try handle.seek(toOffset: size > 128 * 1024 ? size - 128 * 1024 : 0)
            let data = try handle.read(upToCount: 128 * 1024) ?? Data()
            return String(decoding: data, as: UTF8.self)
        } catch { return "" }
    }
}
