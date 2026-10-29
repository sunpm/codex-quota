// Release-note rendering adapted from nanvon/cc-bar (MIT), Main/AppUpdateWindow.swift.
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
import SwiftUI

struct AppUpdateView: View {
    @ObservedObject var model: AppUpdateModel
    @State private var showsCheckCompletion = false
    @State private var confirmsInstallation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("软件更新").font(.headline)
                    Text("当前版本 \(model.currentVersion)").font(PanelTypography.detail)
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if model.checking { ProgressView().controlSize(.small).accessibilityLabel("正在检查更新") }
                Button(model.checking ? "正在检查…" : showsCheckCompletion ? "检查完成" : "检查更新") {
                    model.check()
                }
                    .disabled(!model.canCheckForUpdates || showsCheckCompletion)
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle").fixedSize(horizontal: false, vertical: true)
            }
            if let status = model.status {
                HStack {
                    Text(status).fontWeight(.medium)
                    Spacer()
                    if model.canInstall {
                        Button("下载并安装…") { confirmsInstallation = true }
                            .buttonStyle(PanelButtonStyle(prominent: true))
                    } else if model.canCancel {
                        Button("取消", action: model.cancelDownloadOrCheck)
                    } else if model.canRetryInstallation {
                        Button("重试安装", action: model.retryInstallation)
                    }
                }
            }
            if model.phase == .downloading {
                ProgressView(value: model.downloadProgress).accessibilityLabel("更新下载进度")
                Text(ByteCountFormatter.string(fromByteCount: Int64(clamping: model.downloadedBytes), countStyle: .file))
                    .font(PanelTypography.detail).foregroundStyle(.secondary).monospacedDigit()
            } else if model.phase == .preparing {
                ProgressView(value: model.extractionProgress).accessibilityLabel("更新准备进度")
            } else if model.phase == .installing {
                ProgressView().controlSize(.small).accessibilityLabel("正在安装并重启")
            } else if model.checking, model.canCancel {
                HStack {
                    Spacer()
                    Button("取消", action: model.cancelDownloadOrCheck)
                }
            }
            Link("在 GitHub 查看发布页", destination: model.release?.pageURL ?? AppUpdateModel.releasesURL)
                .buttonStyle(.link).font(PanelTypography.detail)
        }.padding(16).panelCard()
            .alert("安装 \(model.release?.version ?? "更新")？", isPresented: $confirmsInstallation) {
                Button("取消", role: .cancel) {}
                Button("安装并重启", action: model.installConfirmedUpdate)
            } message: {
                Text("下载完成后将退出并重新打开 Codex Quota。")
            }
            .onChange(of: model.completedManualChecks) { _ in showsCheckCompletion = true }
            .task(id: showsCheckCompletion) {
                guard showsCheckCompletion else { return }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                showsCheckCompletion = false
            }
    }
}

struct InstalledReleaseNotesView: View {
    let version: String
    let markdown: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("\(version) 更新说明").font(.title2.weight(.semibold))
            ScrollView {
                ReleaseNotesView(markdown: markdown).padding(.trailing, 12)
            }
            HStack {
                Spacer()
                Button("知道了") { dismiss() }
                    .buttonStyle(PanelButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 560, height: 440)
    }
}

private struct ReleaseNotesView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(markdown.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                let text = line.trimmingCharacters(in: .whitespaces)
                if !text.isEmpty, !text.hasPrefix("<!--") {
                    if text.hasPrefix("### ") {
                        inline(String(text.dropFirst(4))).font(.headline).padding(.top, 4)
                    } else if text.hasPrefix("## ") || text.hasPrefix("# ") {
                        inline(String(text.drop(while: { $0 == "#" || $0 == " " })))
                            .font(.title3.weight(.semibold)).padding(.top, 8)
                    } else if text.hasPrefix("- ") || text.hasPrefix("* ") {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("•").foregroundStyle(.secondary)
                            inline(String(text.dropFirst(2)))
                        }
                    } else {
                        inline(text)
                    }
                }
            }
        }.font(.callout).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func inline(_ text: String) -> Text {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
             ?? AttributedString(text))
    }
}
