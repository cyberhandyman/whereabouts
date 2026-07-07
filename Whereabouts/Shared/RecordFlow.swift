import Foundation

// Phase 111(iOS 版):录入流程的三个"待用户决定"数据结构,从 ContentView.swift 挪到这里 ——
// macOS 主窗口和 iOS "记一条" tab 共用同一套录入决策语义(重复检测 / 字段更新意图 / 同名叶子消歧)。

/// Phase 17:用户给的单段位置("抽屉第一层")在库里有多个同名叶子,等用户挑一个。
/// candidates 里的每个 Location 通过 `loc.path` 自身展开成完整祖先链给用户看。
struct PendingAmbiguousLocation: Identifiable {
    let id = UUID()
    let parsed: InputParser.Parsed
    let candidates: [Location]
    let originalLeaf: String
    /// Phase 43:消歧期间暂存的整段用户原文,被选完后写到新 item.rawInput。
    let rawInput: String?
}

/// 检测到"X 的型号是 Y" 这种对已有物品的字段更新意图,暂存待用户决定。
struct PendingUpdate: Identifiable {
    let id = UUID()
    let item: Item
    let changes: InputParser.ItemChanges
    let summary: String
}

/// 录入时撞上同名/包含关系条目,暂存待用户决定。
struct PendingDuplicate: Identifiable {
    let id = UUID()
    let existing: Item
    let newName: String
    let newPath: [String]
    let newDate: Date?
    let newDatePrecision: String?
    let newSource: String?
    let newModel: String?
    let newColor: String?
    let newVersion: String?

    /// 新句子里至少抽到了一个元数据(日期/渠道/型号/颜色/版本)。
    /// 没位置又没元数据时,弹"补充信息"按钮就没意义了 —— 直接只给"新建/取消"。
    var hasMetadata: Bool {
        newDate != nil || newSource != nil || newModel != nil
            || newColor != nil || newVersion != nil
    }

    /// 给 alert message 用的"会补充什么"摘要。
    /// 每个 part 走 catalog(复用 filter.chip.* 那组带 %@ 占位符的 key)。
    /// 拼接用 ListFormatter,中文得到 "X、Y、Z",英文得到 "X, Y, and Z" — locale 自动处理。
    var metaSummary: String {
        var parts: [String] = []
        if let m = newModel   { parts.append(String(localized: "filter.chip.model \(m)")) }
        if let v = newVersion { parts.append(String(localized: "filter.chip.version \(v)")) }
        if let c = newColor   { parts.append(String(localized: "filter.chip.color \(c)")) }
        if let s = newSource  { parts.append(String(localized: "filter.chip.source \(s)")) }
        if let label = formatPurchaseDate(newDate, precision: newDatePrecision) {
            parts.append(String(localized: "filter.chip.purchase \(label)"))
        }
        return parts.isEmpty
            ? String(localized: "dup.metaSummary.empty")
            : ListFormatter.localizedString(byJoining: parts)
    }
}
