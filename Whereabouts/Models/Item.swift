import Foundation
import SwiftData

/// 按 purchaseDatePrecision 格式化购买日期,按系统 locale 自动本地化。
/// "year"   → zh-Hans "2024年" / en "2024"
/// "month"  → zh-Hans "2024年5月" / en "May 2024"
/// nil/day  → zh-Hans "2024年5月8日" / en "May 8, 2024"
///
/// 用 `Date.FormatStyle` 而非手写字符串,Swift 自带 locale 处理,不进 String Catalog。
func formatPurchaseDate(_ date: Date?, precision: String?) -> String? {
    guard let date = date else { return nil }
    switch precision {
    case "year":
        return date.formatted(.dateTime.year())
    case "month":
        return date.formatted(.dateTime.year().month())
    default:
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

@Model
final class Item {
    // Phase 116(iCloud):CloudKit 要求所有非可选属性带默认值 —— 这里的默认值只为
    // 满足 schema 校验,实际值始终由 init 赋。
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date.distantPast
    var updatedAt: Date = Date.distantPast
    /// 最后一次声明该物品在某位置的时间(便于"上次见到"提示);初次为 createdAt。
    var lastSeenAt: Date = Date.distantPast

    /// 物品所在位置。可空 —— 允许"先记下,位置待定"。
    var location: Location?

    /// 照片的二进制数据(JPEG/HEIC)。Phase 4 启用。
    /// externalStorage 让 SwiftData 把大数据存外部文件,而不是塞进 sqlite。
    @Attribute(.externalStorage) var photoData: Data?

    // MARK: - 可选元数据(SwiftData 加可空字段属于轻量迁移,旧数据不受影响)

    /// 型号:"iPhone 15 Pro" / "Sony WH-1000XM5"
    var model: String?
    /// 版本/规格:"512GB" / "亚太版" / "第二代"
    var version: String?
    /// 颜色:"黑" / "暗紫色"
    var color: String?
    /// 购买日期。和 purchaseDatePrecision 一起用 —— 只到年/月时月日会被填 1,展示时要按 precision 格式化。
    var purchaseDate: Date?
    /// 购买日期的精度。"year" / "month" / "day" 或 nil(nil = 老数据,按 day 处理)。
    var purchaseDatePrecision: String?
    /// 购买渠道:"京东" / "闲鱼" / "线下" 或任意自定义
    var purchaseSource: String?

    /// 用户在"记一条"里写下的原文(Phase 43)。
    /// 一次输入被 parser 拆成多条时,**每一条都存一份完整原文**,
    /// 这样 AI 再次理解某一条时,能看到用户当时说的整段话(包括其它条的上下文、
    /// 已经提到的地点别称等),做出更准的解析。
    /// 老数据为 nil(SwiftData 轻量迁移),AI 兜底回 name + notes。
    var rawInput: String?

    /// 关联组 ID(Phase 52)。同一个 UUID 的所有物品互相算作"关联项目"。
    /// nil = 没参与任何关联;有值 = 同组成员可通过 fetch 拿到。
    /// 关联是**双向 + 传递闭包**:
    ///   - A 关联 B → 二者同 ID
    ///   - C 再关联 A 或 B → C 进入同一个 ID 的组
    ///   - 两个不同 ID 的组合并 → 取一个 ID 把所有成员都改成它
    /// 一组容量上限 8 件;无限多组。看 `RelatedGroup` 命名空间里的 link / unlink / members。
    /// SwiftData 轻量迁移:旧记录默认 nil。
    var relatedGroupID: UUID?

    /// 位置历史:这件东西去过哪。倒序就是从最近到最早。
    /// 删除 item 时连同 logs 一起删(.cascade)。
    @Relationship(deleteRule: .cascade, inverse: \LocationLog.item)
    var locationHistory: [LocationLog] = []

    /// 字段编辑历史(Phase 39):name / model / color / 等字段被改过的前后值 + 来源。
    /// 跟 locationHistory 平行,合并在详情时间线展示。
    @Relationship(deleteRule: .cascade, inverse: \EditLog.item)
    var editHistory: [EditLog] = []

    /// 用户挂的标签(多对多)。inverse 写在 Tag 那一侧。
    /// 删除 item 不删 tag(只是断挂载),反之亦然。
    @Relationship var tags: [Tag] = []

    // MARK: - 置顶(重要物品 + 通知)
    /// 置顶 = 重要 = 想定期收到"它还在原位吗?"提醒。
    /// SwiftData 轻量迁移:旧记录默认 false。
    var isPinned: Bool = false

    /// 上次完成的"用过吗?"动作类型 —— 详情页四个按钮里强调最近按过的那个。
    /// 值:"stillThere" / "putBack" / "moved" / "unknown" 或 nil(从未按过)。
    var lastActionType: String?

    // MARK: - 软删除(回收站)
    /// 真删之前先 soft delete:isDeleted=true、隐藏出主列表 / 搜索 / facet / 状态栏统计,
    /// 但数据完整保留,可在"回收站"窗口右键还原。
    /// SwiftData 轻量迁移:旧记录默认 false。
    var isDeleted: Bool = false
    /// 被 soft delete 的时间。还原时清回 nil。
    var deletedAt: Date?

    // MARK: - 借出去(Phase 91)
    /// 借给谁。nil = 没借出。轻量迁移:旧记录默认 nil。
    /// 跟 location 互不冲突 —— 借出时 location 通常保留为"本来该在的地方",
    /// 借出状态只用 lentTo + lentAt 表达;归还时清这两字段。
    var lentTo: String?
    /// 借出时间。配合 lentTo 显示"借给 XX X 天前"。归还时清回 nil。
    var lentAt: Date?

    init(
        name: String,
        notes: String = "",
        location: Location? = nil,
        photoData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.name = name
        self.notes = notes
        self.location = location
        self.photoData = photoData
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.lastSeenAt = createdAt
    }
}

extension Item {
    /// 软删除 —— 标 isDeleted,不真删。回收站里可还原 / 彻底删除。
    func markDeleted() {
        self.isDeleted = true
        self.deletedAt = .now
        self.updatedAt = .now
    }

    /// 从回收站还原。
    func restore() {
        self.isDeleted = false
        self.deletedAt = nil
        self.updatedAt = .now
    }

    /// 借出 —— 写 lentTo + lentAt + lastActionType="lent_out"。
    /// 不动 location(物品本来该在的地方保留)。详情时间线靠 lastActionType + lentAt 显示。
    func markLentOut(to person: String, at date: Date = .now) {
        let p = person.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        self.lentTo = p
        self.lentAt = date
        self.lastActionType = "lent_out"
        self.updatedAt = date
    }

    /// 归还 —— 清两字段 + lastActionType="returned" + lastSeenAt=now。
    func markReturned() {
        self.lentTo = nil
        self.lentAt = nil
        self.lastActionType = "returned"
        self.lastSeenAt = .now
        self.updatedAt = .now
    }

    /// 借出去了吗?nil-safe 短路。
    var isLentOut: Bool { lentTo != nil }
}
