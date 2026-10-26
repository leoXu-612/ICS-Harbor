import HarborCore

extension AppModel {
    var applicationGuidance: ApplicationGuidance {
        let pending = Set(launchProgress.values.filter(\.isPending).map(\.containerID))
        return ApplicationGuidance.next(containers: state.containers, initialized: runtime.mapValues(\.applicationReady), busy: busy.union(pending), isWorking: isWorking)
    }
    func presentCreate(_ purpose: ContainerPurpose = .applications) { creationPurpose = purpose; showCreate = true }
    func guideApplicationSetup() {
        switch applicationGuidance {
        case .createEnvironment: presentCreate(.applications)
        case .prepare(let id): if let target = container(id) { provision(target, installSteam: false) }
        case .install(let id): preferredInstallContainerID = id; showInstallApplication = true
        case .checkEnvironment: section = .containers
        case .wait: section = isWorking || pendingLaunchCount > 0 ? .activity : .containers
        }
    }
    func hasLibraryConflict(_ container: ContainerRecord) -> Bool {
        libraries.contains { $0.containerID == container.id && conflictingLibraries.contains($0.id) }
    }
}
