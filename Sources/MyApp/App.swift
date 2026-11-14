import ActivityKit
import PhotosUI
import SwiftUI
import UIKit

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// 所有尺寸都取屏幕宽度的比例，换机型自动等比缩放。
struct Metrics {
    let width: CGFloat

    init(width: CGFloat) { self.width = width }

    func ratio(_ value: CGFloat) -> CGFloat { width * value }

    /// 图片两侧留白，同时决定文字与开关的左右边界
    var margin: CGFloat { ratio(0.10) }
    var imageSide: CGFloat { ratio(0.80) }
    var titleSize: CGFloat { ratio(0.095) }
    var actionSize: CGFloat { ratio(0.048) }
    var gap: CGFloat { ratio(0.055) }
    var topInset: CGFloat { ratio(0.08) }
    var blockRadius: CGFloat { ratio(0.02) }
}

/// 封面图落盘，杀进程后还在。
enum CoverStore {
    static var url: URL {
        FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("mi.island.cover.jpg")
    }

    static func save(_ data: Data) {
        try? data.write(to: url, options: .atomic)
    }

    static func load() -> Data? {
        try? Data(contentsOf: url)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

struct DesignerView: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("mi.island.title") private var title = "Island"

    @State private var photoItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var editing = false
    @State private var draft = ""
    @State private var image: UIImage?
    @State private var imageBase64 = ""
    @State private var activity: Activity<DesignActivityAttributes>?
    @State private var updateTask: Task<Void, Never>?

    init() {
        if let data = CoverStore.load(), let saved = UIImage(data: data) {
            _image = State(initialValue: saved)
        }
    }

    private var displayTitle: String {
        title.isEmpty ? "Island" : title
    }

    private var state: DesignActivityAttributes.ContentState {
        DesignActivityAttributes.ContentState(
            title: displayTitle,
            imageBase64: imageBase64
        )
    }

    private var running: Bool { activity != nil }

    private var isDark: Bool { colorScheme == .dark }
    private var fg: Color { isDark ? .white : .black }
    private var bg: Color { isDark ? .black : .white }

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(width: geo.size.width)

            content(m)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    backdrop(m).ignoresSafeArea()
                }
        }
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .onAppear {
            restoreThumbnail()
            syncActivity()
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in await loadImage(from: item) }
        }
        .onChange(of: state) { _, newState in
            guard running else { return }
            scheduleUpdate(for: newState)
        }
        .alert("实时活动文本", isPresented: $editing) {
            TextField("Island", text: $draft)
            Button("取消", role: .cancel) {}
            Button("确定") { title = draft }
        } message: {
            Text("清空后自动显示 Island")
        }
    }

    private func content(_ m: Metrics) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: m.gap) {
                cover(m)

                HStack(alignment: .firstTextBaseline, spacing: m.gap) {
                    Button {
                        draft = title
                        editing = true
                    } label: {
                        Text(displayTitle)
                            .font(.system(size: m.titleSize, weight: .black))
                            .foregroundStyle(fg)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button {
                        if running {
                            stop()
                        } else {
                            start()
                        }
                    } label: {
                        Text(running ? "停止" : "启动")
                            .font(.system(size: m.actionSize, weight: .black))
                            .foregroundStyle(fg)
                            .opacity(running ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, m.margin)
    }

    // MARK: - 背景

    /// 模糊封面只淡淡透出来，页面以底色为主。
    @ViewBuilder
    private func backdrop(_ m: Metrics) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: m.ratio(0.16), opaque: true)
                .overlay(Palette.canvas.opacity(0.82))
                .clipped()
                .allowsHitTesting(false)
        } else {
            Palette.canvas
        }
    }

    // MARK: - 图片

    private func cover(_ m: Metrics) -> some View {
        Button {
            showPicker = true
        } label: {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    bg

                    Text("选择图片")
                        .font(.system(size: m.ratio(0.04), weight: .bold))
                        .foregroundStyle(fg)
                }
            }
            .frame(width: m.imageSide, height: m.imageSide)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: m.blockRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: m.blockRadius, style: .continuous)
                    .strokeBorder(fg.opacity(0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            if image != nil {
                Button(role: .destructive) {
                    clearImage()
                } label: {
                    Label("移除封面", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - 图片处理

    @MainActor
    private func loadImage(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let picked = UIImage(data: data) else { return }

        image = picked
        imageBase64 = makeThumbnail(from: picked)?.base64EncodedString() ?? ""

        if let stored = downscale(picked, to: 1600, quality: 0.85) {
            CoverStore.save(stored)
        }
    }

    private func clearImage() {
        image = nil
        imageBase64 = ""
        photoItem = nil
        CoverStore.clear()
    }

    /// 冷启动时把落盘的封面读回来，并补上实时活动要用的缩略图。
    @MainActor
    private func restoreThumbnail() {
        guard let image, imageBase64.isEmpty else { return }
        imageBase64 = makeThumbnail(from: image)?.base64EncodedString() ?? ""
    }

    /// 实时活动状态有 4KB 上限，只能放缩略图：逐步压到 ≤1600 字节。
    private func makeThumbnail(from image: UIImage) -> Data? {
        let sides: [CGFloat] = [112, 96, 80, 64, 48, 40, 32]
        let qualities: [CGFloat] = [0.6, 0.5, 0.4, 0.3]

        var smallest: Data?

        for side in sides {
            for quality in qualities {
                guard let data = downscale(image, to: side, quality: quality) else { continue }
                if smallest == nil || data.count < (smallest?.count ?? Int.max) {
                    smallest = data
                }
                if data.count <= 1600 {
                    return data
                }
            }
        }

        return smallest
    }

    private func downscale(_ image: UIImage, to side: CGFloat, quality: CGFloat) -> Data? {
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return nil }

        let factor = min(side / max(width, height), 1)
        let size = CGSize(
            width: max(1, (width * factor).rounded()),
            height: max(1, (height * factor).rounded())
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }

        return scaled.jpegData(compressionQuality: quality)
    }

    // MARK: - ActivityKit

    /// 只允许存在一个活动：App 重新打开时直接接管已有的那个。
    private func syncActivity() {
        activity = Activity<DesignActivityAttributes>.activities.first
    }

    private func start() {
        guard !running else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let content = state
        Task { @MainActor in
            // 先清掉可能残留的活动，确保全局只有一个
            for old in Activity<DesignActivityAttributes>.activities {
                await old.end(nil, dismissalPolicy: .immediate)
            }

            guard let newActivity = try? Activity.request(
                attributes: DesignActivityAttributes(),
                content: ActivityContent(state: content, staleDate: nil),
                pushType: nil
            ) else { return }

            activity = newActivity
        }
    }

    private func stop() {
        guard let activity else {
            syncActivity()
            return
        }

        Task { @MainActor in
            await activity.end(nil, dismissalPolicy: .immediate)
            updateTask?.cancel()
            self.activity = nil
        }
    }

    /// 运行中改文字或换图，自动同步。
    private func scheduleUpdate(for content: DesignActivityAttributes.ContentState) {
        updateTask?.cancel()
        updateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let activity else { return }
            await activity.update(ActivityContent(state: content, staleDate: nil))
        }
    }
}
