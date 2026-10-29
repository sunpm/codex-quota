import SwiftUI
import QuotaCore

struct ResetAnnouncementView: View {
    @ObservedObject var model: ResetAnnouncementMonitor

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Codex 重置动态").font(.headline)
                    if model.refreshing { ProgressView().controlSize(.mini) }
                    Spacer()
                    Link(destination: URL(string: "https://aihot.news/codex-reset")!) {
                        Label("AIHOT", systemImage: "arrow.up.right")
                    }.buttonStyle(.link).font(PanelTypography.detail)
                }
                if let feed = model.feed {
                    if feed.events.isEmpty {
                        Text("暂无重置动态").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    ForEach(Array(feed.events.sorted { $0.updatedAt > $1.updatedAt }.prefix(3))) { event in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(event.label).font(.body.weight(.semibold))
                                Spacer(minLength: 8)
                                Text(event.statusText(at: context.date))
                                    .font(PanelTypography.detail).foregroundStyle(.secondary)
                            }
                            if let post = event.latestPost {
                                let isToday = Calendar.current.isDate(post.publishedAt, inSameDayAs: context.date)
                                Text(post.text).font(.body).lineLimit(3).help(post.text)
                                HStack {
                                    Text("原帖 · \(post.publishedAt.formatted(.dateTime.month().day().hour().minute()))")
                                        .fontWeight(isToday ? .semibold : .regular)
                                        .foregroundStyle(isToday ? .primary : .secondary).monospacedDigit()
                                    Spacer()
                                    Link("查看原帖", destination: post.url)
                                        .buttonStyle(.link)
                                }.font(PanelTypography.detail)
                            }
                            if event.status == .announced {
                                if let schedule = event.schedule {
                                    Text("预告 · \(schedule.label)").font(PanelTypography.detail).foregroundStyle(.secondary)
                                } else if let estimate = event.estimate {
                                    Text("AIHOT 估计 · \(estimate.label)").font(PanelTypography.detail).foregroundStyle(.secondary)
                                }
                            }
                            if let scope = event.presentation?.scopeLabel, !scope.isEmpty {
                                Text("适用范围 · \(scope)").font(PanelTypography.detail).foregroundStyle(.secondary)
                            }
                        }
                        Divider()
                    }
                    if let updated = feed.sourceUpdatedAt {
                        Text("来源核实 · \(updated.formatted(.dateTime.month().day().hour().minute()))")
                            .font(PanelTypography.detail).foregroundStyle(.secondary).monospacedDigit()
                    }
                } else {
                    Text(model.refreshing ? "正在读取…" : "等待首次读取")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if let error = model.errorMessage ?? model.feed?.sourceStatus(at: context.date) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(PanelTypography.detail).foregroundStyle(.primary)
                }
            }.padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
