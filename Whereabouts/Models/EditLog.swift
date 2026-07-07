import Foundation
import SwiftData

/// 字段编辑历史(Phase 39 加)。
///
/// 跟 LocationLog 平行:LocationLog 只记位置变更,EditLog 记其它任何字段(name / model / version
/// / color / purchaseDate / purchaseSource / notes)被改的"前后值 + 来源"。
///
/// 目的:用户可以在详情页时间线看到一条物品被怎么改过 —— AI 改的、本地解析器改的、还是自己改的。
/// 现实场景:某次 AI 误把 model 改错,用户想知道之前的值是啥好回滚 —— 历史里直接能看见。
@Model
final class EditLog {
    /// 时间戳。
    var recordedAt: Date = Date.distantPast

    /// 来源标识,用一个稳定的字符串(供 UI 翻译显示):
    ///   "ai_claude"     —— 用 AI 理解(Claude provider)
    ///   "ai_volcengine" —— 用 AI 理解(火山引擎 provider)
    ///   "parser"        —— 录入或"重新解析名字"按钮跑本地 InputParser
    ///   "update_intent" —— "X 的型号是 Y" 这种本地解析里识别的字段更新意图
    ///   "manual"        —— 用户在 ItemEditView 表单里改过然后点 Done
    ///   "batch"         —— 多选批量编辑(设置标签 / 渠道 等)
    var source: String = "manual"

    /// 字段名 —— 用稳定 key,UI 上 mapped 到本地化标签。
    /// "name" / "model" / "version" / "color" / "purchaseDate" / "purchaseSource" / "notes" / "tags"
    var field: String = ""

    /// 改之前的值(stringified)。nil = 之前没值。
    var oldValue: String?

    /// 改之后的值。nil = 改成清空了。
    var newValue: String?

    /// 反向引用。删 item 时 cascade(声明在 Item 那一侧)。
    var item: Item?

    init(
        recordedAt: Date = .now,
        source: String,
        field: String,
        oldValue: String?,
        newValue: String?,
        item: Item? = nil
    ) {
        self.recordedAt = recordedAt
        self.source = source
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
        self.item = item
    }
}

// MARK: - 快照 + diff 写日志

/// 拍一张 item 的当前字段值,在你做修改之后调 `recordEdits(against:source:in:)`,
/// 自动把每个变化的字段写一条 EditLog 插入 modelContext。
/// 用法:
/// ```
/// let snap = ItemFieldSnapshot(item)
/// item.name = newName
/// item.model = newModel
/// snap.recordEdits(against: item, source: "ai_claude", in: context)
/// ```
struct ItemFieldSnapshot {
    let name: String
    let model: String?
    let version: String?
    let color: String?
    let purchaseDate: Date?
    let purchaseDatePrecision: String?
    let purchaseSource: String?
    let notes: String

    init(_ item: Item) {
        name = item.name
        model = item.model
        version = item.version
        color = item.color
        purchaseDate = item.purchaseDate
        purchaseDatePrecision = item.purchaseDatePrecision
        purchaseSource = item.purchaseSource
        notes = item.notes
    }

    /// 对比快照和当前 item,把变化点写成 EditLog。
    /// 位置变更 **不在这里记** —— 已有 LocationLog 体系。
    /// 标签变更也不在这里记(标签是关系,差分粒度复杂,暂不上)。
    @discardableResult
    func recordEdits(against item: Item, source: String, in context: ModelContext) -> Int {
        let now = Date.now
        var count = 0
        func log(field: String, oldRaw: String?, newRaw: String?) {
            // 把空串视同 nil,跟 ItemEditView 的 optionalString 行为一致;
            // 避免 "" vs nil 触发假阳性 diff。
            let oldN = (oldRaw?.isEmpty ?? true) ? nil : oldRaw
            let newN = (newRaw?.isEmpty ?? true) ? nil : newRaw
            guard oldN != newN else { return }
            let entry = EditLog(
                recordedAt: now, source: source, field: field,
                oldValue: oldN, newValue: newN, item: item
            )
            context.insert(entry)
            count += 1
        }
        log(field: "name",           oldRaw: name,           newRaw: item.name)
        log(field: "model",          oldRaw: model,          newRaw: item.model)
        log(field: "version",        oldRaw: version,        newRaw: item.version)
        log(field: "color",          oldRaw: color,          newRaw: item.color)
        log(field: "purchaseSource", oldRaw: purchaseSource, newRaw: item.purchaseSource)
        log(field: "notes",          oldRaw: notes,          newRaw: item.notes)
        // 日期带精度一起 stringify 比较 —— 否则同一日期不同精度会被当作"没变"。
        log(
            field: "purchaseDate",
            oldRaw: formatPurchaseDate(purchaseDate, precision: purchaseDatePrecision),
            newRaw: formatPurchaseDate(item.purchaseDate, precision: item.purchaseDatePrecision)
        )
        return count
    }
}
