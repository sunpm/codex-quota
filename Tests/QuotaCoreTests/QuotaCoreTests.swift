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
        try tests.testClaudeWindowsAndGenericPrecedence()
        try tests.testMissingAndInvalidServiceMeasurements()
        try tests.testCursorBillingAndTeamQuota()
        try tests.testAntigravitySummaryAndLegacyModels()
        try tests.testServiceIsolationAndMutedRecovery()
        tests.testServicePreferencesPersistIndependently()
        tests.testRefreshSchedulesRespectRateLimits()
        try tests.testLegacyStateMigration()
        print("PASS: 17 个测试场景，\(checks) 个断言")
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

    func testClaudeWindowsAndGenericPrecedence() throws {
        let data = Data(#"{"five_hour":{"utilization":30,"resets_at":"2026-10-25T12:00:00.000Z"},"seven_day":{"utilization":70},"seven_day_sonnet":{"utilization":10},"limits":[{"kind":"session","percent":0},{"kind":"weekly_scoped","percent":12,"scope":{"model":{"id":"sonnet","display_name":"Sonnet"}}}]}"#.utf8)
        let windows = try ServiceQuotaParser.claude(data)
        expectEqual(windows.count, 3)
        expectEqual(windows.map(\.usedPercent), [0, 70, 12])
        expectEqual(windows.first?.id, "claude:five_hour")
        expectTrue(windows.first?.resetsAt != nil)
        expectEqual(windows.last?.displayLabel, "Sonnet · 7 天")
        let inactive = try ServiceQuotaParser.claude(Data(#"{"five_hour":{"utilization":20},"limits":[{"kind":"session","percent":0,"is_active":false}]}"#.utf8))
        expectTrue(inactive.isEmpty)
    }

    func testMissingAndInvalidServiceMeasurements() throws {
        expectTrue(try ServiceQuotaParser.claude(Data(#"{"five_hour":{},"seven_day":{"utilization":true},"seven_day_opus":{"utilization":-1}}"#.utf8)).isEmpty)
        expectTrue(try ServiceQuotaParser.cursor(Data(#"{"individualUsage":{"plan":{"totalPercentUsed":null,"autoPercentUsed":false,"apiPercentUsed":-1}}}"#.utf8)).isEmpty)
        expectTrue(try ServiceQuotaParser.cursor(Data(#"{"individualUsage":{"plan":{"used":0,"limit":0}}}"#.utf8)).isEmpty)
        expectTrue(try ServiceQuotaParser.cursor(Data(#"{"individualUsage":{"plan":{"enabled":false,"totalPercentUsed":0}}}"#.utf8)).isEmpty)
        expectTrue(try ServiceQuotaParser.antigravitySummary(Data(#"{"groups":[{"displayName":"Gemini","buckets":[{"bucketId":"weekly","remainingFraction":null},{"bucketId":"session","remainingFraction":2},{"bucketId":"disabled","remainingFraction":1,"disabled":true}]}]}"#.utf8)).isEmpty)
        expectTrue(try ServiceQuotaParser.antigravitySummary(Data(#"{"code":401,"groups":[{"buckets":[{"bucketId":"x","remainingFraction":1}]}]}"#.utf8)).isEmpty)
        expectEqual(ServiceQuotaParser.number(0), 0)
        expectEqual(ServiceQuotaParser.number(1), 1)
        expectEqual(ServiceQuotaParser.number(true), nil)
        expectEqual(ServiceQuotaParser.number("nan"), nil)
    }

    func testCursorBillingAndTeamQuota() throws {
        let windows = try ServiceQuotaParser.cursor(Data(#"{"billingCycleStart":"2026-10-01T00:00:00Z","billingCycleEnd":"2026-11-01T00:00:00Z","individualUsage":{"plan":{"totalPercentUsed":1,"autoPercentUsed":0,"apiPercentUsed":120}}}"#.utf8))
        expectEqual(windows.map(\.percentageText), ["99%", "100%", "0%"])
        expectEqual(windows.first?.durationMinutes, 31 * 1440)
        expectEqual(windows.first?.displayLabel, "账期总额度")
        expectTrue(windows.first?.resetsAt != nil)
        let team = try ServiceQuotaParser.cursor(Data(#"{"limitType":"team","individualUsage":{"plan":{"totalPercentUsed":0}},"teamUsage":{"pooled":{"used":50,"limit":200}}}"#.utf8))
        expectEqual(team.first?.usedPercent, 25)
        let nextMonth = try ServiceQuotaParser.cursor(Data(#"{"billingCycleStart":"2026-11-01T00:00:00Z","billingCycleEnd":"2026-12-01T00:00:00Z","individualUsage":{"plan":{"used":0,"limit":200}}}"#.utf8))
        expectEqual(nextMonth.first?.id, windows.first?.id)
        var tracker = RecoveryTracker()
        _ = tracker.observe(account: "a", windows: windows)
        expectEqual(tracker.observe(account: "a", windows: nextMonth).count, 1)
    }

    func testAntigravitySummaryAndLegacyModels() throws {
        let summary = try ServiceQuotaParser.antigravitySummary(Data(#"{"response":{"groups":[{"displayName":"Gemini","buckets":[{"bucketId":"weekly","displayName":"Weekly","remainingFraction":0.8,"resetTime":"2026-11-01T00:00:00Z"},{"bucketId":"session","displayName":"5 hours","remaining":{"case":"remainingFraction","value":1}}]},{"displayName":"Claude","buckets":[{"bucketId":"weekly","remainingFraction":0.2}]}]}}"#.utf8))
        expectEqual(summary.count, 3)
        expectTrue(abs(summary[0].usedPercent - 20) < 0.00001)
        expectEqual(summary[1].usedPercent, 0)
        expectTrue(summary[0].id != summary[2].id)
        expectTrue(summary[0].resetsAt != nil)
        let status = Data(#"{"userStatus":{"email":"fixture@example.invalid","cascadeModelConfigData":{"clientModelConfigs":[{"label":"Gemini","modelOrAlias":{"model":"gemini"},"quotaInfo":{"remainingFraction":0.5}},{"label":"Unknown","modelOrAlias":{"model":"unknown"},"quotaInfo":{}}]}}}"#.utf8)
        expectEqual(try ServiceQuotaParser.antigravityStatus(status).map(\.percentageText), ["50%"])
        expectEqual(try ServiceQuotaParser.antigravityAccount(status), "fixture@example.invalid")
        expectEqual(try ServiceQuotaParser.antigravityAccount(Data("{}".utf8)), nil)
    }

    func testServiceIsolationAndMutedRecovery() throws {
        var tracker = ServiceRecoveryTracker()
        for service in QuotaService.allCases {
            expectTrue(tracker.observe(service: service, account: "same", windows: [window(20)], notify: true).isEmpty)
        }
        expectTrue(tracker.observe(service: .claude, account: "same", windows: [window(0)], notify: false).isEmpty)
        let saved = try JSONEncoder().encode(tracker)
        tracker = try JSONDecoder().decode(ServiceRecoveryTracker.self, from: saved)
        expectTrue(tracker.observe(service: .claude, account: "same", windows: [window(0)], notify: true).isEmpty)
        expectEqual(tracker.observe(service: .cursor, account: "same", windows: [window(0)], notify: true).count, 1)
        expectTrue(tracker.observe(service: .antigravity, account: "changed", windows: [window(0)], notify: true).isEmpty)
        expectEqual(tracker.observe(service: .codex, account: "same", windows: [window(0)], notify: true).count, 1)
        _ = tracker.observe(service: .claude, account: "same", windows: [window(1)], notify: true)
        expectEqual(tracker.observe(service: .claude, account: "same", windows: [window(0)], notify: true).count, 1)
        _ = tracker.observe(service: .cursor, account: "same", windows: [window(1)], notify: true)
        tracker.clear(.cursor)
        expectTrue(tracker.observe(service: .cursor, account: "same", windows: [window(0)], notify: true).isEmpty)
    }

    func testServicePreferencesPersistIndependently() {
        let suite = "QuotaCoreChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = ServicePreferences(defaults: defaults)
        for service in QuotaService.allCases {
            expectTrue(preferences.isEnabled(service))
            expectTrue(preferences.notificationsEnabled(service))
        }
        preferences.setNotificationsEnabled(false, for: .claude)
        preferences.setEnabled(false, for: .cursor)
        let reopened = ServicePreferences(defaults: UserDefaults(suiteName: suite)!)
        expectTrue(!reopened.notificationsEnabled(.claude))
        expectTrue(reopened.isEnabled(.claude))
        expectTrue(!reopened.isEnabled(.cursor))
        expectTrue(reopened.notificationsEnabled(.cursor))
        expectTrue(reopened.notificationsEnabled(.codex))
    }

    func testRefreshSchedulesRespectRateLimits() {
        var first = RefreshSchedule(), other = RefreshSchedule()
        let now = Date(timeIntervalSince1970: 1000)
        expectEqual(first.failed(at: now), 30)
        expectTrue(!first.canRefresh(force: false, at: now))
        expectTrue(first.canRefresh(force: true, at: now))
        expectEqual(first.failed(retryAfter: 900, at: now), 900)
        expectTrue(!first.canRefresh(force: true, at: now.addingTimeInterval(899)))
        expectTrue(first.canRefresh(force: false, at: now.addingTimeInterval(900)))
        expectTrue(other.canRefresh(force: false, at: now))
        first.succeeded()
        expectEqual(first.failures, 0)
        expectTrue(first.canRefresh(force: false, at: now))
        for _ in 0..<10 { other.failed(at: now) }
        expectEqual(other.nextAttempt, now.addingTimeInterval(300))
    }

    func testLegacyStateMigration() throws {
        let old = RecoveryState(accountFingerprint: "a", usedByWindow: ["codex:primary:10080": 10])
        var tracker = ServiceRecoveryTracker(states: [QuotaService.codex.rawValue: old])
        expectEqual(tracker.observe(service: .codex, account: "a", windows: [window(0)], notify: true).count, 1)
        tracker = try JSONDecoder().decode(ServiceRecoveryTracker.self, from: JSONEncoder().encode(tracker))
        expectTrue(tracker.observe(service: .codex, account: "a", windows: [window(0)], notify: true).isEmpty)
    }
}
