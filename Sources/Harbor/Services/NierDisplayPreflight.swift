import Foundation
import AppKit
import CoreGraphics
import HarborCore
import os

@MainActor enum NierDisplayPreflight {
    private static let repairs = DispatchQueue(label: "local.harbor.nier-display-repair", qos: .userInitiated)
    static func run(container: ContainerRecord, requests: URL, backupRoot: URL, cancelled: @escaping @MainActor @Sendable () -> Bool) async throws -> NierDisplayRepair {
        guard let bundleURL = Bundle.main.resourceURL?.appendingPathComponent("Harbor_Harbor.bundle"),
              let bundle = Bundle(url: bundleURL),
              let source = bundle.url(forResource: "nier-display-probe", withExtension: "cs", subdirectory: "Resources") else {
            throw HarborError.unavailable("显示预检组件缺失，请重新安装完整 Harbor 应用。")
        }
        // Remember even a disconnect/reconnect that returns to the same final layout.
        let displayChanged = OSAllocatedUnfairLock(initialState: false)
        let observer = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: nil) { _ in
            displayChanged.withLock { $0 = true }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let initialDisplay = CGMainDisplayID()
        let initialScreens = Set(NSScreen.screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value })
        let request = try NierDisplayProbeRequest.prepare(container: container, root: requests, source: source)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: container.launcher)
        process.arguments = ["WSS-installer", request.launcher.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(90)
        while !FileManager.default.fileExists(atPath: request.completion.path) {
            guard !cancelled() else { throw CancellationError() }
            if !process.isRunning && process.terminationStatus != 0 {
                throw HarborError.unavailable("显示预检无法启动，未修改游戏配置。诊断：\(request.directory.path)")
            }
            guard Date() < deadline else {
                throw HarborError.unavailable("显示预检超时，未修改游戏配置。诊断：\(request.directory.path)")
            }
            try await Task.sleep(for: .milliseconds(200))
        }
        guard !cancelled() else { throw CancellationError() }
        let currentScreens = Set(NSScreen.screens.compactMap { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value })
        guard !displayChanged.withLock({ $0 }), CGMainDisplayID() == initialDisplay, currentScreens == initialScreens else {
            throw HarborError.unavailable("检查期间显示器连接发生变化，请再次启动游戏。原配置未修改。")
        }
        let display = try request.result()
        // Documents may prompt for access or wait for a file provider. Never open
        // game files on AppKit's main thread. The checkpoint re-enters it briefly
        // to respect Stop tracking and display changes immediately before writes.
        let repair: NierDisplayRepair = try await withCheckedThrowingContinuation { continuation in
            // Several containers can share Documents; never interleave backup,
            // mutation or rollback for this game's files.
            repairs.async {
                do {
                    guard let documents = SteamScanner.resolve(windowsPath: display.documentsPath, prefix: container.prefix) else {
                        throw HarborError.unavailable("无法定位此环境的游戏配置目录，未修改显示设置。")
                    }
                    let result = try NierDisplayConfiguration.repair(
                        directory: URL(fileURLWithPath: documents).appendingPathComponent("My Games/NieR_Automata"),
                        target: display, backupRoot: backupRoot, isGameRunning: {
                            let running = try NierGameProcess.isRunning()
                            // Check after the blocking process scan, immediately
                            // before admitting a write. Already-started writes
                            // finish or roll back; Stop tracking cannot undo them.
                            try DispatchQueue.main.sync {
                                guard !cancelled() else { throw CancellationError() }
                                guard !displayChanged.withLock({ $0 }) else {
                                    throw HarborError.unavailable("检查期间显示器连接发生变化，请再次启动。原配置未修改。")
                                }
                            }
                            return running
                        })
                    continuation.resume(returning: result)
                } catch { continuation.resume(throwing: error) }
            }
        }
        guard !cancelled() else { throw CancellationError() }
        guard !displayChanged.withLock({ $0 }) else {
            throw HarborError.unavailable("预检期间显示器发生变化，请重新启动以再次检查。")
        }
        return repair
    }
}
