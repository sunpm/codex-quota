// Worktree metadata resolution adapted from nanvon/cc-bar (MIT),
// Core/Usage/ProjectWorktreeResolver.swift at 530ef49.
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
import Foundation

enum ProjectWorktreeResolver {
    /// 只认仍存在的工作目录及 Git 元数据；无法确认时由调用方保留原始路径。
    static func mainProjectPath(for path: String) -> String? {
        guard path.hasPrefix("/") else { return nil }
        var directory = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard isDirectory(directory) else { return nil }
        let manager = FileManager.default

        while true {
            guard manager.isReadableFile(atPath: directory.path) else { return nil }
            let dotGit = directory.appendingPathComponent(".git")
            var markerIsDirectory: ObjCBool = false
            if manager.fileExists(atPath: dotGit.path, isDirectory: &markerIsDirectory) {
                let gitDirectory: URL
                if markerIsDirectory.boolValue {
                    gitDirectory = dotGit.resolvingSymlinksInPath().standardizedFileURL
                } else {
                    guard let marker = readSmallText(dotGit), marker.hasPrefix("gitdir:") else { return nil }
                    let path = marker.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !path.isEmpty else { return nil }
                    gitDirectory = resolve(path, relativeTo: directory)
                }
                guard manager.isReadableFile(atPath: gitDirectory.appendingPathComponent("HEAD").path) else { return nil }
                let commonFile = gitDirectory.appendingPathComponent("commondir")
                if manager.fileExists(atPath: commonFile.path) {
                    guard let commonPath = readSmallText(commonFile), !commonPath.isEmpty else { return nil }
                    let common = resolve(commonPath, relativeTo: gitDirectory)
                    // 常规主仓库的公共目录是 .git；bare / 分离的 Git 目录不猜测主工作区。
                    guard common.lastPathComponent == ".git", isDirectory(common.appendingPathComponent("objects")),
                          manager.isReadableFile(atPath: common.appendingPathComponent("HEAD").path) else { return nil }
                    return common.deletingLastPathComponent().path
                }
                // 普通仓库、子模块及 separate-git-dir 都以自己的工作区为项目。
                // 遇到 .git 即停止向上查找，避免把子仓库并入外层仓库。
                return isDirectory(gitDirectory.appendingPathComponent("objects")) ? directory.path : nil
            }
            let parent = directory.deletingLastPathComponent()
            guard parent.path != directory.path else { return nil }
            directory = parent
        }
    }

    private static func resolve(_ path: String, relativeTo directory: URL) -> URL {
        let url = path.hasPrefix("/") ? URL(fileURLWithPath: path) : directory.appendingPathComponent(path)
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private static func readSmallText(_ url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, let size = values.fileSize, size <= 4096,
              let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
