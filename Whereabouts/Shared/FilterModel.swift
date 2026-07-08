import Foundation
import SwiftUI
import SwiftData

// Phase 111(iOS 版):FilterModel + SortMode 从 ContentView.swift 挪到这里 ——
// iOS 的首页列表用同一套筛选 / 排序语义,macOS / iOS 两个 target 都编译本文件。

/// 主列表排序方式。@AppStorage 持久化用户选择。
enum SortMode: String, CaseIterable, Identifiable {
    case updated   // updatedAt desc(任何字段改动)
    case seen      // lastSeenAt desc(放回 / 移动 / 不知道在哪)
    case created   // createdAt desc(录入时间)
    case name      // name asc,localizedStandard 比较(中文按拼音)
    case location  // location.path asc(同地点的相邻)

    var id: String { rawValue }
    var displayKey: LocalizedStringKey {
        switch self {
        case .updated:  return "sort.updated"
        case .seen:     return "sort.seen"
        case .created:  return "sort.created"
        case .name:     return "sort.name"
        case .location: return "sort.location"
        }
    }
    var systemImage: String {
        switch self {
        case .updated:  return "pencil"
        case .seen:     return "eye"
        case .created:  return "plus.circle"
        case .name:     return "textformat"
        case .location: return "mappin"
        }
    }
}

/// 跨视图共享的筛选条件 —— ContentView 持有,通过 environment 注入详情/搜索栏。
/// 主行 facet (渠道 / 年份 / 品牌) 与"详情 chip 点击触发"的精确筛选 (model / color / version / 精确日期)
/// 全部 AND 在一起。一个字段为空就表示不限制。
@Observable
final class FilterModel {
    var search: String = ""

    // facet 行用的(同一时刻每个 facet 最多一个选中)
    var source: String? = nil
    var year: Int? = nil
    var brand: String? = nil
    /// Phase 77:**房间** —— 匹配 item 的**顶层**(parent==nil)祖先名字。
    /// 例:item 在 "书房 > 收纳抽屉",`room = "书房"` 命中,`room = "收纳抽屉"` 不命中。
    var room: String? = nil
    /// Phase 77 重构:**位置** —— 匹配 item.location.path 的完整路径(非根)。
    /// 例:item 在 "书房 > 收纳抽屉",`location = "书房 > 收纳抽屉"` 命中。
    /// 跟以前的"任何祖先节点"模糊匹配不同,这里要**完全相等**;模糊匹配交给搜索框 / `room`。
    var location: String? = nil
    /// Phase 104:**借出状态** —— true = 只看借出去的,false = 只看在家的,nil = 不限制。
    var lent: Bool? = nil
    /// Phase 120:**置顶** —— true = 只看置顶的,nil = 不限制(iOS 统计瓷砖筛选用)。
    var pinned: Bool? = nil

    // 详情页 chip 点击带来的精确筛选
    var model: String? = nil
    var color: String? = nil
    var version: String? = nil
    /// 精确日期 + 精度 ("year" / "month" / "day")。和 year 互斥:点 chip 优先于 facet。
    var exactDate: Date? = nil
    var exactDatePrecision: String? = nil

    var isEmpty: Bool {
        search.isEmpty && source == nil && year == nil && brand == nil
            && room == nil && location == nil && lent == nil && pinned == nil
            && model == nil && color == nil && version == nil && exactDate == nil
    }

    func clearAll() {
        search = ""; source = nil; year = nil; brand = nil
        room = nil; location = nil; lent = nil; pinned = nil
        model = nil; color = nil; version = nil
        exactDate = nil; exactDatePrecision = nil
    }

    /// 一条 item 是否满足当前所有筛选条件。
    func matches(_ item: Item) -> Bool {
        // 搜索:跨 name / notes / 位置路径 / 型号 / 颜色 / 渠道 / 版本 / 借给谁 / 标签名 模糊匹配
        if !search.isEmpty {
            let q = search.lowercased()
            let tagNames = item.tags.map(\.name).joined(separator: " ")
            let hay = [
                item.name, item.notes,
                item.location?.path ?? "",
                item.model ?? "", item.color ?? "",
                item.purchaseSource ?? "", item.version ?? "",
                item.lentTo ?? "", tagNames,
            ].joined(separator: " ").lowercased()
            if !hay.contains(q) { return false }
        }
        if let s = source, item.purchaseSource != s { return false }
        if let b = brand, InputParser.brand(for: item.name) != b { return false }
        // Phase 77:**房间**匹配 —— item 的顶层(parent==nil)祖先名字必须等于 room。
        // case-sensitive 完全相等(facet 列表来源也是 Location.name 原文,不会出错)。
        if let r = room {
            var cursor: Location? = item.location
            while let p = cursor?.parent { cursor = p }
            if cursor?.name != r { return false }
        }
        // Phase 77 重构:**位置**匹配 —— item.location.path 完全相等。
        // 跟 room 配合:房间筛"在 X 房间的所有",位置筛"在 X > Y 这层具体位置的"。
        if let loc = location, item.location?.path != loc { return false }
        // Phase 104:**借出状态** —— true 只看借出去的,false 只看在家的。
        if let l = lent, item.isLentOut != l { return false }
        // Phase 120:**置顶**。
        if let p = pinned, item.isPinned != p { return false }
        if let m = model, item.model != m { return false }
        if let c = color, item.color != c { return false }
        if let v = version, item.version != v { return false }
        if let y = year {
            guard let d = item.purchaseDate else { return false }
            if Calendar.current.component(.year, from: d) != y { return false }
        }
        if let target = exactDate {
            guard let d = item.purchaseDate else { return false }
            let cal = Calendar.current
            switch exactDatePrecision {
            case "year":
                if cal.component(.year, from: d) != cal.component(.year, from: target) { return false }
            case "month":
                let a = cal.dateComponents([.year, .month], from: d)
                let b = cal.dateComponents([.year, .month], from: target)
                if a != b { return false }
            default:
                if !cal.isDate(d, inSameDayAs: target) { return false }
            }
        }
        return true
    }
}
