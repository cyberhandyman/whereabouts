import Foundation
import SwiftData

/// Phase 17:`Location.resolve(path:in:)` 的三种结果。
/// 调用方按 case 分别处理:
///   - `.create`        → 没有现成的匹配,落到 `Location.ensure` 建新树。
///   - `.useExisting`   → 唯一匹配,静默复用,不打扰用户。
///   - `.ambiguous`     → 多个同名 leaf,需要弹窗让用户挑一个。
enum LocationResolution {
    case create(path: [String])
    case useExisting(Location)
    case ambiguous([Location], originalLeaf: String)
}

/// 树状位置:"家" → "卧室" → "五斗柜" → "第二格抽屉"。
/// 用 parent 引用,避免冗余字符串路径,改名时整棵子树跟着改。
@Model
final class Location {
    var name: String
    var parent: Location?

    /// 反向关系:这个位置下属的子位置。
    @Relationship(deleteRule: .cascade, inverse: \Location.parent)
    var children: [Location] = []

    /// 这个位置直接放着的物品(不包含子位置里的)。
    @Relationship(deleteRule: .nullify, inverse: \Item.location)
    var items: [Item] = []

    init(name: String, parent: Location? = nil) {
        self.name = name
        self.parent = parent
    }

    /// 拼出可读路径 "家 > 卧室 > 五斗柜"。
    var path: String {
        var parts: [String] = [name]
        var cursor = parent
        while let p = cursor {
            parts.append(p.name)
            cursor = p.parent
        }
        return parts.reversed().joined(separator: " > ")
    }

    /// Phase 17:对用户给的 path 做"消歧解析"。
    /// 触发场景:用户输入 "iphone 在 抽屉第一层" 时,如果库里有
    ///   "卧室 → 抽屉第一层" 和 "书房 → 抽屉第一层" 两个同名叶子,
    /// 不该直接建新顶层,而应让用户挑一个。
    /// 仅对**单段** path 做这一步;多段(用户已自带父级)走 ensure 的旧语义。
    static func resolve(path: [String], in context: ModelContext) -> LocationResolution {
        guard !path.isEmpty else { return .create(path: path) }
        // 多段路径用户已经写清楚层级,直接交给 ensure(同 parent 复用,缺失即建)
        if path.count > 1 { return .create(path: path) }

        let leaf = path[0].trimmingCharacters(in: .whitespaces)
        guard !leaf.isEmpty else { return .create(path: path) }

        let all: [Location] = (try? context.fetch(FetchDescriptor<Location>())) ?? []
        // 全库找所有 name == leaf 的 Location(无论深浅)
        let matches = all.filter { $0.name == leaf }

        switch matches.count {
        case 0:  return .create(path: path)        // 没现成的 → 建顶层
        case 1:  return .useExisting(matches[0])   // 唯一匹配 → 静默复用(节省键入)
        default: return .ambiguous(matches, originalLeaf: leaf)
        }
    }

    /// Phase 81:把 path 数组里每段内部的 `>` / `》` / `→` / `->` / `/` 拆开,
    /// trim 空白,过滤空段。
    ///
    /// 上下文:AI 偶尔会把多层路径塞进单段(`["书房 > 绿色随身无线充盒子"]`),
    /// 直接 ensure 会建一个 name 含 `>` 的脏 Location。这里在 ensure / bestMatchOrEnsure
    /// 入口先 sanitize,把它们当作正常的 ["书房", "绿色随身无线充盒子"] 处理。
    static func sanitizePath(_ raw: [String]) -> [String] {
        var out: [String] = []
        for seg in raw {
            let normalized = seg
                .replacingOccurrences(of: "》", with: ">")
                .replacingOccurrences(of: "→", with: ">")
                .replacingOccurrences(of: "->", with: ">")
                .replacingOccurrences(of: "/", with: ">")
            for piece in normalized.split(separator: ">") {
                let t = piece.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { out.append(t) }
            }
        }
        return out
    }

    /// 沿路径走/建 Location 树。复用规则:同 parent 下、name 完全相等 = 同一个。
    /// path 为空返回 nil。
    ///
    /// Phase 60:复用判断用**不区分大小写 / 不区分全半角**的比较 —— 这样
    /// "MUJI塑料盒Hifi零件"(小写 f)能命中库里的 "MUJI塑料盒HiFi零件"(大写 F)。
    /// 真正落库时仍用 raw 输入的写法 —— 命中后 ensure 用 existing 节点,不改它的 name。
    ///
    /// Phase 81:先走 sanitizePath 拆每段里可能存在的 `>` —— 防止生成 name 含 `>` 的脏节点。
    static func ensure(path rawPath: [String], in context: ModelContext) -> Location? {
        let path = sanitizePath(rawPath)
        guard !path.isEmpty else { return nil }
        let all: [Location] = (try? context.fetch(FetchDescriptor<Location>())) ?? []
        var parent: Location? = nil
        for raw in path {
            let name = raw.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let nameFold = name.foldedForMatch
            let existing = all.first { loc in
                guard loc.name.foldedForMatch == nameFold else { return false }
                switch (loc.parent, parent) {
                case (nil, nil):                  return true
                case let (lp?, p?) where lp === p: return true
                default:                          return false
                }
            }
            if let e = existing {
                parent = e
            } else {
                let new = Location(name: name, parent: parent)
                context.insert(new)
                parent = new
            }
        }
        return parent
    }

    /// Phase 60:给 AI 用的"模糊反查 + 最长匹配"。
    ///
    /// 场景:AI 返回 `locationPath: ["书房", "MUJI塑料盒"]`,但库里真实有
    /// `书房 > MUJI塑料盒 > HiFi 零件`(更深的路径)。如果直接 ensure([书房, MUJI塑料盒])
    /// 就丢了"HiFi 零件"那一层。这个函数尝试在**与 path 一致的祖先链**下,
    /// 找一个**最深**的现存 Location 作为返回值(只要 AI 路径是其祖先链前缀)。
    ///
    /// 同时,比较都用 `foldedForMatch`(大小写/全半角不敏感),修 MUJI bug。
    ///
    /// 找不到任何 case-insensitive 匹配 → 退化到 `ensure(path:)` 走原行为(新建)。
    /// 找到 case-insensitive 匹配但没有更深唯一子节点 → 返回那个匹配本身。
    ///
    /// Phase 68:加两层 fallback,解决 AI 把"得力塑料抽屉第三层"拆成
    /// `["得力塑料抽屉","第三层"]` 时找不到已有节点的 bug:
    ///   - **合并相邻段**:当层直接匹配失败 → 把 path 剩余段 join 起来在**当层**查
    ///   - **全局兜底**:cursor==nil 时还失败 → 全库找 foldedForMatch == joined 的位置,
    ///     正好 1 个就用它(用户输的位置很可能在某个房间下,AI 没给房间名)
    ///
    /// 调用方:AI 的 applyAIResult 当 result.locationPath 非空时走这个,不走 ensure。
    ///
    /// Phase 81:走 sanitizePath 先把段内部 `>` 拆开 —— AI 偶尔返回
    /// ["书房 > 绿色随身无线充盒子"] 这种单段含分隔符的脏数据。
    static func bestMatchOrEnsure(path rawPath: [String], in context: ModelContext) -> Location? {
        let path = sanitizePath(rawPath)
        guard !path.isEmpty else { return nil }
        let all: [Location] = (try? context.fetch(FetchDescriptor<Location>())) ?? []

        // 当层候选(parent 是 cursor 的;cursor==nil 时是所有根)
        func levelCandidates(of cursor: Location?) -> [Location] {
            if let c = cursor { return c.children }
            return all.filter { $0.parent == nil }
        }
        // 把 path[index...] 合并成单一名字(去空白)
        func joinedTail(from index: Int) -> String {
            path[index...]
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined()
        }

        var cursor: Location? = nil
        var index = 0
        while index < path.count {
            let raw = path[index].trimmingCharacters(in: .whitespaces)
            if raw.isEmpty { index += 1; continue }
            let nameFold = raw.foldedForMatch
            let level = levelCandidates(of: cursor)

            // 1) 当层 direct match
            if let m = level.first(where: { $0.name.foldedForMatch == nameFold }) {
                cursor = m
                index += 1
                continue
            }

            // 2) Phase 68:**合并剩余段** —— 当层若有名字等于 joined 的节点,用它收尾
            if index < path.count - 1 {
                let joined = joinedTail(from: index).foldedForMatch
                if let m = level.first(where: { $0.name.foldedForMatch == joined }) {
                    return descendUniqueChain(from: m)
                }
            } else {
                // 末尾一段也走 joined 比 ——等价于 direct match,但保留对称性。
                // 实际上 index == path.count-1 时 joinedTail == raw,上面 direct match 已覆盖。
            }

            // 3) Phase 68:**全局兜底** —— cursor==nil 时,在整库找 foldedForMatch
            //    等于 joined 的;正好 1 个就用它(AI 漏了房间名,但用户已有这个叶子)。
            if cursor == nil {
                let joined = joinedTail(from: index).foldedForMatch
                let matches = all.filter { $0.name.foldedForMatch == joined }
                if matches.count == 1 {
                    return descendUniqueChain(from: matches[0])
                }
            }

            // 都没命中 → 老行为 ensure(从头建)
            return ensure(path: path, in: context)
        }

        // 全部 walk 成功 → 在唯一子孙链路上自动下钻一下,返回最深
        guard let leaf = cursor else { return nil }
        return descendUniqueChain(from: leaf)
    }

    /// 沿"独苗"子链一直往下走,直到分叉或没有子。
    /// 多个子时停下 —— 不擅自帮 user 选 branch。
    private static func descendUniqueChain(from start: Location) -> Location {
        var deepest = start
        while deepest.children.count == 1 {
            deepest = deepest.children[0]
        }
        return deepest
    }

    /// Phase 76:启动时跑一次的迁移 —— 合并 fold-match(忽略大小写/全半角)同名的**根**位置。
    ///
    /// 历史 bug:早期 Phase 60 还没生效时,case-sensitive 的 ensure 路径会把"书房"和"书房 "
    /// (尾空格)、"书房" vs "Ｓtudy" 之类视为不同的根,产生重复根。filter facet 表现就是
    /// 同名"书房"显示两次,各自的物品互不相关。
    ///
    /// 算法:
    ///   1. 抓所有 parent==nil 的根 Location
    ///   2. 按 foldedForMatch 分组
    ///   3. 每组多于 1 个时,选 subtree 内 item 数最多的当 survivor
    ///   4. 其它 dup:
    ///      - 把 dup.items 重指 survivor(item.location = survivor)
    ///      - 把指向 dup 的 LocationLog.location 重指 survivor
    ///      - 把 dup.children 一棵棵 reparent 到 survivor —— 若 survivor 已有 fold-match 同名
    ///        子节点 → 递归合并;否则直接 reparent
    ///      - 删除 dup
    ///
    /// 返回合并掉的 Location 数(给调用方 toast 显示用)。
    @MainActor
    static func mergeDuplicateRoots(in context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<Location>())) ?? []
        let roots = all.filter { $0.parent == nil }
        var groups: [String: [Location]] = [:]
        for r in roots {
            groups[r.name.foldedForMatch, default: []].append(r)
        }
        var merged = 0
        for (_, group) in groups where group.count > 1 {
            // survivor = subtree 物品最多的那个
            let survivor = group.max(by: { subtreeItemCount($0) < subtreeItemCount($1) }) ?? group[0]
            for dup in group where dup !== survivor {
                mergeInto(survivor: survivor, dup: dup, in: context)
                merged += 1
            }
        }
        return merged
    }

    /// subtree(含自己)上挂的物品总数。用于 mergeDuplicateRoots 挑 survivor。
    private static func subtreeItemCount(_ loc: Location) -> Int {
        var sum = loc.items.count
        for child in loc.children {
            sum += subtreeItemCount(child)
        }
        return sum
    }

    /// Phase 82:启动时跑的脏数据清理 —— 找出所有 `name` 内部含 `>` / `》` / `→` 的
    /// Location,把它们的真实路径(name 里的多段)展开成正常的多层 Location 树,
    /// 然后把 items / children / LocationLog 重指到正确的叶子,删除原脏节点。
    ///
    /// 历史来源:早期 AI 偶尔返回 ["书房 > 绿色随身无线充盒子"] —— 单段含分隔符,
    /// 老的 ensure 直接当成 name 落库,导致 facet 里出现 "书房 > X" 当根。
    /// Phase 81 之后新数据不会再脏,这一步只是清存量。
    /// 这一步**幂等**,可每次启动跑;一旦数据干净就 noop。
    @MainActor
    static func splitMalformedNames(in context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<Location>())) ?? []
        var splitCount = 0
        for loc in all {
            // 只挑 name 真包含分隔符的 —— 大多数 Location 名字干净,直接跳过
            guard loc.name.contains(">") || loc.name.contains("》") || loc.name.contains("→") else {
                continue
            }
            let parts = sanitizePath([loc.name])
            guard parts.count >= 2 else {
                // sanitize 后只剩 1 段(name="书房 >" 这种残留分隔符)→ 把名字归一,不分裂
                loc.name = parts.first ?? loc.name
                continue
            }
            // 用 loc.parent 作为新链的起点,依次 ensure / 复用 ancestors
            let originalParent = loc.parent
            var cursor: Location? = originalParent
            for p in parts {
                let pFold = p.foldedForMatch
                let level: [Location] = {
                    if let c = cursor { return c.children }
                    return all.filter { $0.parent == nil }
                }()
                if let existing = level.first(where: { $0.name.foldedForMatch == pFold && $0 !== loc }) {
                    cursor = existing
                } else {
                    let newNode = Location(name: p, parent: cursor)
                    context.insert(newNode)
                    cursor = newNode
                }
            }
            // cursor 是新链的真正叶子 —— 把脏 loc 的 items / children / logs 全部迁过去
            guard let leaf = cursor, leaf !== loc else { continue }
            for item in loc.items {
                item.location = leaf
                item.updatedAt = .now
            }
            // 复制 children 数组(reparent 会改原)
            for child in Array(loc.children) {
                let foldName = child.name.foldedForMatch
                if let existing = leaf.children.first(where: { $0.name.foldedForMatch == foldName }) {
                    mergeInto(survivor: existing, dup: child, in: context)
                } else {
                    child.parent = leaf
                }
            }
            // LocationLog
            let logDescriptor = FetchDescriptor<LocationLog>()
            if let allLogs = try? context.fetch(logDescriptor) {
                let locID = loc.persistentModelID
                for log in allLogs where log.location?.persistentModelID == locID {
                    log.location = leaf
                }
            }
            context.delete(loc)
            splitCount += 1
        }
        return splitCount
    }

    /// Phase 101:用户在位置管理 tab 里手动合并的入口。
    /// 把 source 整棵子树并入 target,然后删除 source。Items / children / LocationLog 全部 reparent。
    /// **不做** 名字相似性检查,完全信任用户的选择。失败返回 false(同一节点 / source 是 target 祖先时拒绝)。
    @MainActor
    @discardableResult
    static func mergeUserSelected(source: Location, into target: Location,
                                   in context: ModelContext) -> Bool {
        guard source.persistentModelID != target.persistentModelID else { return false }
        // 防止把 ancestor 合并进自己的 descendant(会产生循环)
        var cursor: Location? = target.parent
        while let c = cursor {
            if c.persistentModelID == source.persistentModelID { return false }
            cursor = c.parent
        }
        mergeInto(survivor: target, dup: source, in: context)
        return true
    }

    /// 把 dup 整棵子树合并进 survivor。递归处理子节点的同名冲突。
    /// 这是 mergeDuplicateRoots 的核心 worker —— 也用在更深层的子节点冲突合并。
    @MainActor
    private static func mergeInto(survivor: Location, dup: Location, in context: ModelContext) {
        // 1) 直接物品重指
        for item in dup.items {
            item.location = survivor
            item.updatedAt = .now
        }
        // 2) 历史 log 重指(SwiftData 的 inverse 反向关系没显式列在 Location,这里直接 fetch)
        let logDescriptor = FetchDescriptor<LocationLog>()
        if let allLogs = try? context.fetch(logDescriptor) {
            let dupID = dup.persistentModelID
            for log in allLogs where log.location?.persistentModelID == dupID {
                log.location = survivor
            }
        }
        // 3) 子节点 reparent —— 复制 children 数组(reparent 会改原数组)
        let dupChildren = Array(dup.children)
        for child in dupChildren {
            let foldName = child.name.foldedForMatch
            if let existing = survivor.children.first(where: { $0.name.foldedForMatch == foldName }) {
                // survivor 已有同名子 → 递归合并到 existing
                mergeInto(survivor: existing, dup: child, in: context)
            } else {
                child.parent = survivor
            }
        }
        // 4) 删除 dup —— 此时 dup 已无 items / children
        context.delete(dup)
    }
}

/// Phase 60:String fold helper — 不区分大小写、全半角、变音符差异的匹配。
/// 用于位置 / 物品名的模糊反查比较。
extension String {
    /// 折叠成"匹配规范":小写化 + diacritic-insensitive + width-insensitive + 去首尾空白。
    /// "HiFi零件" 和 "ＨIFI零件" 折叠后相等;"iphone" 和 "iPhone" 也相等。
    var foldedForMatch: String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: nil)
    }
}
