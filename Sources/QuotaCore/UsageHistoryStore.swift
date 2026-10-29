import Foundation

/// 只保存可重新计价的用量字段；不保存日志正文、凭据或计算后的费用。
struct UsageHistory: Codable, Equatable {
    var version = 1
    var records: [String: UsageRecord] = [:]
    var projectRoots: [String: String] = [:]
    /// 保留旧版服务的历史元数据；当前只采集 Codex。
    var antigravityModified: [String: Date]?
}

struct UsageHistoryStore {
    let url: URL

    init(url: URL? = nil) {
        // 产品更名后继续使用原目录，保留已采集历史。
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexQuotaDock/usage-history.json")
    }

    func load() throws -> UsageHistory {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return UsageHistory()
        }
        let history = try JSONDecoder().decode(UsageHistory.self, from: data)
        guard history.version == 1 else { throw HistoryError.unsupportedVersion }
        return history
    }

    func save(_ history: UsageHistory) throws {
        let data = try JSONEncoder().encode(history)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // ponytail: 有变化时整份原子替换；历史大到影响刷新时再采用数据库增量写入。
        try data.write(to: url, options: .atomic)
    }

    func clear() throws {
        var history = try load()
        history.records = history.records.filter { $0.value.service != .codex }
        let projects = Set(history.records.values.map(\.project))
        history.projectRoots = history.projectRoots.filter { projects.contains($0.key) }
        if !history.records.isEmpty {
            try save(history)
            return
        }
        do { try FileManager.default.removeItem(at: url) }
        catch CocoaError.fileNoSuchFile { return }
    }

    private enum HistoryError: Error { case unsupportedVersion }
}
