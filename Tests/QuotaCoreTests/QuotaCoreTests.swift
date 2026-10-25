import Foundation
import QuotaCore

private var checks = 0
private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    guard lhs == rhs else { fatalError("不相等：\(lhs) != \(rhs)", file: file, line: line) }
}
private func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    checks += 1
    guard value else { fatalError("条件未满足", file: file, line: line) }
}

@main
struct QuotaCoreTests {
    static func main() throws {
        let tests = QuotaCoreTests()
        try tests.testDecodeActualWeeklyShapeAndNoPhantomSecondary()
        try tests.testPreferMultiBucketAndKeepIndependentWindows()
        try tests.testLegacyAndNullMissingValues()
        tests.testInitialFullQuotaDoesNotNotify()
        tests.testRecoveryNotifiesOnceThenRearmsAfterUsage()
        try tests.testPersistedBaselineSurvivesRestartWithoutDuplicate()
        tests.testAccountOrWindowChangeDoesNotNotify()
        tests.testPartialRecoveryAndRoundedFullAreNotFull()
        tests.testEachWindowRecoversIndependently()
        print("PASS: 9 个测试场景，\(checks) 个断言")
    }
    func decode(_ json: String) throws -> LimitsResponse {
        try JSONDecoder().decode(LimitsResponse.self, from: Data(json.utf8))
    }
    func window(_ used: Double, id: String = "codex:primary:10080") -> QuotaWindow {
        QuotaWindow(id: id, usedPercent: used, durationMinutes: 10080)
    }

    func testDecodeActualWeeklyShapeAndNoPhantomSecondary() throws {
        let result = try decode(#"{"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":10,"windowDurationMins":10080,"resetsAt":1793412431},"secondary":null}}}"#)
        let windows = result.windows()
        expectEqual(windows.count, 1)
        expectEqual(windows.first?.percentageText, "90%")
        expectEqual(windows.first?.periodText, "7 天额度")
        expectEqual(windows.first?.resetsAt?.timeIntervalSince1970, 1793412431)
    }

    func testPreferMultiBucketAndKeepIndependentWindows() throws {
        let result = try decode(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"primary":{"usedPercent":20,"windowDurationMins":300},"secondary":{"usedPercent":40,"windowDurationMins":10080}},"other":{"primary":{"usedPercent":50}}}}"#)
        expectEqual(result.windows().count, 3)
        expectEqual(result.windows().map(\.remaining), [80, 60, 50])
    }

    func testLegacyAndNullMissingValues() throws {
        let result = try decode(#"{"rateLimits":{"primary":{"usedPercent":0},"secondary":{"usedPercent":null}}}"#)
        expectEqual(result.windows().map(\.percentageText), ["100%"])
        expectTrue(try decode(#"{"rateLimits":null}"#).windows().isEmpty)
        expectTrue(try decode(#"{"rateLimits":{"primary":{"usedPercent":-1},"secondary":{"usedPercent":101}}}"#).windows().isEmpty)
    }

    func testInitialFullQuotaDoesNotNotify() {
        var tracker = RecoveryTracker()
        expectTrue(tracker.observe(account: "a", windows: [window(0)]).isEmpty)
    }

    func testRecoveryNotifiesOnceThenRearmsAfterUsage() {
        var tracker = RecoveryTracker()
        expectTrue(tracker.observe(account: "a", windows: [window(10)]).isEmpty)
        expectEqual(tracker.observe(account: "a", windows: [window(0)]).count, 1)
        expectTrue(tracker.observe(account: "a", windows: [window(0)]).isEmpty)
        expectTrue(tracker.observe(account: "a", windows: [window(1)]).isEmpty)
        expectEqual(tracker.observe(account: "a", windows: [window(0)]).count, 1)
    }

    func testPersistedBaselineSurvivesRestartWithoutDuplicate() throws {
        var first = RecoveryTracker()
        _ = first.observe(account: "a", windows: [window(10)])
        let data = try JSONEncoder().encode(first.state)
        var restarted = RecoveryTracker(state: try JSONDecoder().decode(RecoveryState.self, from: data))
        expectEqual(restarted.observe(account: "a", windows: [window(0)]).count, 1)
        var again = RecoveryTracker(state: restarted.state)
        expectTrue(again.observe(account: "a", windows: [window(0)]).isEmpty)
    }

    func testAccountOrWindowChangeDoesNotNotify() {
        var tracker = RecoveryTracker()
        _ = tracker.observe(account: "a", windows: [window(10)])
        expectTrue(tracker.observe(account: "b", windows: [window(0)]).isEmpty)
        _ = tracker.observe(account: "b", windows: [window(10)])
        expectTrue(tracker.observe(account: "b", windows: [window(0, id: "codex:primary:300")]).isEmpty)
    }

    func testPartialRecoveryAndRoundedFullAreNotFull() {
        var tracker = RecoveryTracker()
        _ = tracker.observe(account: "a", windows: [window(90)])
        expectTrue(tracker.observe(account: "a", windows: [window(0.1)]).isEmpty)
        expectEqual(window(0.1).percentageText, "99%")
        expectEqual(tracker.observe(account: "a", windows: [window(0)]).count, 1)
    }

    func testEachWindowRecoversIndependently() {
        var tracker = RecoveryTracker()
        _ = tracker.observe(account: "a", windows: [window(10, id: "short"), window(90, id: "week")])
        let recovered = tracker.observe(account: "a", windows: [window(0, id: "short"), window(90, id: "week")])
        expectEqual(recovered.map(\.id), ["short"])
    }
}
