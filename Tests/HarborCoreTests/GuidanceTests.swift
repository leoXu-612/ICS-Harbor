import XCTest
@testable import HarborCore

final class GuidanceTests: XCTestCase {
    func testLinkedOnlyLibraryRecommendsIndependentEnvironment() {
        let linked = ContainerRecord(name: "Existing", wrapperPath: "/existing.app")
        XCTAssertEqual(ApplicationGuidance.next(containers: [linked], initialized: [linked.id: true], busy: [], isWorking: false), .createEnvironment)
    }
    func testReadyIdleEnvironmentOutranksBusyAndUnpreparedEnvironments() {
        let waiting = ContainerRecord(name: "Busy", wrapperPath: "/busy.app", origin: .managed)
        let ready = ContainerRecord(name: "Ready", wrapperPath: "/ready.app", origin: .managed)
        let fresh = ContainerRecord(name: "Fresh", wrapperPath: "/fresh.app", origin: .managed)
        XCTAssertEqual(ApplicationGuidance.next(containers: [waiting, fresh, ready], initialized: [waiting.id: true, ready.id: true, fresh.id: false], busy: [waiting.id], isWorking: false), .install(ready.id))
    }
    func testUnpreparedManagedEnvironmentIsPreparedNotRecreated() {
        let fresh = ContainerRecord(name: "Fresh", wrapperPath: "/fresh.app", origin: .managed)
        XCTAssertEqual(ApplicationGuidance.next(containers: [fresh], initialized: [fresh.id: false], busy: [], isWorking: false), .prepare(fresh.id))
    }
    func testUnknownReadinessDoesNotClaimEnvironmentIsReady() {
        let unknown = ContainerRecord(name: "Unknown", wrapperPath: "/unknown.app", origin: .managed)
        XCTAssertEqual(ApplicationGuidance.next(containers: [unknown], initialized: [:], busy: [], isWorking: false), .checkEnvironment)
    }
    func testBusyEnvironmentDoesNotOfferInstallOrReinitialization() {
        let busy = ContainerRecord(name: "Busy", wrapperPath: "/busy.app", origin: .managed)
        XCTAssertEqual(ApplicationGuidance.next(containers: [busy], initialized: [busy.id: false], busy: [busy.id], isWorking: false), .wait)
    }
    func testOngoingComponentTaskTakesPriorityEvenWithoutContainers() {
        XCTAssertEqual(ApplicationGuidance.next(containers: [], initialized: [:], busy: [], isWorking: true), .wait)
    }
}
