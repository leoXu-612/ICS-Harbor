import Foundation

public struct LibrarySnapshot: Sendable {
    public var games: [GameRecord] = []
    public var libraries: [LibraryRecord] = []
    public var warnings: [String] = []
    public init() {}
}
public enum SteamScanner {
    private static let utilities: Set<String> = ["228980", "1070560", "1391110", "1628350"]
    /// Names only for familiar IDs when a disconnected library has no readable manifests.
    private static let knownNames = ["730":"Counter-Strike 2", "312520":"Rain World", "524220":"NieR:Automata", "601150":"Devil May Cry 5", "1113560":"NieR Replicant ver.1.22474487139…", "1222140":"Detroit: Become Human", "1237970":"Titanfall 2", "1238810":"Battlefield V", "1238840":"Battlefield 1", "550":"Left 4 Dead 2"]

    public static func resolve(windowsPath: String, prefix: String) -> String? {
        let path = windowsPath.replacingOccurrences(of: "/", with: "\\")
        guard path.count >= 3, path[path.index(after: path.startIndex)] == ":", let letter = path.first,
              letter.isASCII && letter.isLetter else { return nil }
        let tail = String(path.dropFirst(2)).split(separator: "\\").map(String.init)
        guard !tail.contains("..") else { return nil }
        let driveLink = URL(fileURLWithPath: prefix + "/dosdevices/" + String(letter).lowercased() + ":")
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: driveLink.path) else { return nil }
        let root = target.hasPrefix("/") ? URL(fileURLWithPath: target) : driveLink.deletingLastPathComponent().appendingPathComponent(target)
        return tail.reduce(root.standardizedFileURL) { $0.appendingPathComponent($1) }.standardizedFileURL.path
    }

    public static func scan(_ container: ContainerRecord) -> LibrarySnapshot {
        var result = LibrarySnapshot()
        let fm = FileManager.default
        let vdf = container.steamRoot + "/steamapps/libraryfolders.vdf"
        guard let text = try? String(contentsOfFile: vdf, encoding: .utf8) else {
            result.warnings.append("\(container.name)：尚未发现 Steam 游戏库配置。")
            return result
        }
        guard let parsed = try? VDFParser.parse(text), let folders = parsed["libraryfolders"]?.object else {
            result.warnings.append("\(container.name)：Steam 库配置暂时不可解析；未修改原文件。")
            return result
        }
        for key in folders.keys.sorted() {
            guard let folder = folders[key], let windowsPath = folder["path"]?.string else { continue }
            let localPath = resolve(windowsPath: windowsPath, prefix: container.prefix)
            let online = localPath.map { fm.fileExists(atPath: $0 + "/steamapps") } ?? false
            let letter = String(windowsPath.prefix(1)).uppercased()
            let mapped = try? fm.destinationOfSymbolicLink(atPath: container.prefix + "/dosdevices/" + letter.lowercased() + ":")
            let cachedApps = folder["apps"]?.object ?? [:]
            let libID = container.id.uuidString + ":" + key
            result.libraries.append(LibraryRecord(id: libID, containerID: container.id, windowsPath: windowsPath, unixPath: localPath, drive: letter, mappedTarget: mapped, isOnline: online, registeredCount: cachedApps.keys.filter { !utilities.contains($0) }.count))
            if !online {
                for appID in cachedApps.keys.sorted() where isAppID(appID) && !utilities.contains(appID) {
                    result.games.append(GameRecord(containerID: container.id, appID: appID, name: knownNames[appID] ?? "Steam 游戏 #\(appID)", libraryID: libID, libraryWindowsPath: windowsPath, installDirectory: nil, sizeOnDisk: Int64(cachedApps[appID]?.string ?? "") ?? 0, buildID: nil, availability: .offline, coverPath: artwork(appID, in: container, hero: false), heroPath: artwork(appID, in: container, hero: true)))
                }
                continue
            }
            guard let localPath, let entries = try? fm.contentsOfDirectory(atPath: localPath + "/steamapps") else { continue }
            for file in entries where file.hasPrefix("appmanifest_") && file.hasSuffix(".acf") {
                guard let data = try? String(contentsOfFile: localPath + "/steamapps/" + file, encoding: .utf8),
                      let root = try? VDFParser.parse(data), let state = root["AppState"],
                      let appID = state["appid"]?.string, isAppID(appID), !utilities.contains(appID),
                      let name = state["name"]?.string, let dir = state["installdir"]?.string,
                      !dir.isEmpty, !dir.contains("/"), !dir.contains("\\"), dir != ".", dir != ".." else { continue }
                let installPath = localPath + "/steamapps/common/" + dir
                let flags = Int(state["StateFlags"]?.string ?? "") ?? 0
                let availability: GameAvailability = !fm.fileExists(atPath: installPath) ? .missing : flags & 4 == 0 ? .incomplete : .ready
                result.games.append(GameRecord(containerID: container.id, appID: appID, name: name, libraryID: libID, libraryWindowsPath: windowsPath, installDirectory: installPath, sizeOnDisk: Int64(state["SizeOnDisk"]?.string ?? "") ?? 0, buildID: state["buildid"]?.string, availability: availability, coverPath: artwork(appID, in: container, hero: false), heroPath: artwork(appID, in: container, hero: true)))
            }
        }
        result.games.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return result
    }

    public static func isAppID(_ string: String) -> Bool { !string.isEmpty && string.count <= 12 && string.allSatisfy { $0.isASCII && $0.isNumber } }
    public static func nativeLibraryConflicts(_ libraries: [LibraryRecord], nativeVDF: String) -> Set<String> {
        guard let parsed = try? VDFParser.parse(nativeVDF), let folders = parsed["libraryfolders"]?.object else { return [] }
        let nativePaths = Set(folders.values.compactMap { $0["path"]?.string }.filter { $0.hasPrefix("/") }.map {
            URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path
        })
        return Set(libraries.compactMap { library in
            guard let path = library.unixPath, nativePaths.contains(URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path) else { return nil }
            return library.id
        })
    }
    private static func artwork(_ appID: String, in container: ContainerRecord, hero: Bool) -> String? {
        let root = container.steamRoot + "/appcache/librarycache/"
        let names = hero ? ["library_hero.jpg", "header.jpg", "library_header.jpg"] : ["library_600x900.jpg", "header.jpg", "library_header.jpg"]
        for name in names {
            for path in [root + appID + "/" + name, root + appID + "_" + name] where FileManager.default.fileExists(atPath: path) { return path }
        }
        return nil
    }
}
