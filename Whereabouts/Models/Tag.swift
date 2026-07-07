import Foundation
import SwiftData
import SwiftUI

/// 用户自定义标签 —— 类似 Finder 的标签:有颜色 + 名字。
/// 一个 Item 可挂多个 Tag(多对多)。
/// colorHex 存十六进制色串("#FFB000"),展示时还原成 Color/NSColor;预设色见 `TagPalette`。
@Model
final class Tag {
    /// 用户可见名:"生活用品" / "3C 电子" / 用户自填。
    var name: String

    /// 颜色码 "#RRGGBB"。展示时通过 Color(hex:) 还原。
    var colorHex: String

    /// 创建时间,用于排序(预设是 app launch 时 seed,后加的排末尾)。
    var createdAt: Date

    /// 反向关系:用了这个 tag 的所有 item。
    /// nullify:删 tag 不会删 item(只是清掉这条挂载)。
    @Relationship(deleteRule: .nullify, inverse: \Item.tags)
    var items: [Item] = []

    init(name: String, colorHex: String, createdAt: Date = .now) {
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }
}

/// Finder 风格的固定调色板:7 色 + 2 个扩展。
/// 用户新建 tag 时从这里选,而不是给随便选颜色 —— 8 个够分类,不需要 RGB 拾色器。
enum TagPalette {
    static let all: [(name: String, hex: String)] = [
        ("gray",   "#8E8E93"),
        ("red",    "#FF3B30"),
        ("orange", "#FF9500"),
        ("yellow", "#FFCC00"),
        ("green",  "#34C759"),
        ("teal",   "#5AC8FA"),
        ("blue",   "#007AFF"),
        ("purple", "#AF52DE"),
        ("pink",   "#FF2D55"),
    ]

    /// 给 app 首次启动 seed 的预设 tag(中文 + 英文名都进 catalog 走本地化展示)。
    /// 注意:tag.name 存的是"显示名",seed 时取当前 locale 写入。
    /// (用户切换语言后已 seed 的 tag 名字不会自动改 —— 这是用户数据,跟物品名一样。)
    ///
    /// Phase 59:从 6 个扩到 15 个,覆盖收纳困难人群常见的全部品类(化妆护肤、服饰鞋包、
    /// 母婴、药品、食品、票据证件、玩具游戏、宠物、户外运动、爱好收藏)。**已 seed
    /// 过的 tag 不重复添加**(按 name 去重),所以老用户升级只会**补**新预设,不影响
    /// 自建标签,也不会复活被删除的预设(用户删过的 preset name 检测到已不存在
    /// 但不在已有列表里 —— 检测逻辑会重新 seed,这是个 trade-off,见 seed 注释)。
    static let presets: [(nameKey: String, colorHex: String)] = [
        // 原 6 个
        ("tag.preset.daily",      "#8E8E93"),  // 生活用品(灰)
        ("tag.preset.tech",       "#007AFF"),  // 3C 电子(蓝)
        ("tag.preset.kitchen",    "#FF9500"),  // 厨具(橙)
        ("tag.preset.tools",      "#FFCC00"),  // 小工具(黄)
        ("tag.preset.office",     "#AF52DE"),  // 办公用品(紫)
        ("tag.preset.stationery", "#34C759"),  // 文具(绿)
        // Phase 59 新增 8 个
        ("tag.preset.beauty",     "#FF2D55"),  // 化妆护肤(粉)
        ("tag.preset.apparel",    "#5856D6"),  // 服饰鞋包(靛)
        ("tag.preset.health",     "#FF3B30"),  // 药品健康(红)
        ("tag.preset.food",       "#FFB05A"),  // 食品干货(浅橙)
        ("tag.preset.docs",       "#A2845E"),  // 票据证件(棕)
        ("tag.preset.hobby",      "#30D158"),  // 玩具/游戏/手办(深绿)
        ("tag.preset.outdoor",    "#64D2FF"),  // 户外/运动(湖蓝)
        ("tag.preset.pets",       "#BF5AF2"),  // 宠物用品(紫)
    ]
}

/// Phase 59:预设 tag 集合的版本化迁移声明。
/// 在 `TagPalette.presets` 加新预设时,**同时**在这里 bump `currentVersion`,
/// 并把新增的 keys 加到 `keysAddedInVersion`。
/// ContentView.seedExtendedPresetsIfNeeded() 升级时按版本号取增量 seed。
enum TagPresetMigration {

    /// 当前预设集合的版本号。改:在 TagPalette.presets 加新条目时 bump 一次。
    static let currentVersion: Int = 2

    /// 每版相对上一版**新加**的 nameKey 列表。索引 = 版本号。
    /// version 1 是初始 6 个预设(已经被 hasSeedTags 那一路 seed 进去了,这里**不重复**);
    /// version 2 是 Phase 59 加的 8 个 —— 老用户升级时只补这 8 个。
    private static let keysAddedInVersion: [Int: [String]] = [
        2: [
            "tag.preset.beauty",
            "tag.preset.apparel",
            "tag.preset.health",
            "tag.preset.food",
            "tag.preset.docs",
            "tag.preset.hobby",
            "tag.preset.outdoor",
            "tag.preset.pets",
        ],
    ]

    /// 从老版本升级到 currentVersion 时,需要新 seed 哪些 nameKey?
    /// 返回 Set 方便 contains 查;空集 = 没新增。
    static func newKeysSince(version oldVersion: Int) -> Set<String> {
        var result: Set<String> = []
        // 老用户 v0 / v1 升 v2 → 取 (oldVersion, currentVersion] 区间内每版的 keys
        for v in (oldVersion + 1)...currentVersion {
            if let keys = keysAddedInVersion[v] {
                result.formUnion(keys)
            }
        }
        return result
    }
}

/// Color extension:从 "#RRGGBB" 还原 SwiftUI Color。失败回退 .gray。
extension Color {
    init(tagHex hex: String) {
        var s = hex
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let int = UInt64(s, radix: 16) else {
            self = .gray
            return
        }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}
