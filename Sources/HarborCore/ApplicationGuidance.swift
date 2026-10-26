import Foundation

public enum ApplicationGuidance: Equatable, Sendable {
    case createEnvironment, prepare(UUID), install(UUID), checkEnvironment, wait

    public static func next(containers: [ContainerRecord], initialized: [UUID: Bool], busy: Set<UUID>, isWorking: Bool) -> ApplicationGuidance {
        if isWorking { return .wait }
        let managed = containers.filter { $0.origin == .managed }
        guard !managed.isEmpty else { return .createEnvironment }
        let idle = managed.filter { !busy.contains($0.id) }
        if let ready = idle.first(where: { initialized[$0.id] == true }) { return .install(ready.id) }
        if let unprepared = idle.first(where: { initialized[$0.id] == false }) { return .prepare(unprepared.id) }
        return idle.isEmpty ? .wait : .checkEnvironment
    }
}
