import Foundation
import SwiftData

/// 物品关联组的操作命名空间(Phase 52)。
///
/// 数据模型见 `Item.relatedGroupID`:同一个 UUID 的物品互相算关联。
/// 关联是 **双向 + 传递闭包**:
///   - A 关联 B → 二者同 ID
///   - C 再关联 A → 三者同 ID
///   - 两个不同组合并 → 容量允许的话取一边 ID 重写另一边所有成员
///
/// 容量上限:8。
enum RelatedGroup {

    /// 一组关联最多多少件物品。超出就拒绝 link。
    static let maxGroupSize = 8

    /// 关联操作可能出的错。UI 层用 `.localizedDescription` 直接显示给用户。
    enum LinkError: LocalizedError {
        /// 组容量已满(传当前 count),拒绝新加。
        case groupFull(Int)
        /// 合并后会超 8 件(传 a.count, b.count),拒绝合并。
        case mergeOverflow(Int, Int)
        /// 试图把自己关联到自己。UI 层应该提前过滤掉,这里防御性兜底。
        case sameItem

        var errorDescription: String? {
            switch self {
            case .groupFull(let n):
                return String(localized: "related.error.groupFull \(n) \(RelatedGroup.maxGroupSize)")
            case .mergeOverflow(let a, let b):
                return String(localized: "related.error.mergeOverflow \(a) \(b) \(RelatedGroup.maxGroupSize)")
            case .sameItem:
                return String(localized: "related.error.sameItem")
            }
        }
    }

    /// 把 `a` 和 `b` 关联起来 —— 4 种 case:
    ///   1. 两者都未入组 → 新建一个 UUID,两者都填上
    ///   2. 只有 a 有组 → b 加进 a 的组(检查容量 < 8)
    ///   3. 只有 b 有组 → a 加进 b 的组(同上)
    ///   4. 两者都有组:
    ///      4a. 同组 → noop(已经关联了)
    ///      4b. 不同组 → 合并:取 a 的 ID,把 b 组所有成员改为 a 的 ID(检查合并后 ≤ 8)
    ///
    /// 调用方应包 try / catch,失败时把 `LinkError.localizedDescription` 弹给用户。
    @MainActor
    static func link(_ a: Item, _ b: Item, in context: ModelContext) throws {
        guard a.persistentModelID != b.persistentModelID else { throw LinkError.sameItem }

        switch (a.relatedGroupID, b.relatedGroupID) {

        // case 1:都没组 → 新建
        case (nil, nil):
            let id = UUID()
            a.relatedGroupID = id
            b.relatedGroupID = id
            a.updatedAt = .now
            b.updatedAt = .now

        // case 2:a 有组,b 加进来
        case (.some(let gid), nil):
            let count = members(of: gid, in: context).count
            guard count < maxGroupSize else { throw LinkError.groupFull(count) }
            b.relatedGroupID = gid
            b.updatedAt = .now
            a.updatedAt = .now

        // case 3:b 有组,a 加进来
        case (nil, .some(let gid)):
            let count = members(of: gid, in: context).count
            guard count < maxGroupSize else { throw LinkError.groupFull(count) }
            a.relatedGroupID = gid
            a.updatedAt = .now
            b.updatedAt = .now

        // case 4:两者都有组
        case (.some(let ga), .some(let gb)):
            if ga == gb { return }  // 已同组
            let groupA = members(of: ga, in: context)
            let groupB = members(of: gb, in: context)
            let combined = groupA.count + groupB.count
            guard combined <= maxGroupSize else {
                throw LinkError.mergeOverflow(groupA.count, groupB.count)
            }
            // 合并到 a 的 ID:重写 b 组所有成员的 groupID
            for item in groupB {
                item.relatedGroupID = ga
                item.updatedAt = .now
            }
        }
    }

    /// 把 `item` 从当前组里移除。如果剩下只有 1 件,把那一件也置 nil
    /// (避免出现"1 件孤儿组" —— 1 件没有关联对象,语义上等于没参与关联)。
    @MainActor
    static func unlink(_ item: Item, in context: ModelContext) {
        guard let gid = item.relatedGroupID else { return }
        item.relatedGroupID = nil
        item.updatedAt = .now
        let remaining = members(of: gid, in: context)
        if remaining.count == 1 {
            remaining[0].relatedGroupID = nil
            remaining[0].updatedAt = .now
        }
    }

    /// 拉一个组里的所有成员(包括 deleted/未 deleted 都算 —— UI 层自己再 filter `!isDeleted`)。
    /// 给 link 容量计算用;给 UI 列表用。
    @MainActor
    static func members(of groupID: UUID, in context: ModelContext) -> [Item] {
        let descriptor = FetchDescriptor<Item>(
            predicate: #Predicate<Item> { $0.relatedGroupID == groupID }
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 同组其他成员 —— UI 主要消费这个。自动排除 self、排除 soft-deleted。
    @MainActor
    static func peers(of item: Item, in context: ModelContext) -> [Item] {
        guard let gid = item.relatedGroupID else { return [] }
        return members(of: gid, in: context).filter {
            $0.persistentModelID != item.persistentModelID && !$0.isDeleted
        }
    }
}
