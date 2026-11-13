import LocalAuthentication
import SwiftUI

/// 冷启动先验证身份：Face ID 优先，失败回落到设备密码。
/// 布局照 PocketServer 的弹窗：居中卡片 + 底部左右两个半宽按钮。
struct RootView: View {
    @State private var unlocked = false
    @State private var busy = false
    @State private var message = ""

    var body: some View {
        ZStack {
            if unlocked {
                DesignerView()
            } else {
                lockScreen
            }
        }
        .onAppear(perform: authenticate)
    }

    private var lockScreen: some View {
        GeometryReader { geo in
            let m = Metrics(width: geo.size.width)

            ZStack {
                Palette.canvas.ignoresSafeArea()
                dialog(m)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func dialog(_ m: Metrics) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text(message.isEmpty ? "需要验证身份" : message)
                .font(.system(size: m.size(15), weight: .medium))
                .foregroundStyle(Palette.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, m.size(18))

            Spacer(minLength: 0)

            HStack(spacing: m.size(0.5)) {
                dialogButton("取消", m) {
                    message = "已取消，点 Face ID 重新验证"
                }

                dialogButton("Face ID", m) {
                    authenticate()
                }
            }
            .frame(height: m.size(44))
        }
        .frame(width: m.size(260), height: m.size(200))
        .background(
            RoundedRectangle(cornerRadius: m.size(16), style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: m.size(16), style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: m.size(16), style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: m.size(18), x: 0, y: m.size(8))
        .opacity(busy ? 0.8 : 1)
    }

    private func dialogButton(_ label: String, _ m: Metrics, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: m.size(15), weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(Palette.ink)
                .background(Palette.chip)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func authenticate() {
        guard !busy else { return }

        busy = true
        message = ""

        let context = LAContext()
        context.localizedFallbackTitle = "使用设备密码"
        context.localizedCancelTitle = "取消"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            busy = false
            message = "这台设备没有设置面容 ID 或锁屏密码"
            return
        }

        context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: "解锁 Mi Island"
        ) { success, _ in
            DispatchQueue.main.async {
                busy = false
                if success {
                    unlocked = true
                } else {
                    message = "验证未通过，点 Face ID 重试"
                }
            }
        }
    }
}
