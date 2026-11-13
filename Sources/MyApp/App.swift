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

/// 所有尺寸都按屏幕宽度等比缩放，不使用固定 px。
struct Metrics {
    let scale: CGFloat

    init(width: CGFloat) {
        let base: CGFloat = 390
        scale = min(max(width / base, 0.8), 1.3)
    }

    func size(_ value: CGFloat) -> CGFloat { value * scale }

    var pagePadding: CGFloat { size(16) }
    var rowSpacing: CGFloat { size(16) }
    var thumb: CGFloat { size(64) }
    var radius: CGFloat { size(8) }
    var chipText: CGFloat { size(14) }
    var bodyText: CGFloat { size(16) }
    var metaText: CGFloat { size(14) }
}

struct DesignerView: View {
    @State private var title = "进行中"
    @State private var photoItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var image: UIImage?
    @State private var imageBase64 = ""
    @State private var activity: Activity<DesignActivityAttributes>?
    @State private var updateTask: Task<Void, Never>?

    private var state: DesignActivityAttributes.ContentState {
        DesignActivityAttributes.ContentState(
            title: title,
            imageBase64: imageBase64
        )
    }

    private var running: Bool { activity != nil }

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(width: geo.size.width)

            ZStack {
                backdrop(m)

                VStack(spacing: 0) {
                    topBar(m)
                    list(m)
                    bottomBar(m)
                }
            }
        }
        .photosPicker(isPresented: $showPicker, selection: $photoItem, matching: .images)
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

    @ViewBuilder
    private func backdrop(_ m: Metrics) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .blur(radius: m.size(40))
                .overlay(Palette.canvas.opacity(0.58))
                .clipped()
                .ignoresSafeArea()
        } else {
            Palette.canvas.ignoresSafeArea()
        }
    }

    // MARK: - 顶栏

    private func topBar(_ m: Metrics) -> some View {
        HStack(spacing: m.size(6)) {
            chip("Mi Island", m)

            Text("/")
                .font(.system(size: m.metaText))
                .foregroundStyle(Palette.caption)

            chip("实时活动", m)

            Spacer(minLength: m.size(8))

            Menu {
                Button {
                    showPicker = true
                } label: {
                    Label(image == nil ? "选择封面" : "更换封面", systemImage: "photo")
                }

                if image != nil {
                    Button(role: .destructive) {
                        clearImage()
                    } label: {
                        Label("移除封面", systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: m.size(13), weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .frame(width: m.size(30), height: m.size(30))
                    .overlay(
                        Circle().strokeBorder(Palette.ink, lineWidth: m.size(1.5))
                    )
            }
        }
        .padding(m.pagePadding)
    }

    private func chip(_ text: String, _ m: Metrics) -> some View {
        Text(text)
            .font(.system(size: m.chipText, weight: .semibold))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, m.size(8))
            .padding(.vertical, m.size(8))
            .background(
                RoundedRectangle(cornerRadius: m.radius, style: .continuous)
                    .fill(Palette.chip)
            )
    }

    // MARK: - 列表

    private func list(_ m: Metrics) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                imageRow(m)
                titleRow(m)
            }
            .padding(.horizontal, m.pagePadding)
            .padding(.bottom, m.size(24))
        }
        .frame(maxHeight: .infinity)
    }

    private func imageRow(_ m: Metrics) -> some View {
        Button {
            showPicker = true
        } label: {
            HStack(alignment: .top, spacing: m.size(6)) {
                thumb(m)

                VStack(alignment: .leading, spacing: m.size(4)) {
                    Text("封面图")
                        .font(.system(size: m.bodyText))
                        .foregroundStyle(Palette.ink)
                    Text(image == nil ? "未选择" : byteText)
                        .font(.system(size: m.metaText))
                        .foregroundStyle(Palette.caption)
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, m.rowSpacing)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func titleRow(_ m: Metrics) -> some View {
        TextField("输入文字", text: $title)
            .font(.system(size: m.bodyText))
            .foregroundStyle(Palette.ink)
            .padding(.vertical, m.rowSpacing)
    }

    @ViewBuilder
    private func thumb(_ m: Metrics) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: m.thumb, height: m.thumb)
                .clipped()
        } else {
            Image(systemName: "photo")
                .font(.system(size: m.size(22), weight: .regular))
                .foregroundStyle(Palette.caption)
                .frame(width: m.thumb, height: m.thumb)
                .background(Palette.chip)
        }
    }

    private var byteText: String {
        "\(max(1, imageBase64.count / 1024)) KB"
    }

    // MARK: - 底栏

    private func bottomBar(_ m: Metrics) -> some View {
        HStack(spacing: m.size(8)) {
            barButton("启动实时活动", filled: true, enabled: !running, m) { start() }
            barButton("停止", filled: false, enabled: running, m) { stop() }
        }
        .padding(m.size(8))
        .background {
            if image == nil {
                Palette.canvas
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .shadow(color: .black.opacity(0.10), radius: m.size(14), x: 0, y: -m.size(4))
    }

    private func barButton(
        _ label: String,
        filled: Bool,
        enabled: Bool,
        _ m: Metrics,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: m.size(15), weight: .medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, m.size(10))
                .foregroundStyle(filled ? Palette.canvas : Palette.ink)
                .background(
                    RoundedRectangle(cornerRadius: m.radius, style: .continuous)
                        .fill(filled ? Palette.ink : Palette.chip)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }

    // MARK: - 图片处理

    @MainActor
    private func loadImage(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let picked = UIImage(data: data) else { return }

        image = picked

        guard let thumbnail = makeThumbnail(from: picked) else {
            imageBase64 = ""
            return
        }

        imageBase64 = thumbnail.base64EncodedString()
    }

    private func clearImage() {
        image = nil
        imageBase64 = ""
        photoItem = nil
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
