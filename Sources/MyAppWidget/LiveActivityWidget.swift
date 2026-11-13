import ActivityKit
import SwiftUI
import UIKit
import WidgetKit

private func decode(_ base64: String) -> UIImage? {
    guard !base64.isEmpty, let data = Data(base64Encoded: base64) else { return nil }
    return UIImage(data: data)
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

/// 锁屏：有图 → 左图右文；无图 → 只有一行文字。
struct LockScreenView: View {
    let context: ActivityViewContext<DesignActivityAttributes>

    private var image: UIImage? { decode(context.state.imageBase64) }

    var body: some View {
        Group {
            if let image {
                HStack(alignment: .center, spacing: 14) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))

                    Text(context.state.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(context.state.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
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
            let coverSide: CGFloat = 36
            let regionWidth: CGFloat = 46

            return DynamicIsland {
                // 左边：正方形小图，宽度刚好放下
                DynamicIslandExpandedRegion(.leading) {
                    Group {
                        if let image {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: coverSide, height: coverSide)
                                .clipShape(
                                    RoundedRectangle(cornerRadius: coverSide * 0.28, style: .continuous)
                                )
                        } else {
                            RoundedRectangle(cornerRadius: coverSide * 0.28, style: .continuous)
                                .fill(.white.opacity(0.12))
                                .frame(width: coverSide, height: coverSide)
                        }
                    }
                    .frame(width: regionWidth)
                }

                // 右边：与左边等宽，文字在框内滚动
                DynamicIslandExpandedRegion(.trailing) {
                    MarqueeText(
                        text: context.state.title,
                        font: .headline,
                        color: .primary
                    )
                    .frame(width: regionWidth, height: 20)
                }
            } compactLeading: {
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
            } compactTrailing: {
                MarqueeText(
                    text: context.state.title,
                    font: .caption2,
                    color: .primary
                )
                .frame(width: 52, height: 14)
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
