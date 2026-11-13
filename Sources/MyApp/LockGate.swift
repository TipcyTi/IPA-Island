import LocalAuthentication
import SwiftUI

/// 冷启动先验证：屏幕正中一个字标，点它唤起 Face ID，失败回落到设备密码。
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

                VStack(spacing: m.ratio(0.03)) {
                    Button {
                        authenticate()
                    } label: {
                        Text("Face ID")
                            .font(.system(size: m.ratio(0.16), weight: .black))
                            .foregroundStyle(Palette.ink)
                            .shadow(
                                color: .black.opacity(0.22),
                                radius: m.ratio(0.02),
                                x: 0,
                                y: m.ratio(0.008)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)

                    if !message.isEmpty {
                        Text(message)
                            .font(.system(size: m.ratio(0.036)))
                            .foregroundStyle(Palette.caption)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, m.margin)
                    }
                }
                .opacity(busy ? 0.6 : 1)
            }
        }
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
                    message = "验证未通过，点一下重试"
                }
            }
        }
    }
}
