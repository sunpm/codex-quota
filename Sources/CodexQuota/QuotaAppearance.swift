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
        if #available(macOS 26, *), prominent {
            Button(configuration).buttonStyle(.glassProminent)
        } else if prominent {
            Button(configuration).buttonStyle(.borderedProminent)
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}

struct PanelSelectionIndicator<Value: Hashable>: View {
    let selection: Value
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.accentColor)
            .matchedGeometryEffect(id: selection, in: namespace, isSource: false)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selection)
            .allowsHitTesting(false)
    }
}

struct PanelSelectionLabel<Value: Hashable>: ViewModifier {
    let selection: Value
    let namespace: Namespace.ID

    func body(content: Content) -> some View {
        content.fontWeight(.regular)
            .mask {
                Rectangle().overlay {
                    PanelSelectionIndicator(selection: selection, namespace: namespace)
                        .blendMode(.destinationOut)
                }.compositingGroup()
            }
            .overlay {
                // 字色和字重都由滑块覆盖范围决定，不在点击时提前切换。
                Color.white.mask(content.fontWeight(.semibold))
                    .mask { PanelSelectionIndicator(selection: selection, namespace: namespace) }
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
    }
}

struct PanelSegmentedPicker<Value: Hashable>: View {
    let title: String
    let options: [Value]
    @Binding var selection: Value
    let optionTitle: KeyPath<Value, String>
    @Namespace private var indicator
    @FocusState private var focusedOption: Value?

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                Button { selection = option } label: {
                    Text(option[keyPath: optionTitle])
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .modifier(PanelSelectionLabel(selection: selection, namespace: indicator))
                        .contentShape(Rectangle())
                }
                .matchedGeometryEffect(id: option, in: indicator)
                .focused($focusedOption, equals: option)
                .accessibilityAddTraits(selection == option ? .isSelected : [])
            }
        }
        .background {
            PanelSelectionIndicator(selection: selection, namespace: indicator)
        }
        .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(.primary)
        .padding(3)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain).accessibilityLabel(title)
        .onMoveCommand { direction in
            guard let index = options.firstIndex(of: focusedOption ?? selection) else { return }
            let next: Int
            switch direction {
            case .left: next = max(0, index - 1)
            case .right: next = min(options.count - 1, index + 1)
            default: return
            }
            selection = options[next]
            focusedOption = selection
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
