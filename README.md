# Mi Island

一个 SwiftUI iOS 示例工程：在 App 里**自己设计实时活动（Live Activity）**，通过 ActivityKit（系统级 API）把它显示在锁屏和灵动岛上。

构建全程不需要签名和证书，由 GitHub Actions 自动产出**未签名 IPA**。

## 功能

- 启动前先过 **Face ID**（失败可用设备密码），冷启动才验证
- 只有一行文字，可选配一张封面图
- 封面卡：正方形预览，点一下从中选择「相册」或「文件」导入图片，长按可移除；同一张图模糊后铺满整屏当背景
- 从相册选一张图，自动压成缩略图，锁屏和灵动岛（展开 / 紧凑 / 最小）都会显示
- 灵动岛**展开态**：只保留左侧封面（无图时为占位图）与右侧标题，内容留出边距避免被圆角裁切；**紧凑态**左右两侧为图片与滚动文字
- 有图、无图是两套排版：有图时左图右文，无图时只有一行文字、没有图标也没有进度条
- 底部一颗通栏主按钮：**启动实时活动**（`Activity.request`）/ **停止**（`Activity.end`），运行状态直接体现在按钮文案上
- 进入主页会自动启动实时活动；已有活动则直接接管
- 活动运行中改文字或换图会自动同步（`Activity.update`），不用额外再点一次

## 设计

- **只用黑白灰**：文字、按钮、药丸标签都是灰阶，没有任何彩色
- **底色**：浅色 `#F2F4ED`（微暖的米白），深色 `#141414`（近黑的深灰），内容直接铺在底色上
- **工作室式主页**：顶部是 `MI` 重字重 + `ISLAND` 轻字重的字标；中间一张正方形封面卡（无图时是虚线取图区，点按弹出相册 / 文件 / 移除选项）；下面一张「显示文字」卡片，点一下原地变成输入框；底部只有一颗通栏主按钮负责启动 / 停止
- **层次**：封面卡、文字卡都有圆角、描边和很浅的投影；有封面时同一张图模糊后铺满全屏，再压一层底色让卡片始终清楚
- **浅色 / 深色自动适配**：底色、卡片、描边等由 `Palette` 里的动态色决定，跟随系统实时切换，不用手动判断

## 结构

```
.
├── .github/workflows/build.yml        # CI：生成工程 → archive → 打包 IPA → 上传产物
├── Sources/MyApp/App.swift            # 主页（封面 / 文字 / 启停）+ ActivityKit 控制
├── Sources/MyApp/LockGate.swift       # Face ID 解锁页
├── Sources/MyAppWidget/               # 实时活动 Widget 扩展（锁屏 + 灵动岛）
├── Shared/                            # App 与扩展共用的数据模型、颜色工具
├── Info.plist                         # App 配置（含 NSSupportsLiveActivities）
└── project.yml                        # XcodeGen 工程描述（主 App + Widget 扩展）
```

## 构建

推送到 `main` 会自动构建；也可以在 **Actions → Build Unsigned IPA → Run workflow** 手动触发。
产物在对应运行页面的 **Artifacts → MyApp-unsigned-ipa** 下载。

本地构建（需要 macOS + Xcode + [XcodeGen](https://github.com/yonaskolb/XcodeGen)）：

```sh
brew install xcodegen
xcodegen generate
xcodebuild archive -project MyApp.xcodeproj -scheme MyApp \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/MyApp.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=""

mkdir -p Payload
cp -R build/MyApp.xcarchive/Products/Applications/MyApp.app Payload/
zip -r MyApp.ipa Payload
```

## 安装

产出的是**未签名** IPA：构建全程不需要任何签名或证书。

- 设备上有 TrollStore 等支持未签名包的安装器时，可直接安装；
- 否则用 AltStore、Sideloadly 等工具按设备情况装入；
- 未签名包无法上架 App Store，仅用于自测；请确认你拥有设备与账号的合法使用权。

## 使用

1. 打开 App，先过 Face ID（失败可用设备密码），进来就是设计器主页；
2. 点封面卡，选择「从相册选择」或「从文件选择」导入一张图（不选就只有文字）；长按封面可以移除；
3. 点「显示文字」那一行，文字会原地变成输入框，改完点「完成」或键盘上的换行键；
4. 进入主页会自动启动实时活动（已有活动直接接管），也可以在底部重新启动 / 停止，锁屏下拉或长按灵动岛就能看到；
5. 运行中继续改文字或换图，会停顿约半秒自动同步到锁屏，不用再点按钮；
6. 点「停止实时活动」收起。

图片说明：实时活动的状态有 **4KB 上限**，所以选中的照片会被缩到较小的缩略图（≤2200 字节，最多 160px），足够锁屏和灵动岛显示，请不要指望它是高清大图。

注意：实时活动需要 **iOS 16.1+**（本工程部署目标 17.0），灵动岛需要 iPhone 14 Pro 及以上；若系统关闭了实时活动，请到 设置 → 通知 → 实时活动 打开。

## 自定义

- 改显示名 / Bundle ID：编辑 `project.yml` 里两个 target 的 `PRODUCT_BUNDLE_IDENTIFIER`；
- 改版本号：编辑 `Info.plist` 的 `CFBundleShortVersionString` 与 `CFBundleVersion`；
- 改实时活动数据结构：`Shared/DesignActivityAttributes.swift`（App 与 Widget 共用，改一处两边生效）；
- 改外观：`Sources/MyAppWidget/LiveActivityWidget.swift`（锁屏 + 灵动岛），设计器界面在 `Sources/MyApp/App.swift`。
