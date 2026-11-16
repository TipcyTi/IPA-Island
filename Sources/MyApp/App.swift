import ActivityKit
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

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
    @AppStorage("mi.island.symbol") private var symbol = "sparkles"

    @State private var photoItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showFileImporter = false
    @State private var showSourceDialog = false
    @State private var editing = false
    @State private var draft = ""
    @State private var image: UIImage?
    @State private var backdropImage: UIImage?
    @State private var imageBase64 = ""
    @State private var activity: Activity<DesignActivityAttributes>?
    @State private var updateTask: Task<Void, Never>?
    @State private var notice: String?
    @State private var didAutoStart = false
    @FocusState private var titleFocused: Bool

    init() {
        if let data = CoverStore.load(), let saved = UIImage(data: data) {
            _image = State(initialValue: saved)
            _backdropImage = State(initialValue: Self.backdropThumbnail(from: saved))
        }
    }

    private var displayTitle: String {
        title.isEmpty ? "Island" : title
    }

    private var state: DesignActivityAttributes.ContentState {
        DesignActivityAttributes.ContentState(
            title: displayTitle,
            imageBase64: imageBase64,
            symbol: symbol
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
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    titleCard(m)

                    symbolCard(m)

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
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importImage(from: url)
            case .failure:
                notice = "无法读取所选文件。"
            }
        }
        .confirmationDialog("选择封面", isPresented: $showSourceDialog, titleVisibility: .visible) {
            Button("从相册选择") {
                openPicker { showPicker = true }
            }
            Button("从文件选择") {
                openPicker { showFileImporter = true }
            }

            if image != nil {
                Button("移除封面", role: .destructive) { clearImage() }
            }

            Button("取消", role: .cancel) {}
        }
        .onAppear {
            restoreThumbnail()
            syncActivity()
            autoStartIfNeeded()
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
        HStack(alignment: .firstTextBaseline, spacing: m.ratio(0.022)) {
            Text("MI")
                .font(.system(size: m.ratio(0.080), weight: .black))
                .foregroundStyle(Palette.ink)

            Text("ISLAND")
                .font(.system(size: m.ratio(0.080), weight: .light))
                .tracking(m.ratio(0.0025))
                .foregroundStyle(Palette.ink)

            Spacer(minLength: 0)
        }
    }

    // MARK: - 封面

    private func cover(_ m: Metrics) -> some View {
        GeometryReader { proxy in
            Button {
                presentCoverActions()
            } label: {
                coverBody(m, size: proxy.size)
                    .clipShape(RoundedRectangle(cornerRadius: m.coverRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: m.coverRadius, style: .continuous)
                            .strokeBorder(Palette.hairline, lineWidth: 1)
                            .opacity(image == nil ? 0 : 1)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: m.coverRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .contextMenu {
                Button {
                    showPicker = true
                } label: {
                    Label("从相册选择", systemImage: "photo")
                }

                Button {
                    showFileImporter = true
                } label: {
                    Label("从文件选择", systemImage: "folder")
                }

                if image != nil {
                    Button(role: .destructive) {
                        clearImage()
                    } label: {
                        Label("移除封面", systemImage: "trash")
                    }
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
                    .transition(.opacity)
            } else {
                ZStack {
                    Palette.chip
                    emptyCover(m)
                }
                .transition(.opacity)
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

    private func presentCoverActions() {
        if editing {
            saveTitle()
            return
        }

        showSourceDialog = true
    }

    // MARK: - 显示文字

    private func titleCard(_ m: Metrics) -> some View {
        VStack(alignment: .leading, spacing: m.ratio(0.016)) {
            Text("显示文字")
                .font(.system(size: m.ratio(0.030), weight: .semibold))
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

    // MARK: - 图标

    private let symbolChoices = [
        "sparkles", "bolt.fill", "heart.fill", "star.fill", "moon.stars.fill",
        "flame.fill", "drop.fill", "leaf.fill", "cloud.fill", "sun.max.fill",
        "snowflake", "wind", "music.note", "headphones", "camera.fill",
        "photo.fill", "video.fill", "mic.fill", "bookmark.fill", "flag.fill",
        "bell.fill", "cart.fill", "gift.fill", "gamecontroller.fill",
        "tennisball.fill", "bicycle", "car.fill", "airplane", "map.fill",
        "clock.fill", "calendar", "checkmark.seal.fill", "shield.fill",
        "key.fill", "person.fill", "pawprint.fill", "crown.fill", "atom"
    ]

    private func symbolCard(_ m: Metrics) -> some View {
        VStack(alignment: .leading, spacing: m.ratio(0.016)) {
            Text("图标")
                .font(.system(size: m.ratio(0.030), weight: .semibold))
                .foregroundStyle(Palette.caption)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: m.ratio(0.018)) {
                    ForEach(symbolChoices, id: \.self) { name in
                        Button {
                            symbol = name
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(symbol == name ? Palette.ink : Palette.chip)

                                Image(systemName: name)
                                    .font(.system(size: m.ratio(0.036), weight: .semibold))
                                    .foregroundStyle(symbol == name ? Palette.canvas : Palette.ink)
                            }
                            .frame(width: m.ratio(0.088), height: m.ratio(0.088))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(name)
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, m.ratio(0.044))
        .padding(.vertical, m.ratio(0.030))
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
    }

    // MARK: - 主操作

    private func actionSection(_ m: Metrics) -> some View {
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

                if let backdropImage {
                    Image(uiImage: backdropImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .transition(.opacity)

                    Palette.canvas.opacity(colorScheme == .dark ? 0.82 : 0.80)
                        .transition(.opacity)
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

    // MARK: - 封面上传

    /// 等动作面板收起后再拉起系统选择器，避免两个模态互相抢占。
    private func openPicker(_ present: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: present)
    }

    @MainActor
    private func loadImage(from item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let picked = UIImage(data: data) else { return }

        apply(picked)
    }

    /// 从「文件」App 或其它文件提供方导入图片。
    private func importImage(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        guard let data = try? Data(contentsOf: url),
              let picked = UIImage(data: data) else {
            notice = "这个文件不是可用的图片。"
            return
        }

        apply(picked)
    }

    private func apply(_ picked: UIImage) {
        let stored = downscale(picked, to: 1600, quality: 0.85)
        let display = stored.flatMap { UIImage(data: $0) } ?? picked
        let small = Self.backdropThumbnail(from: display)
        let base64 = makeThumbnail(from: display)?.base64EncodedString() ?? ""

        withAnimation(.easeInOut(duration: 0.24)) {
            image = display
            backdropImage = small
        }

        imageBase64 = base64

        if let stored {
            CoverStore.save(stored)
        }
    }

    private func clearImage() {
        withAnimation(.easeInOut(duration: 0.22)) {
            image = nil
            backdropImage = nil
        }
        imageBase64 = ""
        photoItem = nil
        CoverStore.clear()
    }

    /// 冷启动时把落盘的封面读回来，并补上实时活动要用的缩略图。
    @MainActor
    private func restoreThumbnail() {
        guard let image else { return }

        if imageBase64.isEmpty {
            imageBase64 = makeThumbnail(from: image)?.base64EncodedString() ?? ""
        }

        if backdropImage == nil {
            backdropImage = Self.backdropThumbnail(from: image)
        }
    }

    /// 背景只需要一张很小的纹理，避免在大图上做实时模糊。
    private static func backdropThumbnail(from image: UIImage) -> UIImage? {
        let maxSide: CGFloat = 480
        let width = image.size.width
        let height = image.size.height
        guard width > 0, height > 0 else { return nil }

        let factor = min(maxSide / max(width, height), 1)
        let size = CGSize(
            width: max(1, (width * factor).rounded()),
            height: max(1, (height * factor).rounded())
        )

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// 实时活动状态有 4KB 上限，只能放缩略图：在预算内取尽可能清晰的一张。
    private func makeThumbnail(from image: UIImage) -> Data? {
        let sides: [CGFloat] = [200, 184, 168, 160, 144, 128, 112, 96, 80, 64, 48, 40, 32]
        let qualities: [CGFloat] = [0.65, 0.55, 0.45, 0.35, 0.25]

        var smallest: Data?

        for side in sides {
            for quality in qualities {
                guard let data = downscale(image, to: side, quality: quality) else { continue }
                if smallest == nil || data.count < (smallest?.count ?? Int.max) {
                    smallest = data
                }
                if data.count <= 2800 {
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

    /// 进入主页后自动启动；本次进程只自动启动一次，用户手动停止后不反复拉起。
    private func autoStartIfNeeded() {
        guard !didAutoStart else { return }
        didAutoStart = true

        guard activity == nil else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        start(silent: true)
    }

    private func start(silent: Bool = false) {
        guard !running else { return }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            if !silent {
                notice = "系统未开启实时活动，请到 设置 → 通知 → 实时活动 打开后再试。"
            }
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
                if !silent {
                    notice = "启动实时活动失败，请稍后再试。"
                }
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
