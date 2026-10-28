// Release-note rendering adapted from nanvon/cc-bar (MIT), Main/AppUpdateWindow.swift.
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
import SwiftUI

struct AppUpdateView: View {
    @ObservedObject var model: AppUpdateModel
    @State private var showsNotes = true

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
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Button(model.checking ? "正在检查…" : "检查更新") { Task { await model.check() } }
                        .disabled(model.checking || (model.retryAt.map { $0 > context.date } ?? false))
                }
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle").fixedSize(horizontal: false, vertical: true)
                if let retryAt = model.retryAt, retryAt > Date() {
                    Text("可重试时间：\(retryAt.formatted(date: .omitted, time: .standard))")
                        .font(PanelTypography.detail).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            if let release = model.release {
                HStack {
                    Text(release.status).fontWeight(.medium)
                    Spacer()
                    if release.isNewer, let url = release.downloadURL {
                        Link("下载 \(model.architecture) 版", destination: url).buttonStyle(.borderedProminent)
                    }
                }
                if release.isNewer, release.downloadURL == nil {
                    Text("该版本暂未提供 \(model.architecture) 安装包，请到发布页查看。")
                        .foregroundStyle(.secondary)
                }
                DisclosureGroup("\(release.version) 更新说明", isExpanded: $showsNotes) {
                    ScrollView {
                        ReleaseNotesView(markdown: release.notes.isEmpty ? "此版本未提供更新说明。" : release.notes)
                            .padding(.vertical, 8).padding(.trailing, 12)
                    }.frame(maxHeight: 240)
                }
            }
            Link("在 GitHub 查看发布页", destination: model.release?.pageURL ?? AppUpdateModel.releasesURL)
                .font(PanelTypography.detail)
        }.padding(16).panelCard()
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
