import Foundation
import SwiftData

/// 一个物品的位置历史条目。每次"创建/放回原位/位置变了/重复→更新"都会写一条。
/// 倒序展示就是 item 在世界上飘过的轨迹。
@Model
final class LocationLog {
    /// 这条 log 记录的时间。
    var recordedAt: Date = Date.distantPast

    /// 当时所在位置;nil = 未指定。
    /// nullify:位置被删除时这条 log 不跟着消失,只是把指针清空(保留历史时间点)。
    @Relationship(deleteRule: .nullify)
    var location: Location?

    /// 所属物品(反向关系由 Item.locationHistory 那边声明)。
    var item: Item?

    init(recordedAt: Date = .now, location: Location? = nil, item: Item? = nil) {
        self.recordedAt = recordedAt
        self.location = location
        self.item = item
    }
}
