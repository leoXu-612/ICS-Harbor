import XCTest
@testable import HarborCore

final class TrafficTelemetryTests: XCTestCase {
    private let containerID = UUID()
    private func owner(_ start: String = "100.1") -> TrafficIdentity {
        TrafficIdentity(pid: 46658, startKey: start, processName: "Origin64.exe", containerID: containerID, applicationID: nil)
    }
    private func snapshot(_ received: UInt64, _ sent: UInt64) throws -> NettopSnapshot {
        try NettopParser.parse(",bytes_in,bytes_out,\nwine.46658,999999,999999,\ntcp4 127.0.0.1:52343<->127.0.0.1:52339,\(received),\(sent),\n")[0]
    }
    func testActualCSVExcludesProcessTotalsAndSeparatesRepeatedHeaders() throws {
        let csv = ",bytes_in,bytes_out,\nwine.46658,65536,131072,\ntcp4 127.0.0.1:52343<->127.0.0.1:52339,65536,131072,\n"
        let samples = try NettopParser.parse(csv + csv)
        XCTAssertEqual(samples.count, 2)
        XCTAssertEqual(samples[0].connections.count, 1)
        XCTAssertEqual(samples[0].connections[0].receivedBytes, 65536)
        XCTAssertEqual(samples[0].connections[0].sentBytes, 131072)
        XCTAssertEqual(samples[0].connections[0].pid, 46658)
    }
    func testQuotedCSVReorderedColumnsIPv6AndProcessNameDots() throws {
        let samples = try NettopParser.parse("\"\",bytes_out,bytes_in,\r\n\"Wine, \"\"App\"\".exe.46658\",20,10,\r\n\"tcp6 [fe80::1%lo0]:123<->[::1]:456\",20,10,\r\n")
        let row = try XCTUnwrap(samples.first?.connections.first)
        XCTAssertEqual(row.localEndpoint, "[fe80::1%lo0]:123")
        XCTAssertEqual(row.remoteEndpoint, "[::1]:456")
        XCTAssertEqual(row.transport, "tcp6")
        XCTAssertEqual(row.receivedBytes, 10)
        XCTAssertEqual(row.sentBytes, 20)
    }
    func testInvalidMissingNegativeOverflowAndUnclosedCSVAreUnavailable() {
        for counter in ["-1", "", "1.5", "12 KiB", "18446744073709551616"] {
            XCTAssertThrowsError(try NettopParser.parse(",bytes_in,bytes_out,\nwine.1,0,0,\ntcp4 a:1<->b:2,\(counter),2,\n"), counter)
        }
        XCTAssertThrowsError(try NettopParser.parse("permission denied"))
        XCTAssertThrowsError(try NettopParser.parse(",bytes_in,bytes_out,\n\"unclosed"))
        XCTAssertThrowsError(try NettopParser.parse(",bytes_in,bytes_out,\ntcp4 a:1<->b:2,1,2,\n"))
        XCTAssertThrowsError(try NettopParser.parse(",bytes_in,bytes_out,\nwine.1,0,0,\ntcp4 broken,1,2,\n"))
    }
    func testEmptyValidSnapshotIsDifferentFromMissingOutput() throws {
        XCTAssertTrue(try NettopParser.parse(",bytes_in,bytes_out,\n")[0].connections.isEmpty)
        XCTAssertThrowsError(try NettopParser.parse(""))
    }
    func testFirstSampleHasUnknownRateAndNoHistoricalBytesThenUsesElapsedTime() throws {
        var reducer = TrafficRateReducer()
        let first = reducer.reduce(try snapshot(65536, 131072), identities: [46658: owner()], at: 10)
        XCTAssertNil(first.first?.downloadBps)
        XCTAssertNil(first.first?.uploadBps)
        XCTAssertEqual(first.first?.receivedBytes, 0)
        let next = reducer.reduce(try snapshot(65536 + 128, 131072 + 256), identities: [46658: owner()], at: 12)
        XCTAssertEqual(next.first?.downloadBps, 64)
        XCTAssertEqual(next.first?.uploadBps, 128)
        XCTAssertEqual(next.first?.receivedBytes, 128)
        XCTAssertEqual(next.first?.sentBytes, 256)
        let idle = reducer.reduce(try snapshot(65536 + 128, 131072 + 256), identities: [46658: owner()], at: 14)
        XCTAssertEqual(idle.first?.downloadBps, 0)
        XCTAssertEqual(idle.first?.receivedBytes, 128)
    }
    func testResetRebaselinesOnlyResetDirectionAndPreservesObservedTotals() throws {
        var reducer = TrafficRateReducer()
        _ = reducer.reduce(try snapshot(100, 200), identities: [46658: owner()], at: 0)
        _ = reducer.reduce(try snapshot(200, 300), identities: [46658: owner()], at: 2)
        let reset = reducer.reduce(try snapshot(1, 400), identities: [46658: owner()], at: 4)
        XCTAssertNil(reset.first?.downloadBps)
        XCTAssertEqual(reset.first?.uploadBps, 50)
        XCTAssertEqual(reset.first?.receivedBytes, 100)
        XCTAssertEqual(reset.first?.sentBytes, 200)
        let next = reducer.reduce(try snapshot(21, 420), identities: [46658: owner()], at: 6)
        XCTAssertEqual(next.first?.downloadBps, 10)
        XCTAssertEqual(next.first?.receivedBytes, 120)
    }
    func testDisappearanceAndPIDReuseCannotBridgeCounters() throws {
        var reducer = TrafficRateReducer()
        let initial = reducer.reduce(try snapshot(10, 20), identities: [46658: owner()], at: 1)
        let empty = try NettopParser.parse(",bytes_in,bytes_out,\n")[0]
        XCTAssertTrue(reducer.reduce(empty, identities: [46658: owner()], at: 2).isEmpty)
        let returned = reducer.reduce(try snapshot(1000, 2000), identities: [46658: owner()], at: 3)
        XCTAssertNil(returned.first?.downloadBps)
        XCTAssertEqual(returned.first?.receivedBytes, 0)
        let reused = reducer.reduce(try snapshot(2000, 3000), identities: [46658: owner("200.2")], at: 4)
        XCTAssertNil(reused.first?.downloadBps)
        XCTAssertNotEqual(initial.first?.id, reused.first?.id)
    }
    func testUnownedRowsAndNonIncreasingOrStaleTimeNeverProduceRate() throws {
        var reducer = TrafficRateReducer()
        XCTAssertTrue(reducer.reduce(try snapshot(10, 20), identities: [:], at: 1).isEmpty)
        _ = reducer.reduce(try snapshot(10, 20), identities: [46658: owner()], at: 1)
        XCTAssertNil(reducer.reduce(try snapshot(20, 30), identities: [46658: owner()], at: 1).first?.downloadBps)
        XCTAssertNil(reducer.reduce(try snapshot(200, 300), identities: [46658: owner()], at: 30).first?.downloadBps)
        XCTAssertEqual(reducer.reduce(try snapshot(220, 320), identities: [46658: owner()], at: 32).first?.downloadBps, 10)
    }
    func testFailureInvalidationRebaselinesWithoutCountingGap() throws {
        var reducer = TrafficRateReducer()
        _ = reducer.reduce(try snapshot(10, 20), identities: [46658: owner()], at: 1)
        _ = reducer.reduce(try snapshot(20, 30), identities: [46658: owner()], at: 3)
        reducer.invalidate()
        let next = reducer.reduce(try snapshot(1000, 2000), identities: [46658: owner()], at: 5)
        XCTAssertNil(next.first?.downloadBps)
        XCTAssertEqual(next.first?.receivedBytes, 10)
    }
    func testDuplicateSocketTuplesAreAggregatedWithoutDuplicateIDs() throws {
        let csv = ",bytes_in,bytes_out,\nwine.46658,500,600,\nudp4 *:123<->*:*,10,20,\nudp4 *:123<->*:*,30,40,\n"
        var reducer = TrafficRateReducer()
        let first = reducer.reduce(try NettopParser.parse(csv)[0], identities: [46658: owner()], at: 1)
        XCTAssertEqual(first.count, 1)
        let second = reducer.reduce(try NettopParser.parse(csv.replacingOccurrences(of: "30,40", with: "50,80"))[0], identities: [46658: owner()], at: 3)
        XCTAssertEqual(second.first?.downloadBps, 10)
        XCTAssertEqual(second.first?.uploadBps, 20)
    }
    func testExactExecutableMappingRejectsBasenameArgumentsAndAmbiguity() {
        let appID = UUID()
        let paths = [appID: "C:\\Program Files\\Origin\\Origin64.exe"]
        XCTAssertEqual(TrafficAttribution.applicationID(command: "c:/program files/origin/ORIGIN64.EXE", paths: paths), appID)
        XCTAssertNil(TrafficAttribution.applicationID(command: "Origin64.exe", paths: paths))
        XCTAssertNil(TrafficAttribution.applicationID(command: "C:\\Program Files\\Origin\\Origin64.exe --helper", paths: paths))
        XCTAssertNil(TrafficAttribution.applicationID(command: "C:\\Program Files\\Origin\\helper.exe", paths: paths))
        XCTAssertNil(TrafficAttribution.applicationID(command: paths[appID]!, paths: [appID: paths[appID]!, UUID(): paths[appID]!]))
    }
    func testEngineOwnershipUsesDirectoryBoundaryAndRejectsSharedRoot() {
        let id = UUID()
        XCTAssertEqual(TrafficAttribution.containerID(executablePath: "/engine/bin/wine", engineRoots: [id: "/engine"]), id)
        XCTAssertNil(TrafficAttribution.containerID(executablePath: "/engine-other/bin/wine", engineRoots: [id: "/engine"]))
        XCTAssertNil(TrafficAttribution.containerID(executablePath: "/engine/bin/wine", engineRoots: [id: "/engine", UUID(): "/engine"]))
    }
    func testPSPreservesFullCommandAndConvertsRSSKiB() throws {
        let rows = try TrafficProcessSample.parsePS(" 46658 12.5 2048 C:\\Program Files\\Origin\\Origin64.exe\n")
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].command, "C:\\Program Files\\Origin\\Origin64.exe")
        XCTAssertEqual(rows[0].rssBytes, 2097152)
        XCTAssertEqual(rows[0].cpuPercent, 12.5)
        XCTAssertThrowsError(try TrafficProcessSample.parsePS("1 NaN 123 wine"))
        XCTAssertThrowsError(try TrafficProcessSample.parsePS("1 1.0 -2 wine"))
    }
    func testUIConversionKeepsUnknownDistinctAndAllDoublesFinite() throws {
        var reducer = TrafficRateReducer()
        let first = try XCTUnwrap(reducer.reduce(snapshot(100, 200), identities: [46658: owner()], at: 1).first?.flow)
        XCTAssertFalse(first.hasRateBaseline)
        XCTAssertEqual(first.downloadBps, 0)
        XCTAssertEqual(first.uploadBps, 0)
        let measured = try XCTUnwrap(reducer.reduce(snapshot(120, 240), identities: [46658: owner()], at: 3).first?.flow)
        XCTAssertTrue(measured.hasRateBaseline)
        XCTAssertEqual(measured.downloadBps, 10)
        let reset = try XCTUnwrap(reducer.reduce(snapshot(1, 260), identities: [46658: owner()], at: 5).first?.flow)
        XCTAssertFalse(reset.hasRateBaseline)
        XCTAssertTrue(reset.downloadBps.isFinite && reset.uploadBps.isFinite)
    }
    func testNewHeaderCannotReusePreviousProcessContext() {
        XCTAssertThrowsError(try NettopParser.parse(",bytes_in,bytes_out,\nwine.46658,1,2,\n,bytes_in,bytes_out,\ntcp4 a:1<->b:2,1,2,\n"))
    }
    func testMixedTCPAndUDPRemainSeparateFlows() throws {
        let csv = ",bytes_in,bytes_out,\nwine.46658,999999,999999,\ntcp4 127.0.0.1:52611<->127.0.0.1:53135,65536,131072,\nudp4 127.0.0.1:52611<->127.0.0.1:53135,45056,90112,\n"
        let snapshot = try NettopParser.parse(csv)[0]
        var reducer = TrafficRateReducer()
        let rows = reducer.reduce(snapshot, identities: [46658: owner()], at: 0)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(Set(rows.map(\.id)).count, 2)
        XCTAssertEqual(Set(rows.map(\.transport)), Set(["tcp4", "udp4"]))
    }
    func testSocketCountChangeAndAggregateOverflowRebaseline() throws {
        var reducer = TrafficRateReducer()
        let row = NettopConnection(pid: 46658, localEndpoint: "a:1", remoteEndpoint: "b:2", transport: "udp4", receivedBytes: UInt64.max, sentBytes: 100)
        _ = reducer.reduce(NettopSnapshot(connections: [row]), identities: [46658: owner()], at: 1)
        let overflow = reducer.reduce(NettopSnapshot(connections: [row, row]), identities: [46658: owner()], at: 3)
        XCTAssertFalse(try XCTUnwrap(overflow.first?.flow).hasRateBaseline)
        XCTAssertEqual(overflow.first?.receivedBytes, 0)
        let returned = reducer.reduce(NettopSnapshot(connections: [row]), identities: [46658: owner()], at: 5)
        XCTAssertNil(returned.first?.downloadBps)
    }
    func testNonFiniteTimestampDoesNotPoisonFutureBaseline() throws {
        var reducer = TrafficRateReducer()
        _ = reducer.reduce(try snapshot(10, 20), identities: [46658: owner()], at: .nan)
        XCTAssertNil(reducer.reduce(try snapshot(20, 40), identities: [46658: owner()], at: 1).first?.downloadBps)
        XCTAssertEqual(reducer.reduce(try snapshot(40, 80), identities: [46658: owner()], at: 3).first?.downloadBps, 10)
    }

}
