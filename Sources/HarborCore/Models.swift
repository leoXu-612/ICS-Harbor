import Foundation

public enum ContainerOrigin: String, Codable, Sendable { case linked, managed }
public enum ContainerPurpose: String, Codable, CaseIterable, Sendable { case applications, steam }
public struct ContainerRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var wrapperPath: String
    public var origin: ContainerOrigin
    public var createdAt: Date
    public var purpose: ContainerPurpose?
    public init(id: UUID = UUID(), name: String, wrapperPath: String, origin: ContainerOrigin = .linked, createdAt: Date = Date()) {
        self.id = id; self.name = name; self.wrapperPath = wrapperPath; self.origin = origin; self.createdAt = createdAt
    }
    public var prefix: String { wrapperPath + "/Contents/SharedSupport/prefix" }
    public var launcher: String { wrapperPath + "/Contents/MacOS/launcher" }
    public var steamRoot: String { prefix + "/drive_c/Program Files (x86)/Steam" }
    public var steamExecutable: String { steamRoot + "/Steam.exe" }
    public var displayOrigin: String { origin == .linked ? "只读接入" : "Harbor 托管" }
    public var preparesSteam: Bool { purpose != .applications }
}

public enum GameAvailability: String, Codable, Sendable {
    case ready, offline, incomplete, missing
    public var title: String {
        switch self { case .ready: return "已安装"; case .offline: return "磁盘离线"; case .incomplete: return "安装未完成"; case .missing: return "文件待确认" }
    }
}
public struct GameRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String { containerID.uuidString + ":" + appID }
    public var containerID: UUID
    public var appID: String
    public var name: String
    public var libraryID: String
    public var libraryWindowsPath: String
    public var installDirectory: String?
    public var sizeOnDisk: Int64
    public var buildID: String?
    public var availability: GameAvailability
    public var coverPath: String?
    public var heroPath: String?
    public var windowsGamePath: String? {
        guard let installDirectory else { return nil }
        return libraryWindowsPath + "\\steamapps\\common\\" + URL(fileURLWithPath: installDirectory).lastPathComponent
    }
}

public struct LibraryRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var containerID: UUID
    public var windowsPath: String
    public var unixPath: String?
    public var drive: String
    public var mappedTarget: String?
    public var isOnline: Bool
    public var registeredCount: Int
}

public struct DriveBinding: Identifiable, Codable, Hashable, Sendable {
    public var id: String { containerID.uuidString + ":" + letter }
    public var containerID: UUID
    public var letter: String
    public var volumeUUID: String
    public var volumeName: String
    public var relativeRoot: String
    public init(containerID: UUID, letter: String, volumeUUID: String, volumeName: String, relativeRoot: String = "") {
        self.containerID = containerID; self.letter = letter; self.volumeUUID = volumeUUID; self.volumeName = volumeName; self.relativeRoot = relativeRoot
    }
}
public struct MountedVolume: Identifiable, Hashable, Sendable {
    public var id: String { uuid ?? path }
    public var name: String
    public var path: String
    public var uuid: String?
    public var availableBytes: Int64?
    public init(name: String, path: String, uuid: String?, availableBytes: Int64? = nil) { self.name = name; self.path = path; self.uuid = uuid; self.availableBytes = availableBytes }
}

public enum TaskState: String, Codable, Sendable { case running, succeeded, failed, requested }
public struct ActivityRecord: Identifiable, Codable, Sendable {
    public var id: UUID = UUID()
    public var title: String
    public var detail: String
    public var state: TaskState
    public var createdAt: Date = Date()
    public var log: String = ""
    public var launch: LaunchProgress?
    public init(title: String, detail: String = "", state: TaskState = .running) { self.title = title; self.detail = detail; self.state = state }
}
public struct AppState: Codable, Sendable {
    public var schema: Int = 1
    public var containers: [ContainerRecord] = []
    public var presets: [String: GamePreset] = [:]
    public var previousPresets: [String: GamePreset] = [:]
    public var favorites: Set<String> = []
    public var bindings: [DriveBinding] = []
    public var activity: [ActivityRecord] = []
    // Optional so states written before standalone applications remain readable.
    public var applications: [WindowsApplication]?
    public init() {}
}

public enum HarborError: LocalizedError {
    case invalid(String), unavailable(String), protected(String)
    public var errorDescription: String? { switch self { case .invalid(let s), .unavailable(let s), .protected(let s): return s } }
}
