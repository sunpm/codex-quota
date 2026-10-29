import Foundation
import Combine
import Darwin

@MainActor
final class AppUpdateModel: ObservableObject {
    static let releasesURL = URL(string: "https://github.com/sunpm/codex-quota-dock/releases/latest")!

    struct Release {
        let version: String
        let notes: String
        let pageURL: URL
        let downloadURL: URL?
        let isNewer: Bool
        let status: String
    }

    let currentVersion: String
    let architecture: String
    @Published private(set) var checking = false
    @Published private(set) var release: Release?
    @Published private(set) var error: String?
    @Published private(set) var retryAt: Date?
    @Published private(set) var automaticallyChecks: Bool
    private let defaults: UserDefaults
    private var automaticChecksTask: Task<Void, Never>?
    private var lastCheckAttempt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticallyChecks = defaults.object(forKey: "updates.automaticallyChecks") as? Bool ?? true
        currentVersion = Bundle.main.object(forInfoDictionaryKey: "ReleaseVersion") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "未知"
        #if arch(arm64)
        architecture = "Apple Silicon"
        #else
        // Intel 应用经 Rosetta 运行时，仍下载这台 Mac 的原生 Apple Silicon 版本。
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let result = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        architecture = result == 0 && translated == 1 ? "Apple Silicon" : "Intel"
        #endif
    }

    func setAutomaticallyChecks(_ enabled: Bool) {
        automaticallyChecks = enabled
        defaults.set(enabled, forKey: "updates.automaticallyChecks")
        if enabled { startAutomaticChecks() }
        else { stopAutomaticChecks() }
    }

    func startAutomaticChecks() {
        guard automaticallyChecks, automaticChecksTask == nil else { return }
        automaticChecksTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.check(automatically: true)
                // 每小时判断是否到期；启动后约每 24 小时查询一次，手动查询也计入间隔。
                try? await Task.sleep(nanoseconds: 3_600_000_000_000)
            }
        }
    }

    func stopAutomaticChecks() {
        automaticChecksTask?.cancel()
        automaticChecksTask = nil
    }

    func check(automatically: Bool = false) async {
        guard !Task.isCancelled, !checking, retryAt.map({ $0 <= Date() }) ?? true else { return }
        if automatically {
            guard automaticallyChecks,
                  lastCheckAttempt.map({ Date().timeIntervalSince($0) >= 86_400 }) ?? true else { return }
        }
        checking = true
        error = nil
        retryAt = nil
        defer {
            checking = false
            // 失败也按正常间隔重试；睡眠或关闭开关造成的取消不推迟下次检查。
            if !Task.isCancelled { lastCheckAttempt = Date() }
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/sunpm/codex-quota-dock/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CodexQuotaDock", forHTTPHeaderField: "User-Agent")

        do {
            let (data, rawResponse) = try await session.data(for: request)
            guard !Task.isCancelled else { return }
            guard let response = rawResponse as? HTTPURLResponse else {
                error = "GitHub 未返回有效响应，请重试或打开发布页。"
                return
            }
            if response.statusCode == 429 || (response.statusCode == 403 &&
                (response.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" || response.value(forHTTPHeaderField: "Retry-After") != nil)) {
                let rawRetry = response.value(forHTTPHeaderField: "Retry-After") ?? ""
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
                let delay = Double(rawRetry) ?? formatter.date(from: rawRetry)?.timeIntervalSinceNow ?? 60
                let reset = Double(response.value(forHTTPHeaderField: "X-RateLimit-Reset") ?? "")
                    .map { $0 - Date().timeIntervalSince1970 } ?? 0
                retryAt = Date().addingTimeInterval(max(60, delay.isFinite ? delay : 60, reset.isFinite ? reset : 0))
                error = "GitHub 暂时限制查询，请稍后重试或打开发布页。"
                return
            }
            guard response.statusCode == 200 else {
                error = response.statusCode == 404 ? "暂未找到正式版本，可打开发布页查看。"
                    : "检查更新失败（HTTP \(response.statusCode)），请重试或打开发布页。"
                return
            }
            let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
            guard !payload.draft, !payload.prerelease,
                  let latest = Version(payload.tagName), !latest.isPrerelease else {
                error = "GitHub 返回的正式版本信息无效，请打开发布页查看。"
                return
            }
            guard let current = Version(currentVersion) else {
                error = "无法识别当前应用版本，请打开发布页核对。"
                return
            }
            let comparison = latest.numbers.lexicographicallyPrecedes(current.numbers) ? -1
                : current.numbers.lexicographicallyPrecedes(latest.numbers) ? 1 : 0
            let isNewer = comparison > 0 || (comparison == 0 && current.isPrerelease)
            let platform = architecture == "Apple Silicon" ? "AppleSilicon" : "Intel"
            let filename = "CodexQuotaDock-\(payload.tagName)-macOS-\(platform).dmg"
            let asset = payload.assets.first { $0.name == filename && $0.state == "uploaded" }
            // 只提供当前 release 中确实存在的附件，不回退到另一种架构。
            let downloadURL = asset.map { _ in
                URL(string: "https://github.com/sunpm/codex-quota-dock/releases/download/\(payload.tagName)/\(filename)")!
            }
            release = Release(version: latest.text, notes: payload.body ?? "",
                              pageURL: URL(string: "https://github.com/sunpm/codex-quota-dock/releases/tag/\(payload.tagName)")!,
                              downloadURL: downloadURL, isNewer: isNewer,
                              status: isNewer ? "发现新版本 \(latest.text)" : comparison == 0
                                ? "已是最新正式版" : "当前版本高于最新正式版 \(latest.text)")
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error is DecodingError ? "无法读取 GitHub 版本信息，请重试或打开发布页。"
                : "无法连接 GitHub，请检查网络后重试，或打开发布页。"
        }
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let state: String
        }
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body, draft, prerelease, assets
        }
    }

    private struct Version {
        let text: String
        let numbers: [Int]
        let isPrerelease: Bool

        init?(_ raw: String) {
            let text = raw.hasPrefix("v") ? String(raw.dropFirst()) : raw
            guard text.range(of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$"#,
                             options: .regularExpression) != nil else { return nil }
            let parts = text.split(separator: "-", maxSplits: 1)
            let numbers = parts[0].split(separator: ".").compactMap { Int($0) }
            guard numbers.count == 3 else { return nil }
            self.text = text
            self.numbers = numbers
            isPrerelease = parts.count == 2
        }
    }
}
