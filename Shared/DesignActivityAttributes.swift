import ActivityKit
import Foundation

struct DesignActivityAttributes: ActivityAttributes {
    var designName: String = "Live Activity"

    struct ContentState: Codable, Hashable {
        var title: String
        /// 缩略图 base64（JPEG）。空串表示没有图片，此时只显示一行文字。
        var imageBase64: String = ""
        /// 紧凑态右侧显示的 SF Symbol；为空时回退到默认图标。
        var symbol: String? = nil
    }
}
