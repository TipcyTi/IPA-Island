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

    var margin: CGFloat { ratio(0.063) }
    var titleSize: CGFloat { ratio(0.155) }
    var fieldHeight: CGFloat { ratio(0.125) }
    var fieldRadius: CGFloat { ratio(0.018) }
    var blockRadius: CGFloat { ratio(0.02) }
    var gap: CGFloat { ratio(0.05) }
    var squareSide: CGFloat { ratio(0.44) }
    var columnGap: CGFloat { ratio(0.068) }
    var buttonGap: CGFloat { ratio(0.034) }
    var bodySize: CGFloat { ratio(0.04) }
    var labelSize: CGFloat { ratio(0.042) }
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
    @AppStorage("mi.island.title") private var title = "Island"

    @State private var photoItem: PhotosPickerItem?
    @State private var showPicker = false
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

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(width: geo.size.width)

            ZStack {
                backdrop(m)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Island")
                        .font(.system(size: m.titleSize, weight: .black))
                        .foregroundStyle(Palette.ink)
                        .shadow(
                            color: .black.opacity(0.22),
                            radius: m.ratio(0.02),
                            x: 0,
                            y: m.ratio(0.008)
                        )

                    Spacer(minLength: 0)

                    field(m)

                    Spacer().frame(height: m.gap)

                    HStack(alignment: .top, spacing: m.columnGap) {
                        cover(m)

                        VStack(spacing: m.buttonGap) {
                            actionButton("启动", m, filled: true) { start() }
                            actionButton("停止", m, filled: false) { stop() }
                        }
                        .frame(
                            width: m.width - m.margin * 2 - m.squareSide - m.columnGap,
                            height: m.squareSide
                        )
                    }

                    Spacer().frame(height: m.ratio(0.10))
                }
                .padding(.horizontal, m.margin)
                .padding(.top, m.ratio(0.10))
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
        .onAppear { restoreThumbnail() }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task { @MainActor in await loadImage(from: item) }
        }
        .onChange(of: state) { _, newState in
            guard running else { return }
            scheduleUpdate(for: newState)
        }
    }

    // MARK: - 背景

    /// 选图后自动高斯模糊、铺满整屏；没图时就是纯底色。
    @ViewBuilder
    private func backdrop(_ m: Metrics) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: m.ratio(0.10))
                .overlay(Palette.canvas.opacity(0.55))
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)
        } else {
            Palette.canvas.ignoresSafeArea()
        }
    }

    // MARK: - 输入框

    private func field(_ m: Metrics) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: m.fieldRadius, style: .continuous)
                .fill(Palette.chip)

            TextField("Island", text: $title)
                .textFieldStyle(.plain)
                .font(.system(size: m.bodySize))
                .foregroundStyle(Palette.ink)
                .padding(.leading, m.ratio(0.038))
                .padding(.trailing, m.ratio(0.045))
        }
        .frame(height: m.fieldHeight)
        .clipShape(RoundedRectangle(cornerRadius: m.fieldRadius, style: .continuous))
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
                    Palette.chip

                    Text("选择图片")
                        .font(.system(size: m.bodySize, weight: .bold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .frame(width: m.squareSide, height: m.squareSide)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: m.blockRadius, style: .continuous))
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

    // MARK: - 按钮

    private func actionButton(
        _ label: String,
        _ m: Metrics,
        filled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: m.labelSize, weight: .bold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .foregroundStyle(filled ? Palette.canvas : Palette.ink)
                .background(
                    RoundedRectangle(cornerRadius: m.blockRadius, style: .continuous)
                        .fill(filled ? Palette.ink : Palette.chip)
                )
        }
        .buttonStyle(.plain)
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

    private func start() {
        guard !running else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let content = state
        Task { @MainActor in
            guard let newActivity = try? Activity.request(
                attributes: DesignActivityAttributes(),
                content: ActivityContent(state: content, staleDate: nil),
                pushType: nil
            ) else { return }
            activity = newActivity
        }
    }

    private func stop() {
        guard let activity else { return }

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
