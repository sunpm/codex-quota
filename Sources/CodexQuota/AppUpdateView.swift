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
                if model.canInstall {
                    Button("下载并安装…") { confirmsInstallation = true }
                } else if model.canCancel, !model.checking {
                    Button("取消", action: model.cancelDownloadOrCheck)
                } else if model.canRetryInstallation {
                    Button("重试安装", action: model.retryInstallation)
                }
                if model.checking, model.canCancel {
                    Button("取消检查", action: model.cancelDownloadOrCheck)
                } else {
                    Button(model.checking ? "正在检查…" : showsCheckCompletion ? "检查完成" : "检查更新") {
                        model.check()
                    }
                        .disabled(!model.canCheckForUpdates || showsCheckCompletion)
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
            }
            HStack(alignment: .firstTextBaseline) {
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .lineLimit(1).help(error)
                } else if let status = model.status {
                    Text(status).fontWeight(.medium).lineLimit(1).help(status)
                }
                Spacer(minLength: 12)
                Link("在 GitHub 查看发布页", destination: model.release?.pageURL ?? AppUpdateModel.releasesURL)
                    .buttonStyle(.link).fixedSize()
            }.font(PanelTypography.detail).frame(height: 20)
            if let release = model.release {
                if let notes = release.notes {
                    ViewThatFits(in: .vertical) {
                        ReleaseNotesView(markdown: notes).fixedSize(horizontal: false, vertical: true)
                        ScrollView {
                            ReleaseNotesView(markdown: notes).padding(.trailing, 12)
                        }
                    }.frame(maxHeight: 220).accessibilityLabel("更新说明")
                } else {
                    Text("暂无更新说明").font(PanelTypography.detail).foregroundStyle(.secondary)
                }
            }
            Divider()
            HStack {
                Text("自动检查更新")
                Spacer()
                Toggle("自动检查更新", isOn: Binding(get: { model.automaticallyChecks }, set: { model.setAutomaticallyChecks($0) })).labelsHidden()
            }.toggleStyle(.switch).controlSize(.small)
        }.padding(16).panelCard()
            .alert("安装 \(model.release?.version ?? "更新")？", isPresented: $confirmsInstallation) {
                Button("取消", role: .cancel) {}
                Button("安装并重启", action: model.installConfirmedUpdate)
                    .keyboardShortcut(.defaultAction)
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
                Button("完成") { dismiss() }
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
