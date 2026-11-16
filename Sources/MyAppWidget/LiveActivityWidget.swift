import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

private func decode(_ base64: String) -> UIImage? {
    guard !base64.isEmpty, let data = Data(base64Encoded: base64) else { return nil }
    return UIImage(data: data)
}

private func symbolName(for raw: String?) -> String {
    let name = raw ?? ""
    return name.isEmpty ? "sparkles" : name
}

/// 只走一行：放得下就静态显示，放不下就横向来回滚动。
struct MarqueeText: View {
    let text: String
    let font: Font
    let color: Color

    @State private var contentWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @State private var started = false

    var body: some View {
        GeometryReader { box in
            Text(text)
                .font(font)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .background(
                    GeometryReader { proxy in
                        Color.clear.onAppear { contentWidth = proxy.size.width }
                    }
                )
                .offset(x: offset)
                .onAppear {
                    guard !started else { return }
                    started = true
                    DispatchQueue.main.async {
                        let overflow = contentWidth - box.size.width
                        guard overflow > 1 else { return }
                        withAnimation(
                            .linear(duration: Double(overflow) / 24)
                                .repeatForever(autoreverses: true)
                        ) {
                            offset = -overflow
                        }
                    }
                }
        }
        .clipped()
    }
}

/// 锁屏：有图 → 左图 + 中间文字 + 右侧同尺寸图标；无图 → 文字 + 右侧图标。
struct LockScreenView: View {
    let context: ActivityViewContext<DesignActivityAttributes>

    private var image: UIImage? { decode(context.state.imageBase64) }
    private var symbol: String { symbolName(for: context.state.symbol) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 54, height: 54)
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
            }

            Text(context.state.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 54, height: 54)
                .foregroundStyle(.primary)
        }
        .padding(16)
    }
}

struct DesignActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DesignActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            let image = decode(context.state.imageBase64)
            let coverSide: CGFloat = 50

            return DynamicIsland {
                // 展开态：左列放封面，右列放标题，各自在列内水平 + 垂直居中
                DynamicIslandExpandedRegion(.leading) {
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: coverSide, height: coverSide)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: coverSide * 0.30, style: .continuous)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: coverSide * 0.30, style: .continuous)
                                .fill(.white.opacity(0.10))
                                .frame(width: coverSide, height: coverSide)
                                .overlay {
                                    Image(systemName: "photo")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(.secondary)
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
                .contentMargins(.all, 14)

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                        .padding(.trailing, 8)
                }
                .contentMargins(.all, 14)
            } compactLeading: {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 22, height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    Circle()
                        .fill(.primary)
                        .frame(width: 6, height: 6)
                }
            } compactTrailing: {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.14))

                    Image(systemName: symbolName(for: context.state.symbol))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .frame(width: 22, height: 22)
            } minimal: {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 20, height: 20)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else {
                    Circle()
                        .fill(.primary)
                        .frame(width: 6, height: 6)
                }
            }
        }
    }
}

@main
struct MyAppWidgetBundle: WidgetBundle {
    var body: some Widget {
        DesignActivityWidget()
    }
}
