// Adapted from nanvon/cc-bar (MIT), Main/DesignSystem.swift.
// Copyright (c) 2026 nanvon. See Resources/ThirdPartyNotices/cc-bar-LICENSE.txt.
import AppKit
import SwiftUI
import QuotaCore

enum PanelTypography {
    // macOS 的 caption 默认偏小；时间、说明与表格明细统一使用可读的 12pt。
    static let detail = Font.system(size: 12)
}

struct PanelButtonStyle: PrimitiveButtonStyle {
    var prominent = false

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                Button(configuration).buttonStyle(.glassProminent)
            } else {
                Button(configuration).buttonStyle(.glass)
            }
        } else if prominent {
            Button(configuration).buttonStyle(.borderedProminent)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}

func quotaColor(remaining: Double?) -> Color {
    guard let remaining else { return .secondary }
    let light: (CGFloat, CGFloat, CGFloat)
    let dark: (CGFloat, CGFloat, CGFloat)
    if remaining <= 0 {
        light = (209, 36, 58); dark = (255, 122, 144)
    } else if remaining < 20 {
        light = (199, 83, 0); dark = (255, 161, 95)
    } else {
        light = (108, 108, 112); dark = (152, 152, 157)
    }
    return Color(nsColor: NSColor(name: nil) { appearance in
        let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        return NSColor(calibratedRed: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255, alpha: 1)
    })
}

struct QuotaProgressBar: View {
    let remaining: Double
    let tint: Color
    var height: CGFloat = 7

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                Capsule().fill(tint)
                    .frame(width: geometry.size.width * max(0, min(1, remaining / 100)))
            }
        }.frame(height: height)
    }
}

struct CodexServiceTile: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6).fill(.white)
            .frame(width: 22, height: 22)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            .overlay {
                if let logo = CodexLogo.image {
                    Image(nsImage: logo).resizable().renderingMode(.template)
                        .foregroundStyle(.black).frame(width: 14, height: 14)
                } else {
                    Image(systemName: "terminal").font(.system(size: 12)).foregroundStyle(.black)
                }
            }
    }
}
