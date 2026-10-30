// Update-driver integration adapted from nanvon/cc-bar (MIT), Core/AppUpdater.swift.
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
import AppKit
import Combine
import Darwin
import Sparkle

@MainActor
final class AppUpdateModel: NSObject, ObservableObject, SPUUserDriver, SPUUpdaterDelegate {
    static let releasesURL = URL(string: "https://github.com/sunpm/codex-quota/releases/latest")!

    enum Phase {
        case idle, checking, available, downloading, preparing, installing, upToDate, failed
    }

    struct Release {
        let version: String
        let build: String
        let pageURL: URL
        let isNewer: Bool
        let notes: String?
        var status: String { "发现新版本 \(version)" }
    }

    let currentVersion: String
    let architecture: String
    let installedReleaseNotes: String
    @Published var showsInstalledReleaseNotes: Bool
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var release: Release?
    @Published private(set) var error: String?
    @Published private(set) var automaticallyChecks: Bool
    @Published private(set) var completedManualChecks = 0
    @Published private(set) var downloadedBytes: UInt64 = 0
    @Published private(set) var expectedBytes: UInt64 = 0
    @Published private(set) var extractionProgress = 0.0
    @Published private var cancellation: (() -> Void)?
    @Published private var retryTermination: (() -> Void)?
    @Published private var canCheck = true
    var showSettings: (() -> Void)?

    private let defaults: UserDefaults
    private var updater: SPUUpdater?
    private var checkObservation: NSKeyValueObservation?
    private var configurationError: String?
    private var didStart = false
    private var paused = false
    private var manualCheckPending = false
    private var installWasConfirmed = false
    private var confirmedBuild: String?
    private var informationOnly = false
    private var latestStatus = "已是最新正式版"

    var checking: Bool { phase == .checking }
    var canCheckForUpdates: Bool {
        canCheck && !manualCheckPending
            && ![.downloading, .preparing, .installing].contains(phase)
    }
    var canInstall: Bool { phase == .available && release != nil && canCheckForUpdates && !informationOnly }
    var canCancel: Bool { cancellation != nil }
    var canRetryInstallation: Bool { retryTermination != nil }
    var downloadProgress: Double? {
        expectedBytes > 0 ? min(1, Double(downloadedBytes) / Double(expectedBytes)) : nil
    }
    var status: String? {
        switch phase {
        case .downloading: return "正在下载 \(release?.version ?? "更新")…"
        case .preparing: return "正在准备安装…"
        case .installing: return "正在安装并重启…"
        case .upToDate: return latestStatus
        case .available: return release?.status
        case .idle, .checking, .failed: return nil
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticallyChecks = defaults.object(forKey: "updates.automaticallyChecks") as? Bool ?? true
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "ReleaseVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        let notes = Bundle.main.url(forResource: "ReleaseNotes", withExtension: "md")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        installedReleaseNotes = notes
        showsInstalledReleaseNotes = !notes.isEmpty
            && defaults.string(forKey: "updates.lastShownReleaseNotesVersion") != currentVersion
        #if arch(arm64)
        architecture = "AppleSilicon"
        #else
        // Rosetta 下仍选择这台 Mac 的原生 Apple Silicon 更新包。
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        architecture = result == 0 && translated == 1 ? "AppleSilicon" : "Intel"
        #endif
        super.init()
    }

    func markInstalledReleaseNotesShown() {
        defaults.set(currentVersion, forKey: "updates.lastShownReleaseNotesVersion")
    }

    private func start() {
        guard !didStart else { return }
        didStart = true
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            configurationError = "此构建未启用应用内更新，请从发布页下载安装。"
            return
        }
        // 保留旧版用户选择；后续由 Sparkle 调度，避免并存两套定时检查。
        if defaults.object(forKey: "SUEnableAutomaticChecks") == nil {
            defaults.set(automaticallyChecks, forKey: "SUEnableAutomaticChecks")
        }
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        do {
            try updater.start()
            self.updater = updater
            automaticallyChecks = updater.automaticallyChecksForUpdates
            canCheck = updater.canCheckForUpdates && !updater.sessionInProgress
            // canCheckForUpdates 也允许聚焦已有会话；这里仅允许开始新的检查。
            checkObservation = updater.observe(\.sessionInProgress, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    guard let self, let updater = self.updater else { return }
                    self.canCheck = updater.canCheckForUpdates && !updater.sessionInProgress
                    if self.manualCheckPending && self.canCheck && self.phase != .checking {
                        self.phase = .checking
                        updater.checkForUpdates()
                    }
                }
            }
            if automaticallyChecks { updater.checkForUpdatesInBackground() }
        } catch {
            configurationError = "无法启动软件更新：\(error.localizedDescription)"
        }
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        automaticallyChecks = enabled
        defaults.set(enabled, forKey: "updates.automaticallyChecks")
        updater?.automaticallyChecksForUpdates = enabled
        if !didStart { defaults.set(enabled, forKey: "SUEnableAutomaticChecks") }
    }

    func startAutomaticChecks() {
        paused = false
        if didStart { updater?.resetUpdateCycle() }
        else { start() }
        if let configurationError { error = configurationError }
    }

    func stopAutomaticChecks() {
        // 暂停只阻止新的检查，不改写用户的自动检查偏好或取消已确认的安装。
        paused = true
    }

    func check() {
        guard canCheckForUpdates else { return }
        start()
        error = nil
        if let configurationError {
            error = configurationError
            phase = .failed
            return
        }
        guard let updater else { return }
        manualCheckPending = true
        if updater.canCheckForUpdates && !updater.sessionInProgress {
            phase = .checking
            updater.checkForUpdates()
        }
    }

    /// 仅从用户确认“安装并重启”的操作调用；确认覆盖下载、安装与重启。
    func installConfirmedUpdate() {
        guard canInstall, let release else { return }
        confirmedBuild = release.build
        check()
    }

    func cancelDownloadOrCheck() {
        guard let cancel = cancellation else { return }
        cancellation = nil
        installWasConfirmed = false
        confirmedBuild = nil
        manualCheckPending = false
        cancel()
    }

    func retryInstallation() {
        guard installWasConfirmed, let retryTermination else { return }
        phase = .installing
        retryTermination()
    }

    private func finishManualCheck() {
        if manualCheckPending && confirmedBuild == nil { completedManualChecks += 1 }
        manualCheckPending = false
    }

    // MARK: SPUUserDriver — Sparkle 保证在主线程调用。

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: automaticallyChecks, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        phase = .checking
    }

    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
                         reply: @escaping (SPUUserUpdateChoice) -> Void) {
        cancellation = nil
        retryTermination = nil
        installWasConfirmed = false
        informationOnly = appcastItem.isInformationOnlyUpdate
        let notes = appcastItem.itemDescriptionFormat == "markdown"
            ? appcastItem.itemDescription?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        release = Release(version: appcastItem.displayVersionString, build: appcastItem.versionString,
                          pageURL: appcastItem.infoURL ?? Self.releasesURL, isNewer: true,
                          notes: notes?.isEmpty == false ? notes : nil)
        downloadedBytes = 0
        expectedBytes = appcastItem.contentLength
        extractionProgress = 0
        error = nil
        phase = .available
        finishManualCheck()
        let requestedBuild = confirmedBuild
        confirmedBuild = nil
        if informationOnly {
            error = "该版本需要从发布页手动安装。"
            reply(.dismiss)
        } else if requestedBuild == appcastItem.versionString {
            installWasConfirmed = true
            phase = .downloading
            reply(.install)
        } else {
            if requestedBuild != nil { error = "可用版本已变化，请重新确认安装。" }
            // 结束发现会话才能继续每日检查。确认安装时重新检查同一构建，
            // 不让“稍后安装”锁住调度，也不把旧确认用于后来发布的版本。
            reply(.dismiss)
        }
    }

    // 更新说明直接随签名清单返回；结束发现会话后无需继续下载。
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}

    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        self.error = error.localizedDescription
        phase = .failed
        manualCheckPending = false
        confirmedBuild = nil
        showSettings?()
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
        downloadedBytes = 0
        phase = .downloading
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedBytes = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) { downloadedBytes += length }

    func showDownloadDidStartExtractingUpdate() {
        cancellation = nil
        phase = .preparing
    }

    func showExtractionReceivedProgress(_ progress: Double) { extractionProgress = progress }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard installWasConfirmed else {
            // .dismiss 仍可能在退出时安装；.skip 才会取消已准备的安装。
            reply(.skip)
            return
        }
        phase = .installing
        reply(.install)
    }

    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool,
                             retryTerminatingApplication: @escaping () -> Void) {
        phase = .installing
        retryTermination = applicationTerminated ? nil : retryTerminatingApplication
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func dismissUpdateInstallation() {
        cancellation = nil
        retryTermination = nil
        installWasConfirmed = false
        confirmedBuild = nil
        if [.checking, .downloading, .preparing, .installing].contains(phase) {
            phase = release == nil ? .idle : .available
        }
    }

    func showUpdateInFocus() { showSettings?() }

    // MARK: SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? {
        // 其余情况沿用包内 SUFeedURL，便于在独立安装目录验收更新。
        // 仅对 Rosetta 运行的正式 Intel 包改选 Apple Silicon 更新源。
        let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String
        if architecture == "AppleSilicon",
           feed == "https://github.com/sunpm/codex-quota/releases/latest/download/appcast-Intel.xml" {
            return "https://github.com/sunpm/codex-quota/releases/latest/download/appcast-AppleSilicon.xml"
        }
        return nil
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        if paused {
            throw NSError(domain: NSCocoaErrorDomain, code: CocoaError.userCancelled.rawValue,
                          userInfo: [NSLocalizedDescriptionKey: "软件更新检查已暂停。"])
        }
    }

    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool { false }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let error = error as NSError
        let reason = (error.userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber)?.int32Value
        release = nil
        if reason == SPUNoUpdateFoundReason.onLatestVersion.rawValue
            || reason == SPUNoUpdateFoundReason.onNewerThanLatestVersion.rawValue {
            latestStatus = reason == SPUNoUpdateFoundReason.onLatestVersion.rawValue
                ? "已是最新正式版" : "当前版本高于最新正式版"
            phase = .upToDate
            self.error = nil
            finishManualCheck()
            confirmedBuild = nil
        } else {
            phase = .failed
            self.error = error.localizedRecoverySuggestion ?? error.localizedDescription
            manualCheckPending = false
            confirmedBuild = nil
        }
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        guard !paused, let error = error as NSError?,
              !(error.domain == SUSparkleErrorDomain && error.code == Int(SUError.noUpdateError.rawValue)),
              !(error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) else { return }
        self.error = error.localizedDescription
        phase = .failed
        manualCheckPending = false
        confirmedBuild = nil
    }
}
