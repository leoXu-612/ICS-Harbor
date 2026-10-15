import Foundation

public enum ContainerDiscovery {
    public static func discover(home: String = NSHomeDirectory()) -> [ContainerRecord] {
        let fm = FileManager.default
        let roots = [home + "/Applications/Sikarugir", home + "/Applications"]
        var found = Set<String>()
        return roots.flatMap { root -> [ContainerRecord] in
            (try? fm.contentsOfDirectory(atPath: root))?.compactMap { entry in
                let path = root + "/" + entry
                guard entry.hasSuffix(".app"), found.insert(path).inserted,
                      fm.fileExists(atPath: path + "/Contents/SharedSupport/prefix/drive_c/Program Files (x86)/Steam/Steam.exe"),
                      fm.isExecutableFile(atPath: path + "/Contents/MacOS/launcher") else { return nil }
                return ContainerRecord(name: String(entry.dropLast(4)), wrapperPath: path)
            } ?? []
        }
    }
    public static func validateWrapper(_ url: URL) throws -> ContainerRecord {
        let path = url.standardizedFileURL.path
        guard url.pathExtension == "app", FileManager.default.isExecutableFile(atPath: path + "/Contents/MacOS/launcher"),
              FileManager.default.fileExists(atPath: path + "/Contents/SharedSupport/wine/bin/wine") else {
            throw HarborError.invalid("请选择 Sikarugir Wine 容器 .app，而不是 Mac 原生 Steam。")
        }
        return ContainerRecord(name: url.deletingPathExtension().lastPathComponent, wrapperPath: path)
    }
}

public struct RuntimeInfo: Sendable {
    public var engine: String
    public var renderer: String
    public var hasSteam: Bool
    public var initialized: Bool
    public static func read(_ container: ContainerRecord) -> RuntimeInfo {
        let fm = FileManager.default
        let dict = (try? Data(contentsOf: URL(fileURLWithPath: container.wrapperPath + "/Contents/Info.plist")))
            .flatMap { try? PropertyListSerialization.propertyList(from: $0, format: nil) as? [String: Any] } ?? [:]
        let renderer = (dict["D3DMETAL"] as? NSNumber)?.boolValue == true ? "D3DMetal" : (dict["DXVK"] as? NSNumber)?.boolValue == true ? "DXVK" : "DXMT"
        let version = (try? String(contentsOfFile: container.wrapperPath + "/Contents/SharedSupport/wine/version", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
        return RuntimeInfo(engine: version ?? "引擎尚未准备", renderer: dict.isEmpty ? "尚未配置" : renderer, hasSteam: fm.fileExists(atPath: container.steamExecutable), initialized: fm.fileExists(atPath: container.prefix + "/system.reg"))
    }
}

public struct ProcessEntry: Sendable { public var pid: Int32; public var command: String }
public enum ProcessProbe {
    public static func entries() -> [ProcessEntry] {
        let process = Process(); let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axo", "pid=,comm="]
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let bytes = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        return String(decoding: bytes, as: UTF8.self).split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let pid = Int32(parts[0]) else { return nil }
            return ProcessEntry(pid: pid, command: String(parts[1]).trimmingCharacters(in: .whitespaces))
        }
    }
    public static func isBusy(_ container: ContainerRecord, entries: [ProcessEntry]) -> Bool {
        let original = container.wrapperPath + "/Contents/"
        let real = URL(fileURLWithPath: container.wrapperPath).resolvingSymlinksInPath().path + "/Contents/"
        return entries.contains {
            guard $0.command.hasPrefix("/"), $0.command.contains("/SharedSupport/wine/") else { return false }
            let normalized = URL(fileURLWithPath: $0.command).resolvingSymlinksInPath().standardizedFileURL.path
            return $0.command.hasPrefix(original) || $0.command.hasPrefix(real) || normalized.hasPrefix(real)
        }
    }
}

public enum VolumeScanner {
    public static func mounted() -> [MountedVolume] {
        let keys: Set<URLResourceKey> = [.volumeNameKey, .volumeUUIDStringKey, .volumeAvailableCapacityKey]
        return (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"), includingPropertiesForKeys: Array(keys)))?.compactMap { url in
            guard let info = try? url.resourceValues(forKeys: keys), url.path != "/Volumes/Recovery" else { return nil }
            return MountedVolume(name: info.volumeName ?? url.lastPathComponent, path: url.path, uuid: info.volumeUUIDString, availableBytes: info.volumeAvailableCapacity.map(Int64.init))
        }.sorted { $0.name < $1.name } ?? []
    }
}

public enum DriveMapper {
    public static func createMissingLink(container: ContainerRecord, letter: String, target: URL, allowLinkedRepair: Bool = false) throws {
        guard container.origin == .managed || allowLinkedRepair else { throw HarborError.protected("关联容器需要单独确认盘符修复。") }
        guard letter.count == 1, let char = letter.first, char.isASCII, char.isLetter, !["c", "z"].contains(letter.lowercased()) else {
            throw HarborError.invalid("盘符必须为 C、Z 以外的单个英文字母。")
        }
        let resolved = target.standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path != "/", FileManager.default.fileExists(atPath: resolved.path) else { throw HarborError.unavailable("目标磁盘尚未挂载。") }
        let link = container.prefix + "/dosdevices/" + letter.lowercased() + ":"
        let fm = FileManager.default
        if let old = try? fm.destinationOfSymbolicLink(atPath: link) {
            let actual = old.hasPrefix("/") ? URL(fileURLWithPath: old) : URL(fileURLWithPath: link).deletingLastPathComponent().appendingPathComponent(old)
            if actual.standardizedFileURL.resolvingSymlinksInPath() == resolved { return }
            throw HarborError.protected("\(letter.uppercased()): 已指向 \(old)。为保护原配置，不自动替换。")
        }
        guard !fm.fileExists(atPath: link) else { throw HarborError.protected("盘符位置已有文件，未覆盖。") }
        guard fm.fileExists(atPath: container.prefix + "/dosdevices") else { throw HarborError.unavailable("容器尚未初始化。") }
        try fm.createSymbolicLink(atPath: link, withDestinationPath: resolved.path)
    }
    public static func target(for binding: DriveBinding, volumes: [MountedVolume]) -> URL? {
        guard !binding.volumeUUID.isEmpty, let volume = volumes.first(where: { $0.uuid == binding.volumeUUID }),
              !binding.relativeRoot.split(separator: "/").contains("..") else { return nil }
        return URL(fileURLWithPath: volume.path).appendingPathComponent(binding.relativeRoot).standardizedFileURL
    }
}
