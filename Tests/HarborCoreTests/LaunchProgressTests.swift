import XCTest
@testable import HarborCore

final class LaunchProgressTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    func testElapsedTimeNeverInventsProgress() {
        var progress = LaunchProgress(containerID: UUID(), appID: "730", title: "CS2", now: start)
        progress.checkedFiles(at: start)
        XCTAssertEqual(progress.fraction, 0.2)
        XCTAssertTrue(progress.isTakingLong(at: start.addingTimeInterval(60)))
        XCTAssertEqual(progress.fraction, 0.2)
        XCTAssertEqual(progress.outcome, .pending)
        XCTAssertFalse(progress.explanation.contains("未响应"))
    }
    func testProcessIsNotWindowCompletion() {
        var progress = LaunchProgress(containerID: UUID(), appID: "730", title: "CS2", now: start)
        progress.checkedFiles(at: start)
        var evidence = LaunchEvidence(); evidence.runtimeRunning = true; evidence.steamPID = 1; evidence.gamePID = 2
        progress.observe(evidence, at: start.addingTimeInterval(5))
        XCTAssertEqual(progress.completedCount, 4); XCTAssertEqual(progress.outcome, .pending)
        XCTAssertEqual(progress.current, .window)
        evidence.visibleWindowPIDs = [2]
        progress.observe(evidence, at: start.addingTimeInterval(8))
        XCTAssertEqual(progress.outcome, .windowDetected); XCTAssertEqual(progress.fraction, 1)
        XCTAssertTrue(progress.explanation.contains("匹配"))
        progress.observe(.init(), at: start.addingTimeInterval(600))
        XCTAssertEqual(progress.outcome, .exited)
        XCTAssertEqual(progress.elapsed(at: start.addingTimeInterval(600)), 8)
    }
    func testSteamWebHelperWindowCountsForSteamButNotGame() {
        var progress = LaunchProgress(containerID: UUID(), appID: nil, title: "Steam", now: start)
        progress.checkedFiles(at: start)
        var evidence = LaunchEvidence(); evidence.steamPID = 1; evidence.steamWindowPID = 3; evidence.visibleWindowPIDs = [3]
        progress.observe(evidence, at: start.addingTimeInterval(2))
        XCTAssertEqual(progress.completedCount, 4); XCTAssertEqual(progress.outcome, .windowDetected)
        var game = LaunchProgress(containerID: UUID(), appID: "730", title: "CS2", now: start)
        game.observe(evidence, at: start.addingTimeInterval(2))
        XCTAssertEqual(game.outcome, .pending)
    }
    func testExitBeforeWindowAndStoppedTrackingAreDistinct() {
        var progress = LaunchProgress(containerID: UUID(), appID: "730", title: "CS2", now: start)
        var evidence = LaunchEvidence(); evidence.gamePID = 9
        progress.observe(evidence, at: start)
        progress.observe(.init(), at: start.addingTimeInterval(2))
        XCTAssertEqual(progress.outcome, .pending)
        progress.observe(.init(), at: start.addingTimeInterval(7))
        XCTAssertEqual(progress.outcome, .exited)
        progress.stop(at: start.addingTimeInterval(3))
        progress.observe(evidence, at: start.addingTimeInterval(4))
        XCTAssertEqual(progress.outcome, .stopped)
    }
    func testConnectionParserDoesNotReturnCredentialsOrAssumeGameplay() {
        let text = "[2026-10-14 01:00:00] RecvMsgClientLogOnResponse() [U:1:123456789] OK token=secret\n[2026-10-14 01:02:00] LogOff"
        XCTAssertEqual(SteamSignals.connection(in: text, since: .distantPast), .offline)
        XCTAssertEqual(SteamSignals.connection(in: text, since: .distantFuture), .unknown)
        XCTAssertEqual(SteamSignals.connection(in: "[2026-10-14 01:00:00] LogOnResponse OK cookie=private", since: .distantPast), .online)
    }
    func testOldOrOtherGameDiskErrorsDoNotFailCurrentLaunch() {
        let text = "[2026-10-14 01:00:00] AppID 730 update canceled (Disk write failure)"
        XCTAssertTrue(SteamSignals.hasDiskFailure(in: text, appID: "730", since: .distantPast))
        XCTAssertFalse(SteamSignals.hasDiskFailure(in: text, appID: "73", since: .distantPast))
        XCTAssertFalse(SteamSignals.hasDiskFailure(in: text, appID: "730", since: .distantFuture))
    }
    func testWindowsLogLineEndingsAndCompletionNoticeKeepOnlineState() {
        let text = "\r\n[2026-10-14 10:58:31] Connect()\r\n[2026-10-14 10:58:33] RecvMsgClientLogOnResponse() : 'OK'\r\n[2026-10-14 10:58:33] RecvMsgClientLogOnResponse() : processing complete\r\n"
        XCTAssertEqual(SteamSignals.connection(in: text, since: .distantPast), .online)
        XCTAssertEqual(SteamSignals.connection(in: text + "[2026-10-14 11:00:00] RecvMsgClientLogOnResponse() : 'NoConnection'\r\n", since: .distantPast), .offline)
        let error = "\r\n[2026-10-14 10:58:33] AppID 730 update canceled (Disk write failure)\r\n"
        XCTAssertTrue(SteamSignals.hasDiskFailure(in: error, appID: "730", since: .distantPast))
    }
    func testSteamBootstrapWindowDoesNotFinishClientLaunch() {
        var progress = LaunchProgress(containerID: UUID(), appID: nil, title: "Steam", now: start)
        progress.checkedFiles(at: start)
        var evidence = LaunchEvidence(); evidence.steamPID = 1; evidence.visibleWindowPIDs = [1]
        progress.observe(evidence, at: start.addingTimeInterval(1))
        XCTAssertEqual(progress.completedCount, 3)
        XCTAssertEqual(progress.outcome, .pending)
        evidence.steamWindowPID = 2; evidence.visibleWindowPIDs = [1,2]
        progress.observe(evidence, at: start.addingTimeInterval(2))
        XCTAssertEqual(progress.outcome, .windowDetected)
    }
    func testDownloadProgressUsesRecordedBytesNotElapsedTime() {
        let text = #""AppState" { "StateFlags" "1048582" "BytesToDownload" "1000" "BytesDownloaded" "250" }"#
        let progress = SteamSignals.transfer(in: text, recordedAt: start)
        XCTAssertEqual(progress?.fraction, 0.25); XCTAssertEqual(progress?.recordedAt, start)
        XCTAssertNil(SteamSignals.transfer(in: text.replacingOccurrences(of: "1048582", with: "4"), recordedAt: start))
    }
    func testDiskErrorInRequestSecondIsNotMissed() throws {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let second = try XCTUnwrap(formatter.date(from: "2026-10-14 01:00:00"))
        let line = "[2026-10-14 01:00:00] AppID 730 update canceled (Disk write failure)"
        XCTAssertTrue(SteamSignals.hasDiskFailure(in: line, appID: "730", since: second.addingTimeInterval(0.7)))
        XCTAssertFalse(SteamSignals.hasDiskFailure(in: line, appID: "730", since: second.addingTimeInterval(1)))
    }
    func testGameProcessDoesNotInventSteamConnection() {
        var progress = LaunchProgress(containerID: UUID(), appID: "730", title: "CS2", now: start)
        var evidence = LaunchEvidence(); evidence.gamePID = 2
        progress.observe(evidence, at: start)
        XCTAssertTrue(progress.completed.contains(.game))
        XCTAssertFalse(progress.completed.contains(.steam))
        XCTAssertEqual(progress.connection, .unknown)
    }
    func testOldActivityWithoutProgressStillDecodes() throws {
        let record = ActivityRecord(title: "Legacy", detail: "sent", state: .requested)
        let bytes = try JSONEncoder().encode(record)
        let result = try JSONDecoder().decode(ActivityRecord.self, from: bytes)
        XCTAssertNil(result.launch)
    }
}
