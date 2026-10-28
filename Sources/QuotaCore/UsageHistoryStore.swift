import Foundation

/// 只保存可重新计价的用量字段；不保存日志正文、凭据或计算后的费用。
struct UsageHistory: Codable, Equatable {
    var version = 1
    var records: [String: UsageRecord] = [:]
    var projectRoots: [String: String] = [:]
    /// 可选字段兼容已有快照，避免较新 transcript 被清理后由旧副本回退计数。
    var antigravityModified: [String: Date]?
}

struct UsageHistoryStore {
    let url: URL

    init(url: URL? = nil) {
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
        do { try FileManager.default.removeItem(at: url) }
        catch CocoaError.fileNoSuchFile { return }
    }

    private enum HistoryError: Error { case unsupportedVersion }
}
