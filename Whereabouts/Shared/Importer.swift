import Foundation
import SwiftData

// Phase 111(iOS 版):JSON 导入逻辑从 macOS DataSettingsTab 抽出来 ——
// macOS 设置页和 iOS 设置页共用同一套 schema 解码 / 去重 / 建树 / 挂标签行为。

enum WhereaboutsImporter {

    struct Result {
        let imported: Int
        let skipped: Int
    }

    /// dedup 签名 —— "name@path"。path nil 时用 "<none>",case-sensitive 完全比对。
    /// 跨大小写不去重 —— 用户可能故意有 "iphone" / "iPhone" 两条,导入时保留。
    static func signature(name: String, locationPath: String?) -> String {
        "\(name)@\(locationPath ?? "<none>")"
    }

    /// 从 JSON data 导入。`dedup` 控制是否跳过 name+path 已存在的物品。
    /// 解码失败返回 nil(调用方弹"导入失败"提示)。
    /// schema v2 起带 tags / lentTo / lentAt / isPinned / relatedGroupID;v1 老文件 nil 跳过。
    @MainActor
    static func importJSON(_ data: Data, into context: ModelContext, dedup: Bool) -> Result? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let schema = try? decoder.decode(ExportSchema.self, from: data) else {
            return nil
        }

        // 预取已有所有 tag,按 name 缓存 —— import 时新建 tag 也加入这个 dict。
        var tagByName: [String: Tag] = [:]
        for t in (try? context.fetch(FetchDescriptor<Tag>())) ?? [] {
            tagByName[t.name] = t
        }
        // 预取已有 items 的 name+path 集合,dedup 判断用。
        var existingSignatures: Set<String> = []
        if dedup {
            let allItems: [Item] = (try? context.fetch(FetchDescriptor<Item>())) ?? []
            for it in allItems where !it.isDeleted {
                existingSignatures.insert(signature(name: it.name, locationPath: it.location?.path))
            }
        }

        var imported = 0
        var skipped = 0
        for ei in schema.items {
            let pathStr = ei.locationPath.isEmpty ? nil : ei.locationPath.joined(separator: " > ")
            if dedup {
                let sig = signature(name: ei.name, locationPath: pathStr)
                if existingSignatures.contains(sig) { skipped += 1; continue }
                existingSignatures.insert(sig)
            }
            let loc = Location.ensure(path: ei.locationPath, in: context)
            let item = Item(name: ei.name, location: loc)
            item.notes = ei.notes
            item.createdAt = ei.createdAt
            item.updatedAt = ei.updatedAt
            item.lastSeenAt = ei.lastSeenAt
            item.model = ei.model
            item.version = ei.version
            item.color = ei.color
            item.purchaseDate = ei.purchaseDate
            item.purchaseDatePrecision = ei.purchaseDatePrecision
            item.purchaseSource = ei.purchaseSource
            if let b64 = ei.photoBase64 {
                item.photoData = Data(base64Encoded: b64)
            }
            // Phase 90:新字段(v2)。v1 老文件这些都是 nil,跳过即可。
            item.isPinned = ei.isPinned ?? false
            item.lentTo = ei.lentTo
            item.lentAt = ei.lentAt
            if let gid = ei.relatedGroupID, let uuid = UUID(uuidString: gid) {
                item.relatedGroupID = uuid
            }
            if let tagNames = ei.tags {
                for n in tagNames {
                    if let existing = tagByName[n] {
                        item.tags.append(existing)
                    } else {
                        // 用户原本就有这个标签 (导出时存的) 但本机没有 → 新建,色用默认。
                        let t = Tag(name: n, colorHex: "#5AC8FA")
                        context.insert(t)
                        tagByName[n] = t
                        item.tags.append(t)
                    }
                }
            }
            context.insert(item)
            for el in ei.history {
                let logLoc = Location.ensure(path: el.locationPath, in: context)
                context.insert(LocationLog(recordedAt: el.recordedAt, location: logLoc, item: item))
            }
            imported += 1
        }
        try? context.save()
        return Result(imported: imported, skipped: skipped)
    }
}
