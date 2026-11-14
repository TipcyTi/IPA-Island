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

/// 尺寸全部按 390pt 宽等比缩放，换机型不跑版。
struct Metrics {
    let width: CGFloat

    init(width: CGFloat) { self.width = width }

    func ratio(_ value: CGFloat) -> CGFloat { width * value }

    /// 页面左右留白
    var hPadding: CGFloat { ratio(0.055) }
    /// 卡片圆角
    var cardRadius: CGFloat { ratio(0.058) }
    /// 封面圆角
    var coverRadius: CGFloat { ratio(0.070) }
    /// 区块间距
    var gap: CGFloat { ratio(0.038) }
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

/// 主页：一张封面卡 + 一行可点开的文字 + 一颗主操作按钮。
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
    @State private var notice: String?
    @FocusState private var titleFocused: Bool

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

    private var shadowColor: Color {
        .black.opacity(colorScheme == .dark ? 0.42 : 0.07)
    }

    private var noticePresented: Binding<Bool> {
        Binding(
            get: { notice != nil },
            set: { if !$0 { notice = nil } }
        )
    }

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(width: geo.size.width)

            ZStack {
                Palette.canvas
                    .ignoresSafeArea()

                VStack(spacing: m.gap) {
                    header(m)

                    cover(m)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    titleCard(m)

                    actionSection(m)
                }
                .padding(.horizontal, m.hPadding)
                .padding(.top, m.ratio(0.015))
                .padding(.bottom, m.ratio(0.02))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    backdrop(m)
                }
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
        .alert("提示", isPresented: noticePresented) {
            Button("好", role: .cancel) { notice = nil }
        } message: {
            Text(notice ?? "")
        }
    }

    // MARK: - 顶部

    private func header(_ m: Metrics) -> some View {
        HStack(alignment: .center, spacing: m.ratio(0.03)) {
            VStack(alignment: .leading, spacing: m.ratio(0.008)) {
                Text("MI ISLAND")
                    .font(.system(size: m.ratio(0.028), weight: .semibold))
                    .tracking(m.ratio(0.007))
                    .foregroundStyle(Palette.caption)

                Text("实时活动设计器")
                    .font(.system(size: m.ratio(0.066), weight: .black))
                    .foregroundStyle(Palette.ink)
            }

            Spacer(minLength: m.ratio(0.02))

            statusPill(m)
        }
    }

    private func statusPill(_ m: Metrics) -> some View {
        HStack(spacing: m.ratio(0.017)) {
            Circle()
                .fill(running ? Palette.ink : Palette.caption)
                .frame(width: m.ratio(0.016), height: m.ratio(0.016))

            Text(running ? "运行中" : "未启动")
                .font(.system(size: m.ratio(0.030), weight: .semibold))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, m.ratio(0.030))
        .padding(.vertical, m.ratio(0.018))
        .background(Capsule(style: .continuous).fill(Palette.chip))
        .overlay(Capsule(style: .continuous).strokeBorder(Palette.hairline, lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: running)
        .accessibilityLabel(running ? "实时活动运行中" : "实时活动未启动")
    }

    // MARK: - 封面

    private func cover(_ m: Metrics) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                coverBody(m, size: proxy.size)
                    .clipShape(RoundedRectangle(cornerRadius: m.coverRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: m.coverRadius, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                            .opacity(image == nil ? 0 : 1)
                    )
                    .shadow(color: shadowColor, radius: 24, x: 0, y: 12)
                    .contentShape(RoundedRectangle(cornerRadius: m.coverRadius, style: .continuous))
                    .onTapGesture { showPicker = true }
                    .contextMenu {
                        Button {
                            showPicker = true
                        } label: {
                            Label("更换封面", systemImage: "photo")
                        }

                        if image != nil {
                            Button(role: .destructive) {
                                clearImage()
                            } label: {
                                Label("移除封面", systemImage: "trash")
                            }
                        }
                    }

                if image != nil {
                    Menu {
                        Button {
                            showPicker = true
                        } label: {
                            Label("更换封面", systemImage: "photo")
                        }

                        Button(role: .destructive) {
                            clearImage()
                        } label: {
                            Label("移除封面", systemImage: "trash")
                        }
                    } label: {
                        menuBadge(m)
                    }
                    .buttonStyle(.plain)
                    .padding(m.ratio(0.034))
                }
            }
        }
    }

    @ViewBuilder
    private func coverBody(_ m: Metrics, size: CGSize) -> some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .clipped()

                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.38)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack {
                    Spacer()

                    HStack {
                        Text("点按更换封面")
                            .font(.system(size: m.ratio(0.030), weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, m.ratio(0.026))
                            .padding(.vertical, m.ratio(0.012))
                            .background(Capsule(style: .continuous).fill(Color.black.opacity(0.34)))

                        Spacer()
                    }
                    .padding(m.ratio(0.032))
                }
            } else {
                Palette.chip
                emptyCover(m)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func emptyCover(_ m: Metrics) -> some View {
        VStack(spacing: m.ratio(0.024)) {
            ZStack {
                Circle().fill(Palette.card)
                Circle().strokeBorder(Palette.hairline, lineWidth: 1)
                Image(systemName: "plus")
                    .font(.system(size: m.ratio(0.050), weight: .semibold))
                    .foregroundStyle(Palette.ink.opacity(0.7))
            }
            .frame(width: m.ratio(0.150), height: m.ratio(0.150))

            Text("添加封面")
                .font(.system(size: m.ratio(0.044), weight: .semibold))
                .foregroundStyle(Palette.ink)

            Text("会同步到锁屏与灵动岛")
                .font(.system(size: m.ratio(0.032)))
                .foregroundStyle(Palette.caption)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: m.coverRadius - m.ratio(0.018), style: .continuous)
                .strokeBorder(
                    Palette.hairline,
                    style: StrokeStyle(
                        lineWidth: 1.5,
                        dash: [m.ratio(0.020), m.ratio(0.018)]
                    )
                )
                .padding(m.ratio(0.026))
        )
    }

    private func menuBadge(_ m: Metrics) -> some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
            Image(systemName: "ellipsis")
                .font(.system(size: m.ratio(0.046), weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: m.ratio(0.105), height: m.ratio(0.105))
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 3)
        .accessibilityLabel("封面操作")
    }

    // MARK: - 显示文字

    private func titleCard(_ m: Metrics) -> some View {
        VStack(alignment: .leading, spacing: m.ratio(0.016)) {
            Text("显示文字")
                .font(.system(size: m.ratio(0.030), weight: .semibold))
                .tracking(m.ratio(0.006))
                .foregroundStyle(Palette.caption)

            if editing {
                HStack(spacing: m.ratio(0.022)) {
                    TextField("Island", text: $draft)
                        .font(.system(size: m.ratio(0.052), weight: .bold))
                        .foregroundStyle(Palette.ink)
                        .tint(Palette.ink)
                        .focused($titleFocused)
                        .submitLabel(.done)
                        .onSubmit(saveTitle)
                        .onAppear {
                            DispatchQueue.main.async { titleFocused = true }
                        }

                    Button(action: cancelTitle) {
                        Image(systemName: "xmark")
                            .font(.system(size: m.ratio(0.032), weight: .bold))
                            .foregroundStyle(Palette.caption)
                            .frame(width: m.ratio(0.088), height: m.ratio(0.088))
                            .background(Circle().fill(Palette.chip))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("取消编辑")

                    Button(action: saveTitle) {
                        Text("完成")
                            .font(.system(size: m.ratio(0.032), weight: .bold))
                            .foregroundStyle(Palette.canvas)
                            .padding(.horizontal, m.ratio(0.036))
                            .frame(height: m.ratio(0.088))
                            .background(Capsule(style: .continuous).fill(Palette.ink))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("保存文字")
                }
            } else {
                Button {
                    draft = title
                    editing = true
                } label: {
                    HStack(spacing: m.ratio(0.030)) {
                        Text(displayTitle)
                            .font(.system(size: m.ratio(0.052), weight: .bold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ZStack {
                            Circle().fill(Palette.chip)
                            Image(systemName: "pencil")
                                .font(.system(size: m.ratio(0.036), weight: .semibold))
                                .foregroundStyle(Palette.ink.opacity(0.8))
                        }
                        .frame(width: m.ratio(0.088), height: m.ratio(0.088))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("编辑显示文字")
            }
        }
        .padding(.horizontal, m.ratio(0.044))
        .padding(.vertical, m.ratio(0.036))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: m.cardRadius, style: .continuous)
                .fill(Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: m.cardRadius, style: .continuous)
                .strokeBorder(Palette.hairline, lineWidth: 1)
        )
        .shadow(color: shadowColor, radius: 16, x: 0, y: 8)
        .animation(.snappy(duration: 0.26), value: editing)
    }

    // MARK: - 主操作

    private func actionSection(_ m: Metrics) -> some View {
        VStack(spacing: m.ratio(0.018)) {
            Button(action: toggleActivity) {
                HStack(spacing: m.ratio(0.022)) {
                    Image(systemName: running ? "stop.fill" : "play.fill")
                        .font(.system(size: m.ratio(0.034), weight: .bold))

                    Text(running ? "停止实时活动" : "启动实时活动")
                        .font(.system(size: m.ratio(0.043), weight: .bold))
                }
                .foregroundStyle(running ? Palette.ink : Palette.canvas)
                .frame(maxWidth: .infinity)
                .frame(height: m.ratio(0.145))
                .background(
                    RoundedRectangle(cornerRadius: m.cardRadius, style: .continuous)
                        .fill(running ? Palette.chip : Palette.ink)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: m.cardRadius, style: .continuous)
                        .strokeBorder(Palette.hairline, lineWidth: 1)
                        .opacity(running ? 1 : 0)
                )
            }
            .buttonStyle(.plain)

            Text(running ? "改文字或换封面会自动同步，无需再操作" : "启动后会出现在锁屏和灵动岛上")
                .font(.system(size: m.ratio(0.030)))
                .foregroundStyle(Palette.caption)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.2), value: running)
    }

    private func toggleActivity() {
        if running {
            stop()
        } else {
            start()
        }
    }

    // MARK: - 背景（模糊图直接铺满全屏）

    @ViewBuilder
    private func backdrop(_ m: Metrics) -> some View {
        GeometryReader { proxy in
            ZStack {
                Palette.canvas

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .blur(radius: m.ratio(0.13), opaque: true)

                    Palette.canvas.opacity(colorScheme == .dark ? 0.82 : 0.80)
                }
            }
            .clipped()
        }
        .ignoresSafeArea()
    }

    // MARK: - 文字编辑

    private func saveTitle() {
        title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        editing = false
        titleFocused = false
    }

    private func cancelTitle() {
        editing = false
        titleFocused = false
        draft = title
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

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            notice = "系统未开启实时活动，请到 设置 → 通知 → 实时活动 打开后再试。"
            return
        }

        let content = state

        Task { @MainActor in
            for old in Activity<DesignActivityAttributes>.activities {
                await old.end(nil, dismissalPolicy: .immediate)
            }

            do {
                let newActivity = try Activity.request(
                    attributes: DesignActivityAttributes(),
                    content: ActivityContent(state: content, staleDate: nil),
                    pushType: nil
                )
                activity = newActivity
            } catch {
                notice = "启动实时活动失败，请稍后再试。"
            }
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
